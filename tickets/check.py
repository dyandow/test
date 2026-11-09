"""Watch ticket sites for new listings that match a game, group size and all-in price, and push them to ntfy.

Run:  NTFY_TOPIC=my-topic python -m tickets.check
Env:  NTFY_TOPIC          (required to send; without it, alerts are only printed)
      SEATGEEK_CLIENT_ID  (optional) free key from seatgeek.com/account/develop; adds SeatGeek price alerts
      STATE_FILE          (default: tickets_state.json) - remembers what was already alerted
      LOOP_MINUTES        keep checking for this many minutes (default 0 = check once)
      INTERVAL_SECONDS    pause between checks while looping (default 60)
      DRY_RUN=1           print alerts instead of sending them
      TEST_MODE=1         ignore past alerts, so whatever matches right now gets sent (state is not changed)
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

CONFIG_FILE = Path(__file__).with_name("config.json")
USER_AGENT = "Mozilla/5.0 (ticket-watcher; personal use)"
GAMETIME_API = "https://mobile.gametime.co"
TIMEZONE = ZoneInfo("America/New_York")


def http_get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:  # include the site's explanation, e.g. a rejected API key
        raise RuntimeError(f"HTTP {exc.code}: {exc.read().decode('utf-8', 'replace')[:300]}") from None


def money(cents):
    dollars = cents / 100
    return f"${dollars:,.0f}" if dollars == int(dollars) else f"${dollars:,.2f}"


def watch_is_live(watch, today):
    """Active watches are checked until the day after the game."""
    return watch.get("active", True) and today <= date.fromisoformat(watch["date"]) + timedelta(days=1)


# --- Gametime (public listings feed its own site and app use) ---------------

def find_gametime_event(watch):
    """Return (event_id, event_url) for the watch: the pinned id, or the search result on the game's date."""
    data = http_get_json(f"{GAMETIME_API}/v1/search?" + urllib.parse.urlencode({"q": watch["search"]}))
    events = [e["event"] for e in data.get("events", [])]
    pinned = watch.get("gametime_event_id")
    for ev in events:
        if pinned and ev["id"] == pinned:
            return ev["id"], ev.get("seo_url")
    if pinned:  # not in search results (yet); listings still work by id
        return pinned, None
    for ev in events:
        if ev["datetime_local"][:10] == watch["date"] and "parking" not in ev.get("kinds", []):
            return ev["id"], ev.get("seo_url")
    raise RuntimeError(f"No Gametime event for '{watch['search']}' on {watch['date']}")


def fetch_gametime(event_id):
    return http_get_json(f"{GAMETIME_API}/v2/listings/{event_id}")


def parse_gametime(raw, event_id, event_url):
    """Normalize Gametime listings. Gametime's `total` is the per-seat price with fees, in cents."""
    listings = []
    for item in (raw.get("listings") or {}).values():
        price = item.get("price") or {}
        total = price.get("total")
        if not total:
            continue
        link = f"{event_url}/listings/{item['id']}" if event_url else f"https://gametime.co/events/{event_id}"
        listings.append({
            "site": "Gametime",
            "id": item["id"],
            "section": item.get("section", "?"),
            "row": item.get("row", "?"),
            "quantities": [int(q) for q in item.get("lots", [])],
            "per_seat_cents": int(total) + int(price.get("sales_tax") or 0),
            "url": link,
        })
    return listings


# --- SeatGeek (official API; only shows the cheapest price, not group sizes) -

def fetch_seatgeek(watch, client_id):
    """SeatGeek events on the game's date. Tries the configured search, then each team name on its own,
    and keeps only events on that date, because SeatGeek's text search can miss multi-word queries."""
    queries = [watch.get("seatgeek_search") or watch["search"]] + watch.get("seatgeek_fallback_searches", [])
    seen = {}
    for q in queries:
        params = {"client_id": client_id, "q": q, "per_page": 50,
                  "datetime_local.gte": f"{watch['date']}T00:00:00",
                  "datetime_local.lte": f"{watch['date']}T23:59:59"}
        raw = http_get_json("https://api.seatgeek.com/2/events?" + urllib.parse.urlencode(params))
        on_day = [ev for ev in raw.get("events", []) if (ev.get("datetime_local") or "")[:10] == watch["date"]]
        print(f"  SeatGeek search '{q}': {len(raw.get('events', []))} result(s), {len(on_day)} on {watch['date']}: "
              + "; ".join(f"{ev.get('title')} [{ev.get('type')}]" for ev in on_day[:5]))
        for ev in on_day:
            seen[ev["id"]] = ev
        if seen:
            break
    return {"events": list(seen.values())}


