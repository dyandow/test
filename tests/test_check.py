import json
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path
from unittest import mock

from teetimes import check

CONFIG = {
    "timezone": "America/New_York",
    "days_ahead": 14,
    "weekdays": ["Saturday", "Sunday"],
    "latest_time": "13:10",
    "min_players": 2,
    "courses": [{"name": "Byrne", "platform": "foreup", "course_id": 1, "schedule_id": 2,
                 "booking_class": None, "booking_url": "https://example.com"}],
}
COURSE = CONFIG["courses"][0]
NOW = datetime(2026, 10, 7, 12, 0)  # a Wednesday


class FilterTests(unittest.TestCase):
    def test_target_dates_are_weekends_only(self):
        days = check.target_dates(CONFIG, date(2026, 10, 7))
        self.assertEqual(days, [date(2026, 10, 10), date(2026, 10, 11),
                                date(2026, 10, 17), date(2026, 10, 18)])

    def test_qualifying_rules(self):
        slots = check.parse_foreup([
            {"time": "2026-10-10 07:00", "available_spots": 4},  # yes
            {"time": "2026-10-10 08:00", "available_spots": 2},  # yes
            {"time": "2026-10-10 09:00", "available_spots": 1},  # too few spots
            {"time": "2026-10-10 13:10", "available_spots": 3},  # yes, exactly 1:10pm
            {"time": "2026-10-10 13:20", "available_spots": 4},  # too late
        ], COURSE)
        found = check.qualifying_slots(CONFIG, COURSE, slots, NOW)
        self.assertEqual(sorted(s["when"].strftime("%H:%M") for s in found.values()),
                         ["07:00", "08:00", "13:10"])

    def test_message_format(self):
        msg = check.build_message([{"course": "Byrne", "when": datetime(2026, 10, 10, 7, 40), "spots": 3}])
        self.assertEqual(msg, "Sat Oct 10 · 7:40 AM · 3 spots")


class TeeItUpTests(unittest.TestCase):
    def test_parse_converts_utc_and_skips_resident_only_rates(self):
        raw = [{"teetimes": [
            {"teetime": "2026-10-31T11:40:00.000Z", "maxPlayers": 4,  # 7:40 AM Eastern
             "rates": [{"name": "Resident 18", "holes": 18, "allowedPlayers": [1, 2, 3, 4]},
                       {"name": "Non-Resident 18", "holes": 18, "allowedPlayers": [1, 2]}]},
            {"teetime": "2026-10-31T12:00:00.000Z", "maxPlayers": 4,  # resident-only: skipped
             "rates": [{"name": "Resident Weekend", "holes": 18, "allowedPlayers": [1, 2, 3, 4]}]},
            {"teetime": "2026-10-31T12:10:00.000Z", "maxPlayers": 3,  # no allowedPlayers: use maxPlayers
             "rates": [{"name": "Weekend 18", "holes": 18}]},
            {"teetime": "2026-10-31T12:20:00.000Z", "maxPlayers": 4,  # 9-hole only: skipped
             "rates": [{"name": "Twilight 9", "holes": 9, "allowedPlayers": [1, 2, 3, 4]}]},
        ]}]
        slots = check.parse_teeitup(raw, {"holes": 18})
        self.assertEqual(slots, [(datetime(2026, 10, 31, 7, 40), 2), (datetime(2026, 10, 31, 8, 10), 3)])


class ButtonTests(unittest.TestCase):
    def test_book_buttons_link_to_confirmation_page(self):
        slots = [{"course": "Byrne", "when": datetime(2026, 10, 10, h, 4), "spots": 3} for h in (13, 7, 9, 8)]
        actions = check.book_actions(slots, "https://book.example.workers.dev/")
        self.assertEqual(actions.split("; "), [
            "view, Book Sat 7:04am, https://book.example.workers.dev/?d=2026-10-10&t=07%3A04&s=3",
            "view, Book Sat 8:04am, https://book.example.workers.dev/?d=2026-10-10&t=08%3A04&s=3",
            "view, Book Sat 9:04am, https://book.example.workers.dev/?d=2026-10-10&t=09%3A04&s=3",
        ])


class RunTests(unittest.TestCase):
    def run_main(self, raw_by_date, state_file):
        def fake_fetch(course, day):
            return raw_by_date.get(day.isoformat(), [])
        sent = []
        env = {"NTFY_TOPIC": "t", "STATE_FILE": str(state_file)}
        with mock.patch.dict(check.PLATFORMS, {"foreup": (fake_fetch, check.parse_foreup)}), \
             mock.patch.object(check, "send_ntfy", lambda *a, **k: sent.append(a)), \
             mock.patch.object(check, "CONFIG_FILE", self.config_path), \
             mock.patch.dict("os.environ", env), \
             mock.patch.object(check, "datetime", wraps=datetime) as dt:
            dt.now.return_value = NOW.replace(tzinfo=check.ZoneInfo("America/New_York"))
            dt.strptime = datetime.strptime
            check.main()
        return sent

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.config_path = self.tmp / "config.json"
        self.config_path.write_text(json.dumps(CONFIG))

    def test_only_new_times_alert(self):
        state = self.tmp / "state.json"
        first = self.run_main({"2026-10-10": [{"time": "2026-10-10 08:00", "available_spots": 4}]}, state)
        self.assertEqual(len(first), 1)  # first run reports what's open now
        again = self.run_main({"2026-10-10": [{"time": "2026-10-10 08:00", "available_spots": 4}]}, state)
        self.assertEqual(again, [])  # same tee time: no repeat alert
        new = self.run_main({"2026-10-10": [{"time": "2026-10-10 08:00", "available_spots": 4},
                                            {"time": "2026-10-10 09:30", "available_spots": 2}]}, state)
        self.assertEqual(len(new), 1)
        self.assertIn("9:30 AM · 2 spots", new[0][2])
        self.assertNotIn("8:00", new[0][2])


if __name__ == "__main__":
    unittest.main()
