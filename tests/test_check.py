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
        ])
        found = check.qualifying_slots(CONFIG, COURSE, slots, NOW)
        self.assertEqual(sorted(s["when"].strftime("%H:%M") for s in found.values()),
                         ["07:00", "08:00", "13:10"])

    def test_message_format(self):
        msg = check.build_message([{"course": "Byrne", "when": datetime(2026, 10, 10, 7, 40), "spots": 3}])
        self.assertEqual(msg, "Sat Oct 10 · 7:40 AM · 3 spots")


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
