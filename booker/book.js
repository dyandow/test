// Books one ForeUP tee time by driving the public booking site the way a person would.
//
// Inputs (env):  BOOK_DATE=2026-10-10  BOOK_TIME=07:40  BOOK_PLAYERS=2  DRY_RUN=1 (stop before paying)
// Secrets (env): FOREUP_EMAIL FOREUP_PASSWORD CARD_NUMBER CARD_EXP (MM/YY) CARD_CVC CARD_ZIP NTFY_TOPIC
//
// The repo is public, so this script never logs or screenshots personal details: only step names.

const { chromium } = require('playwright');

const BOOKING_URL = 'https://foreupsoftware.com/index.php/booking/22528/11078#/teetimes';
const BOOKING_CLASS = 'Non-Cardholders';
const COURSE = 'Francis Byrne';

const env = process.env;
const dryRun = env.DRY_RUN === '1' || env.DRY_RUN === 'true';
const [year, month, day] = (env.BOOK_DATE || '').split('-');
const [hour24, minute] = (env.BOOK_TIME || '').split(':').map(Number);
const players = Number(env.BOOK_PLAYERS);

const tileLabel = `${hour24 % 12 || 12}:${String(minute).padStart(2, '0')}${hour24 < 12 ? 'am' : 'pm'}`;
const when = new Date(Number(year), Number(month) - 1, Number(day))
  .toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
const summary = `${when} · ${tileLabel.replace(/(am|pm)$/, m => ' ' + m.toUpperCase())} · ${players} players`;
const runUrl = env.GITHUB_RUN_ID
  ? `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}` : undefined;

let step = 'starting';
const log = s => { step = s; console.log(`[step] ${s}`); };

async function notify(title, message, click) {
  if (!env.NTFY_TOPIC) return console.log(`[notify] ${title}: ${message}`);
  const headers = { Title: title, Tags: 'golf', Priority: 'high' };
  if (click) headers.Click = click;
  await fetch(`https://ntfy.sh/${env.NTFY_TOPIC}`, { method: 'POST', body: message, headers });
}

// Card fields live in the payment processor's iframes, so look through every frame.
async function fillAcrossFrames(page, placeholder, value) {
  for (const frame of page.frames()) {
    const input = frame.locator(`input[placeholder*="${placeholder}" i]`).first();
    if (await input.count() && await input.isVisible().catch(() => false)) {
      await input.click();
      await input.pressSequentially(value, { delay: 40 });
      return;
    }
  }
  throw new Error(`card field "${placeholder}" not found`);
}

async function visibleError(page) {
  const alert = page.locator('.modal .alert-danger:visible').first();
  return (await alert.count()) ? (await alert.innerText()).trim().slice(0, 200) : null;
}

async function book(page) {
  log('open booking site');
  await page.goto(BOOKING_URL, { waitUntil: 'networkidle' });

  log(`choose ${BOOKING_CLASS}`);
  const classButton = page.getByRole('button', { name: BOOKING_CLASS, exact: true });
  if (await classButton.count()) await classButton.first().click();

  log('pick date');
  const dateMenu = page.locator('#date-menu');
  await dateMenu.waitFor({ state: 'attached', timeout: 20000 });
  const dateValue = `${month}-${day}-${year}`;
  if (!(await dateMenu.locator(`option[value="${dateValue}"]`).count())) {
    throw new Error(`${when} isn't bookable yet (outside the booking window)`);
  }
  await dateMenu.selectOption(dateValue);

  log('find tee time');
  await page.locator('.time h4.start').first().waitFor({ timeout: 20000 }).catch(() => {});
  const tile = page.locator('.time')
    .filter({ has: page.locator('h4.start', { hasText: new RegExp(`^\\s*${tileLabel}\\s*$`) }) }).first();
  if (!(await tile.count())) throw new Error('that tee time is gone (someone else booked it)');
  await tile.click();

  log('log in');
  const loginEmail = page.locator('#login_email');
  const playerButtons = page.locator('.modal .players');
  await Promise.race([loginEmail.waitFor({ timeout: 15000 }), playerButtons.waitFor({ timeout: 15000 })]);
  if (await loginEmail.isVisible()) {
    await loginEmail.fill(env.FOREUP_EMAIL);
    await page.locator('#login_password').fill(env.FOREUP_PASSWORD);
    await page.locator('.modal').getByRole('button', { name: 'Log In', exact: true }).click();
    await playerButtons.waitFor({ timeout: 20000 }).catch(async () => {
      throw new Error((await visibleError(page)) || 'login failed');
    });
  }

  log(`select ${players} players`);
  const playerButton = page.locator(`.modal .players a[data-value="${players}"]`);
  if (!(await playerButton.count())) throw new Error(`fewer than ${players} spots are left on that time`);
  await playerButton.click();
  await page.locator('.modal .js-book-button').click();

  log('choose Pay Online');
  const payOnline = page.locator('.modal').getByText('Pay Online', { exact: false }).first();
  await payOnline.waitFor({ timeout: 20000 });
  await payOnline.click();
  await page.locator('.modal button.continue:visible, .modal button:has-text("Book Time"):visible').first().click();

  log('enter card');
  await page.waitForTimeout(3000); // let the payment iframes load
  await fillAcrossFrames(page, 'Card Number', env.CARD_NUMBER);
  await fillAcrossFrames(page, 'MM', env.CARD_EXP.replace(/\D/g, ''));
  await fillAcrossFrames(page, 'CVC', env.CARD_CVC);
  await fillAcrossFrames(page, 'Postal', env.CARD_ZIP);

  if (dryRun) {
    log('practice run: stopping before Submit (nothing was charged or booked)');
    return 'dry-run';
  }

  log('submit payment');
  await page.getByRole('button', { name: 'Submit', exact: true }).click();
  await page.getByText('Your reservation has been booked').waitFor({ timeout: 60000 }).catch(async () => {
    throw new Error((await visibleError(page)) || 'no confirmation shown after paying; check your email/ForeUP account');
  });
  log('booked');
  return 'booked';
}

(async () => {
  if (!year || Number.isNaN(minute) || !(players >= 1 && players <= 4)) {
    console.error('BOOK_DATE (YYYY-MM-DD), BOOK_TIME (HH:MM) and BOOK_PLAYERS (1-4) are required');
    process.exit(2);
  }
  console.log(`Booking ${COURSE}: ${summary}${dryRun ? ' [PRACTICE RUN]' : ''}`);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
  try {
    const result = await book(page);
    if (result === 'dry-run') {
      await notify('🧪 Practice run OK', `Reached the payment step for ${summary}. Nothing was charged.`, runUrl);
    } else {
      await notify('✅ Tee time booked!', `${COURSE}: ${summary}. Check your email for the confirmation.`);
    }
  } catch (err) {
    console.error(`[failed] at "${step}": ${err.message}`);
    await notify('❌ Booking failed', `${summary}\n${err.message} (step: ${step})`, BOOKING_URL);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();