def parse_seatgeek(raw, exclude_words=("parking",)):
    """Return [(event_id, title, lowest_price_dollars, listing_count, url)] for priced events (not parking etc.)."""
    out = []
    for ev in raw.get("events", []):
        title = ev.get("title", "")
        if any(w in title.lower() for w in exclude_words):
            continue
        stats = ev.get("stats") or {}
        low = stats.get("lowest_price")
        if low:
            out.append((ev["id"], title, float(low), stats.get("listing_count"), ev.get("url")))
        else:
            print(f"  SeatGeek '{title}': no price in API stats {json.dumps(stats)[:200]}")
    return out


# --- Matching, diffing, notifying -------------------------------------------

def matches(watch, listings):
    """{key: alert} for every (listing, group size) within budget. Keys are what 'already alerted' remembers."""
    limit = round(watch["max_price_per_seat"] * 100)
    found = {}
    for lst in listings:
        if lst["per_seat_cents"] > limit:
            continue
        for qty in watch["quantities"]:
            if qty in lst["quantities"]:
                key = f"{watch['name']}|{lst['site']}|{lst['id']}|{qty}"
                found[key] = {**lst, "qty": qty}
    return found


def group_alerts(alerts):
    """Merge alerts for the same listing (e.g. it can be bought as 4 or 8) into one line each, cheapest first."""
    merged = {}
    for a in alerts:
        m = merged.setdefault((a["site"], a["id"]), {**a, "qtys": []})
        m["qtys"].append(a["qty"])
    return sorted(merged.values(), key=lambda a: (a["per_seat_cents"], a["site"]))


def format_line(a):
    qtys = sorted(a["qtys"])
    seats = " or ".join(str(q) for q in qtys)
    total = " / ".join(money(a["per_seat_cents"] * q) for q in qtys)
    return (f"{a['site']} · {seats} seats · Sec {a['section']} Row {a['row']} · "
            f"{money(a['per_seat_cents'])}/seat all-in ({total} total)")


def build_message(alerts, limit=12):
    grouped = group_alerts(alerts)
    lines = [format_line(a) for a in grouped[:limit]]
    if len(grouped) > limit:
        lines.append(f"…and {len(grouped) - limit} more")
    return "\n".join(lines), grouped


def view_actions(grouped, limit=3):
    """ntfy buttons (max 3) that open the cheapest listings."""
    buttons = []
    for a in grouped[:limit]:
        label = f"{a['site']} {money(a['per_seat_cents'])} Sec {a['section']}".replace(",", "")
        url = a["url"] + ("&" if "?" in a["url"] else "?") + f"quantity={min(a['qtys'])}"
        buttons.append(f"view, {label}, {url}")
    return "; ".join(buttons)


