"""Check golf courses for open weekend tee times and push new ones to ntfy.

Run:  NTFY_TOPIC=my-topic python -m teetimes.check
Env:  NTFY_TOPIC  (required to send; without it, alerts are only printed)
      STATE_FILE  (default: state.json) - remembers what was already alerted
      DRY_RUN=1   print alerts instead of sending them
"""

import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

CONFIG_FILE = Path(__file__).with_name("config.json")
USER_AGENT = "Mozilla/5.0 (tee-time-watcher; personal use)"
WEEKDAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def http_get_json(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def target_dates(config, today):
    """Every date in the next `days_ahead` days that falls on a wanted weekday."""
    wanted = {WEEKDAY_NAMES.index(d) for d in config["weekdays"]}
    days = range(config["days_ahead"] + 1)
    return [today + timedelta(n) for n in days if (today + timedelta(n)).weekday() in wanted]


# --- ForeUP -----------------------------------------------------------------

def fetch_foreup(course, day):
    """Return the raw tee time list ForeUP's booking page loads for one date."""
    params = {
        "time": "all",
        "date": day.strftime("%m-%d-%Y"),
        "holes": "all",
        "players": "0",
        "schedule_id": course["schedule_id"],
        "schedule_ids[]": course["schedule_id"],
        "specials_only": "0",
        "api_key": "no_limits",
    }
    if course.get("booking_class"):
        params["booking_class"] = course["booking_class"]
    url = "https://foreupsoftware.com/index.php/api/booking/times?" + urllib.parse.urlencode(params)
    data = http_get_json(url, headers={"Api-Key": "no_limits", "X-Requested-With": "XMLHttpRequest"})
    if not isinstance(data, list):
        # ForeUP returns an object (e.g. an error message) instead of a list on failure.
        raise RuntimeError(f"Unexpected ForeUP response for {day}: {str(data)[:300]}")
    return data


def parse_foreup(raw):
    """Normalize ForeUP entries to (datetime, open_spots)."""
    slots = []
    for entry in raw:
        when = datetime.strptime(entry["time"], "%Y-%m-%d %H:%M")
        slots.append((when, int(entry.get("available_spots") or 0)))
    return slots


PLATFORMS = {"foreup": (fetch_foreup, parse_foreup)}


# --- Filtering, diffing, notifying ------------------------------------------

def qualifying_slots(config, course, slots, now):
    latest = datetime.strptime(config["latest_time"], "%H:%M").time()
    found = {}
    for when, spots in slots:
        if spots >= config["min_players"] and when.time() <= latest and when > now:
            key = f"{course['name']}|{when:%Y-%m-%d %H:%M}"
            found[key] = {"course": course["name"], "when": when, "spots": spots}
    return found


def format_slot(slot):
    when = slot["when"]
    hour = when.strftime("%I:%M %p").lstrip("0")
    return f"{when:%a %b} {when.day} · {hour} · {slot['spots']} spots"


def build_message(new_slots):
    """Group new slots by course into one notification body."""
    lines = []
    by_course = {}
    for slot in sorted(new_slots, key=lambda s: s["when"]):
        by_course.setdefault(slot["course"], []).append(slot)
    for course, slots in by_course.items():
        if len(by_course) > 1:
            lines.append(f"{course}:")
        lines.extend(format_slot(s) for s in slots)
    return "\n".join(lines)


def send_ntfy(topic, title, message, click_url=None):
    headers = {"Title": title.encode("utf-8"), "Tags": "golf", "Priority": "high"}
    if click_url:
        headers["Click"] = click_url
    req = urllib.request.Request(
        f"https://ntfy.sh/{topic}", data=message.encode("utf-8"), headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()


def load_state(path):
    try:
        return set(json.loads(Path(path).read_text())["seen"])
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return None


def save_state(path, keys):
    Path(path).write_text(json.dumps({"seen": sorted(keys)}, indent=1))


def main():
    config = json.loads(CONFIG_FILE.read_text())
    tz = ZoneInfo(config["timezone"])
    now = datetime.now(tz).replace(tzinfo=None)
    topic = os.environ.get("NTFY_TOPIC")
    dry_run = os.environ.get("DRY_RUN") == "1" or not topic
    state_file = os.environ.get("STATE_FILE", "state.json")

    previously_seen = load_state(state_file)
    current = {}
    failures = 0
    checked_courses = set()

    for course in config["courses"]:
        fetch, parse = PLATFORMS[course["platform"]]
        course_ok = True
        for day in target_dates(config, now.date()):
            try:
                slots = parse(fetch(course, day))
            except Exception as exc:  # keep checking other dates/courses
                print(f"[error] {course['name']} {day}: {exc}", file=sys.stderr)
                failures += 1
                course_ok = False
                continue
            found = qualifying_slots(config, course, slots, now)
            print(f"{course['name']} {day:%a %m/%d}: {len(slots)} times listed, {len(found)} match")
            current.update(found)
        if course_ok:
            checked_courses.add(course["name"])

    # A course whose check failed keeps its old state, so a hiccup doesn't re-alert everything later.
    if previously_seen is not None:
        for key in previously_seen:
            if key.split("|", 1)[0] not in checked_courses:
                current.setdefault(key, None)

    first_run = previously_seen is None
    new_slots = [s for k, s in current.items() if s and k not in (previously_seen or set())]

    if new_slots:
        title = "Tee times currently open" if first_run else f"{len(new_slots)} new tee time(s) open!"
        message = build_message(new_slots)
        click = config["courses"][0]["booking_url"] if len(config["courses"]) == 1 else None
        if dry_run:
            print(f"\n[dry run] {title}\n{message}")
        else:
            send_ntfy(topic, title, message, click)
            print(f"Sent notification for {len(new_slots)} tee time(s).")
    else:
        print("No new tee times.")

    save_state(state_file, current.keys())
    # Fail the run only if nothing at all could be checked, so GitHub emails about real breakage.
    return 1 if failures and not checked_courses else 0


if __name__ == "__main__":
    sys.exit(main())
