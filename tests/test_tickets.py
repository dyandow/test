import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

from tickets import check

WATCH = {"name": "UConn vs OSU", "date": "2026-11-13", "search": "uconn ohio state",
         "gametime_event_id": "ev1", "quantities": [4, 8], "max_price_per_seat": 130}
EVENT_URL = "https://gametime.co/basketball/x/events/ev1"


def gt_listing(lid, total, lots, tax=0, section="217", row="Z"):
    return {"id": lid, "section": section, "row": row, "lots": lots,
            "price": {"prefee": total - 1000, "total": total, "sales_tax": tax}}


def gt_raw(*items):
    return {"listings": {i["id"]: i for i in items}}


class GametimeTests(unittest.TestCase):
    def test_parse_uses_all_in_total_plus_tax(self):
        [lst] = check.parse_gametime(gt_raw(gt_listing("a", 12000, [2, 4], tax=500)), "ev1", EVENT_URL)
        self.assertEqual(lst["per_seat_cents"], 12500)
        self.assertEqual(lst["quantities"], [2, 4])
        self.assertEqual(lst["url"], EVENT_URL + "/listings/a")

    def test_matching_rules(self):
        listings = check.parse_gametime(gt_raw(
            gt_listing("cheap4", 7600, [1, 2, 3, 4]),     # yes, 4
            gt_listing("both", 9800, [4, 8]),             # yes, 4 and 8
            gt_listing("exact", 13000, [8]),              # yes, exactly $130
            gt_listing("pricey", 13001, [4]),             # over budget
            gt_listing("pairs", 5000, [1, 2, 3, 5, 6]),   # can't buy 4 or 8 together
        ), "ev1", EVENT_URL)
        found = check.matches(WATCH, listings)
        self.assertEqual(sorted(found), [
            "UConn vs OSU|Gametime|both|4", "UConn vs OSU|Gametime|both|8",
            "UConn vs OSU|Gametime|cheap4|4", "UConn vs OSU|Gametime|exact|8"])

    def test_message_merges_group_sizes_and_shows_totals(self):
        listings = check.parse_gametime(gt_raw(gt_listing("both", 9800, [4, 8], section="204", row="X")),
                                        "ev1", EVENT_URL)
        message, grouped = check.build_message(list(check.matches(WATCH, listings).values()))
        self.assertEqual(message, "Gametime · 4 or 8 seats · Sec 204 Row X · $98/seat all-in ($392 / $784 total)")
        self.assertIn("quantity=4", check.view_actions(grouped))


class RunTests(unittest.TestCase):
    def run_checker(self, raw, state):
        checker = check.Checker({"watches": [WATCH]}, "topic", dry_run=False, test_mode=False, state=state)
        with mock.patch.object(check, "find_gametime_event", return_value=("ev1", EVENT_URL)), \
             mock.patch.object(check, "fetch_gametime", return_value=raw), \
             mock.patch.object(check, "send_ntfy") as send, \
             mock.patch.dict("os.environ", {}, clear=True):
            checker.check_once(date(2026, 11, 10))
        return checker, send

    def test_only_new_listings_alert(self):
        checker, send = self.run_checker(gt_raw(gt_listing("a", 7600, [4])), None)
        self.assertIn("right now", send.call_args[0][1])  # first run: summary of what's listed
        checker, send = self.run_checker(gt_raw(gt_listing("a", 7600, [4]), gt_listing("b", 9000, [8])),
                                         checker.state)
        self.assertIn("1 NEW", send.call_args[0][1])
        self.assertIn("8 seats", send.call_args[0][2])
        _, send = self.run_checker(gt_raw(gt_listing("a", 7600, [4]), gt_listing("b", 9000, [8])), checker.state)
        send.assert_not_called()

    def test_finished_games_are_skipped(self):
        self.assertTrue(check.watch_is_live(WATCH, date(2026, 11, 14)))
        self.assertFalse(check.watch_is_live(WATCH, date(2026, 11, 15)))
        self.assertFalse(check.watch_is_live({**WATCH, "active": False}, date(2026, 11, 10)))

    def test_state_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "s.json"
            check.save_state(path, {"seen": {"x"}, "lows": {"k": 99.0}})
            self.assertEqual(check.load_state(path), {"seen": {"x"}, "lows": {"k": 99.0}})