def send_ntfy(topic, title, message, click_url=None, actions=None):
    headers = {"Title": title.encode("utf-8"), "Tags": "ticket", "Priority": "high"}
    if click_url:
        headers["Click"] = click_url
    if actions:
        headers["Actions"] = actions
    req = urllib.request.Request(
        f"https://ntfy.sh/{topic}", data=message.encode("utf-8"), headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()


def load_state(path):
    try:
        data = json.loads(Path(path).read_text())
        return {"seen": set(data["seen"]), "lows": data.get("lows", {})}
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return None


def save_state(path, state):
    Path(path).write_text(json.dumps({"seen": sorted(state["seen"]), "lows": state["lows"]}, indent=1))


def seatgeek_alerts(watch, events, lows):
    """A SeatGeek alert fires when the cheapest seat is within budget and lower than the last one alerted."""
    alerts = []
    limit = watch["max_price_per_seat"]
    for eid, title, low, count, url in events:
        key = f"{watch['name']}|SeatGeek|{eid}"
        if low > limit:
            lows.pop(key, None)  # back over budget: the next dip alerts again
        elif key not in lows or low < lows[key]:
            lows[key] = low
            groups = " or ".join(str(q) for q in watch["quantities"])
            alerts.append((f"SeatGeek: cheapest seat now {money(low * 100)} ({count or '?'} listings). "
                           f"SeatGeek doesn't share group sizes. Open it to check {groups} together.", url))
    return alerts


class Checker:
    def __init__(self, config, topic, dry_run, test_mode, state):
        self.config, self.topic, self.dry_run, self.test_mode = config, topic, dry_run, test_mode
        self.state = state or {"seen": set(), "lows": {}}
        self.first_run = state is None or test_mode
        self.events = {}  # watch name -> (gametime event id, url), looked up once per run
        self.sent = 0

    def notify(self, title, message, click=None, actions=None):
        if self.test_mode:
            title = "TEST: " + title
        if self.dry_run:
            print(f"\n[dry run] {title}\n{message}\n[buttons] {actions}")
        else:
            send_ntfy(self.topic, title, message, click, actions)
            print(f"Sent: {title}")
        self.sent += 1

    def check_once(self, today):
        """One pass over every watch. Returns True if at least one site was checked successfully."""
        any_ok = False
        for watch in self.config["watches"]:
            if not watch_is_live(watch, today):
                continue
            ok = self.check_gametime(watch)
            ok = self.check_seatgeek(watch) or ok
            any_ok = any_ok or ok
        self.first_run = False
        return any_ok

    def check_gametime(self, watch):
        try:
            if watch["name"] not in self.events:
                self.events[watch["name"]] = find_gametime_event(watch)
            event_id, event_url = self.events[watch["name"]]
            listings = parse_gametime(fetch_gametime(event_id), event_id, event_url)
        except Exception as exc:  # keep checking other sites/watches
            print(f"[error] Gametime {watch['name']}: {exc}", file=sys.stderr)
            return False
        found = matches(watch, listings)
        new = [a for k, a in found.items() if self.test_mode or k not in self.state["seen"]]
        print(f"{datetime.now(TIMEZONE):%H:%M:%S} Gametime {watch['name']}: {len(listings)} listings, "
              f"{len(found)} match, {len(new)} new")
        if new:
            message, grouped = build_message(new)
            budget = money(round(watch["max_price_per_seat"] * 100))
            if self.first_run:
                title = f"{watch['name']}: {len(grouped)} listing(s) under {budget}/seat right now"
            else:
                title = f"{watch['name']}: {len(grouped)} NEW listing(s) under {budget}/seat"
            self.notify(title, message, grouped[0]["url"], view_actions(grouped))
        if not self.test_mode:
            # Only remember what is still listed, so a listing that is pulled and reposted alerts again.
            prefix = f"{watch['name']}|Gametime|"
            self.state["seen"] = {k for k in self.state["seen"] if not k.startswith(prefix)} | set(found)
        return True

    def check_seatgeek(self, watch):
        client_id = (os.environ.get("SEATGEEK_CLIENT_ID") or "").strip()  # pasted keys often end in a newline
        if not client_id:
            return False
        try:
            events = parse_seatgeek(fetch_seatgeek(watch, client_id))
        except Exception as exc:
            print(f"[error] SeatGeek {watch['name']}: {exc}", file=sys.stderr)
            return False
        lows = {} if self.test_mode else self.state["lows"]  # a test run reports the current price
        for text, url in seatgeek_alerts(watch, events, lows):
            self.notify(f"{watch['name']}: SeatGeek price drop", text, url)
        print(f"{datetime.now(TIMEZONE):%H:%M:%S} SeatGeek {watch['name']}: {len(events)} event(s)")
        return True


def any_live_watch():
    """True while some watch still has a game coming up (used to decide whether to keep checking)."""
    config = json.loads(CONFIG_FILE.read_text())
    today = datetime.now(TIMEZONE).date()
    return any(watch_is_live(w, today) for w in config["watches"])


def main():
    config = json.loads(CONFIG_FILE.read_text())
    topic = os.environ.get("NTFY_TOPIC")
    dry_run = os.environ.get("DRY_RUN") == "1" or not topic
    test_mode = os.environ.get("TEST_MODE") == "1"
    state_file = os.environ.get("STATE_FILE", "tickets_state.json")
    loop_minutes = float(os.environ.get("LOOP_MINUTES") or 0)
    interval = float(os.environ.get("INTERVAL_SECONDS") or 60)

    checker = Checker(config, topic, dry_run, test_mode, None if test_mode else load_state(state_file))
    deadline = time.monotonic() + loop_minutes * 60
    ever_ok = False
    while True:
        today = datetime.now(TIMEZONE).date()
        ok = checker.check_once(today)
        ever_ok = ever_ok or ok
        if not test_mode:
            save_state(state_file, checker.state)
        if test_mode or time.monotonic() + interval > deadline:
            break
        time.sleep(interval)
    if test_mode and not checker.sent and ever_ok:
        checker.notify("watcher is working", "Nothing matches your filters right now.")
    # Fail the run only if nothing at all could be checked, so GitHub emails about real breakage.
    return 0 if ever_ok else 1


if __name__ == "__main__":
    sys.exit(main())
