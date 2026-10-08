# Tee time watcher

Checks golf course tee sheets every 8 minutes and sends a push notification (via [ntfy](https://ntfy.sh))
when a new tee time opens that matches your rules.

**Current rules** (edit `teetimes/config.json`):
- Saturdays and Sundays, up to 8 days out (the Non-Cardholder booking window)
- Tee times at or before 1:10 PM (Eastern)
- At least 2 open spots
- Courses: Francis Byrne (ForeUP)

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
