# Tee time watcher

Checks golf course tee sheets every 8 minutes and sends a push notification (via [ntfy](https://ntfy.sh))
when a new tee time opens that matches your rules.

**Current rules** (edit `teetimes/config.json`):
- Saturdays and Sundays, up to 8 days out (the Non-Cardholder booking window)
- Tee times at or before 1:10 PM (Eastern)
- At least 2 open spots
- Courses: Francis Byrne and Weequahic (ForeUP, Non-Cardholder rate)

Each notification lists the day, time and number of open spots. Tapping it opens the booking page.
The first run sends one summary of everything currently open; after that you only hear about new openings.

## Setup

1. In GitHub: **Settings → Secrets and variables → Actions → New repository secret**,
   name `NTFY_TOPIC`, value = your ntfy topic name.
2. The workflow (`.github/workflows/teetimes.yml`) runs on its own once this is on the default branch.
   To run it immediately: **Actions → Tee time watcher → Run workflow**.

## Adding a course

Add another entry to `courses` in `teetimes/config.json`. ForeUP courses need the two numbers from their
booking URL: `foreupsoftware.com/index.php/booking/<course_id>/<schedule_id>`.

## Running locally

```bash
DRY_RUN=1 python -m teetimes.check      # prints instead of notifying
python -m unittest                       # run the tests
```

## Testing that it works

**Actions → Tee time watcher → Run workflow**, tick **Test mode**, then **Run workflow**.
This ignores the 1:10 PM cutoff and sends whatever is open right now (titled "TEST"), straight from GitHub.
It doesn't change what the regular watcher remembers.

## One-tap booking (Francis Byrne)

Alerts include up to three **Book** buttons. A button opens a confirmation page where you pick the number of
players, type your PIN and press **Approve & book**. That starts the **Book tee time** workflow, which uses a
headless browser to book and pay on ForeUP exactly as you would, then notifies you: ✅ booked or ❌ why not.

Pieces: `booker/book.js` (the robot), `.github/workflows/book.yml` (runs it), `worker/worker.js` (the
confirmation page, hosted free on Cloudflare Workers).

**Safety:** nothing is booked without your PIN; a **practice run** stops right before paying; card details and
login live only in GitHub secrets and are never printed in the (public) logs.

### Setup
1. **GitHub secrets** (Settings → Secrets and variables → Actions → *Secrets*): `FOREUP_EMAIL`, `FOREUP_PASSWORD`,
   `CARD_NUMBER`, `CARD_EXP` (MM/YY), `CARD_CVC`, `CARD_ZIP`.
2. **GitHub token for the confirmation page**: github.com/settings/personal-access-tokens → *Generate new token*
   → Repository access: *Only select repositories* → this repo → Permissions: **Actions: Read and write** → Generate.
3. **Cloudflare Worker**: dash.cloudflare.com → Workers & Pages → Create → *Start with Hello World* → Deploy →
   *Edit code* → replace everything with `worker/worker.js` → Deploy. Then Settings → Variables and Secrets:
   secrets `BOOK_PIN` and `GITHUB_TOKEN`; text `GITHUB_REPO` = `dyandow/test`, `GITHUB_BRANCH` = default branch.
4. **GitHub variable** (Settings → Secrets and variables → Actions → *Variables*): `BOOKER_URL` = the worker's URL.
5. **Practice run**: Actions → Book tee time → Run workflow with an open date/time and *Practice run* ticked.

---

# Ticket watcher

Checks ticket sites **every minute, around the clock** and sends a push notification (same ntfy app) when a
**new listing** shows up that fits your group size and **all-in price per seat (fees included)**. Tap the alert to
open the listing, then buy it yourself. No logins are used.

**Currently watching** (edit `tickets/config.json`, or just tell Claude what to change):
- **UConn vs Ohio State** men's basketball, Fri Nov 13, 2026, 7:30 PM, PeoplesBank Arena, Hartford
- Seats that can be bought **4 together or 8 together**
- **$130 or less per seat, all-in**

The first run sends one summary of everything that already matches. After that you only hear about new listings.
A listing that sells or is pulled and later reposted alerts again. A game stops being checked the day after it's played.

| Site | Status |
|------|--------|
| **Gametime** | ✅ Full listings: section, row, group sizes, all-in price |
| **SeatGeek** | ⚙️ Optional. Add a free key (below). SeatGeek's public API only gives the cheapest price, not group sizes, so it alerts on price drops under your budget |
| StubHub, Ticketmaster, Vivid Seats, TickPick | ❌ No public data. They block automated checks and only open their APIs to approved partners |

### Watching another game
Add an entry to `watches` in `tickets/config.json`:
```json
{ "name": "UConn vs Marquette", "date": "2027-01-20", "search": "uconn marquette",
  "quantities": [2, 4], "max_price_per_seat": 90, "active": true }
```
`search` is what you'd type into Gametime's search box. The game is matched by `date`.
`gametime_event_id` is optional and only pins the exact event. Set `"active": false` to pause a watch.

### Setup
1. Notifications go to the existing `NTFY_TOPIC` secret. To send ticket alerts to a separate topic, add a
   `TICKETS_NTFY_TOPIC` secret.
2. *(Optional, SeatGeek)* Sign in at seatgeek.com/account/develop → create an app → copy the **Client ID** →
   add it as the repository secret `SEATGEEK_CLIENT_ID`.
3. The workflow (`.github/workflows/tickets.yml`) runs on its own once this is on the default branch.
   **Test it:** Actions → Ticket watcher → Run workflow → tick **Test mode**. It sends whatever matches now.

### Running locally
```bash
DRY_RUN=1 python -m tickets.check                               # one check, prints instead of notifying
LOOP_MINUTES=600 INTERVAL_SECONDS=30 NTFY_TOPIC=… python -m tickets.check   # keep checking on your own computer
```
