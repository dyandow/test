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