class SeatGeekTests(unittest.TestCase):
    def test_alerts_on_new_low_within_budget(self):
        lows = {}
        events = [(1, "OSU at UConn", 120.0, 300, "https://seatgeek.com/e/1")]
        self.assertEqual(len(check.seatgeek_alerts(WATCH, events, lows)), 1)
        self.assertEqual(check.seatgeek_alerts(WATCH, events, lows), [])          # same price: quiet
        events = [(1, "OSU at UConn", 110.0, 300, "https://seatgeek.com/e/1")]
        self.assertEqual(len(check.seatgeek_alerts(WATCH, events, lows)), 1)      # lower: alert
        check.seatgeek_alerts(WATCH, [(1, "", 150.0, 300, "")], lows)             # over budget resets
        self.assertEqual(len(check.seatgeek_alerts(WATCH, [(1, "", 125.0, 1, "")], lows)), 1)

    def test_parse(self):
        raw = {"events": [{"id": 5, "title": "T", "url": "u", "stats": {"lowest_price": 58, "listing_count": 9}},
                          {"id": 6, "title": "none", "stats": {"lowest_price": None}}]}
        self.assertEqual(check.parse_seatgeek(raw), [(5, "T", 58.0, 9, "u")])


if __name__ == "__main__":
    unittest.main()


LINE_CFG = {"book": "DraftKings", "sport": "basketball/mens-college-basketball",
            "teams": ["UConn", "Ohio State"], "url": "https://sportsbook.draftkings.com"}


def espn_event(odds):
    return {"id": "401", "name": "Ohio State Buckeyes at UConn Huskies", "competitions": [{
        "competitors": [{"homeAway": "home", "team": {"shortDisplayName": "UConn"}},
                        {"homeAway": "away", "team": {"shortDisplayName": "Ohio State"}}],
        "odds": odds}]}


DK = {"provider": {"name": "DraftKings"}, "details": "CONN -6.5", "overUnder": 147.5, "spread": -6.5,
      "homeTeamOdds": {"moneyLine": -275}, "awayTeamOdds": {"moneyLine": 220}}


class LineTests(unittest.TestCase):
    def test_reads_draftkings_line(self):
        line = check.find_book_line(espn_event([DK]), "DraftKings", LINE_CFG["sport"])
        self.assertEqual(check.format_line_alert(line),
                         "Spread: CONN -6.5\nTotal: 147.5\nMoneyline: Ohio State +220 / UConn -275")

    def test_not_posted_when_only_other_books_or_empty(self):
        other = {**DK, "provider": {"name": "ESPN BET"}}
        empty = {"provider": {"name": "DraftKings"}}
        with mock.patch.object(check, "http_get_json", return_value={"pickcenter": [empty]}):
            self.assertIsNone(check.find_book_line(espn_event([other]), "DraftKings", LINE_CFG["sport"]))

    def test_alerts_once(self):
        watch = {**WATCH, "line_alert": LINE_CFG}
        checker = check.Checker({"watches": [watch]}, "topic", dry_run=False, test_mode=False, state=None)
        with mock.patch.object(check, "fetch_espn_event", return_value=espn_event([DK])) as fetch, \
             mock.patch.object(check, "send_ntfy") as send:
            checker.check_line(watch)
            checker.check_line(watch)
        self.assertEqual(send.call_count, 1)
        self.assertIn("DraftKings line is up", send.call_args[0][1])
        self.assertEqual(fetch.call_count, 1)  # stops checking once alerted


class PolitenessTests(unittest.TestCase):
    def test_spacing_and_rate_limit_backoff(self):
        checker = check.Checker({"watches": []}, "topic", dry_run=True, test_mode=False, state=None)
        calls = []

        def limited():
            calls.append(1)
            checker.note_error("Gametime", RuntimeError("HTTP 429: "))
            return False

        with mock.patch.object(check.time, "monotonic", return_value=1000.0):
            checker.polite("gametime", limited)
            self.assertEqual(checker.backoff["gametime"], check.RATE_LIMIT_BACKOFF)
            self.assertTrue(checker.polite("gametime", limited))   # paused: skipped
        self.assertEqual(len(calls), 1)
        with mock.patch.object(check.time, "monotonic", return_value=1000.0 + check.RATE_LIMIT_BACKOFF):
            checker.polite("gametime", limited)                    # still limited: pause doubles
        self.assertEqual(checker.backoff["gametime"], 2 * check.RATE_LIMIT_BACKOFF)
        with mock.patch.object(check.time, "monotonic", return_value=5000.0):
            checker.polite("gametime", lambda: True)               # recovered
        self.assertNotIn("gametime", checker.backoff)
        self.assertEqual(checker.next_try["gametime"], 5000.0 + check.SPACING["gametime"])
