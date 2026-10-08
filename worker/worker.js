// Cloudflare Worker: the "Book it" confirmation page.
//
// GET  /?d=2026-10-10&t=07:40&s=4   -> confirmation page (players + PIN + Approve)
// POST /                            -> checks the PIN, then starts the "Book tee time" GitHub workflow
//
// Settings (Cloudflare dashboard -> your worker -> Settings -> Variables and Secrets):
//   BOOK_PIN       (secret) the code you type to approve a booking
//   GITHUB_TOKEN   (secret) fine-grained token with "Actions: Read and write" on this repo only
//   GITHUB_REPO    (text)   e.g. dyandow/test
//   GITHUB_BRANCH  (text)   the repo's default branch, e.g. main

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^\d{2}:\d{2}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'POST') return approve(request, env);
    const d = url.searchParams.get('d') || '';
    const t = url.searchParams.get('t') || '';
    const spots = Math.min(Math.max(Number(url.searchParams.get('s')) || 4, 1), 4);
    if (!DATE_RE.test(d) || !TIME_RE.test(t)) return page('Missing tee time', '<p>Open this page from a tee time alert.</p>');
    return page('Book this tee time?', form(d, t, spots));
  },
};

async function approve(request, env) {
  const body = await request.formData();
  const d = String(body.get('d') || ''), t = String(body.get('t') || '');
  const players = String(body.get('players') || '');
  const practice = body.get('practice') === 'on';
  if (!DATE_RE.test(d) || !TIME_RE.test(t) || !/^[1-4]$/.test(players)) {
    return page('Something is off', '<p>That request was incomplete. Open the page from the alert again.</p>', 400);
  }
  if (!env.BOOK_PIN || !(await sameText(String(body.get('pin') || ''), env.BOOK_PIN))) {
    await new Promise(r => setTimeout(r, 1500)); // slow down guessing
    return page('Wrong PIN', `<p>Nothing was booked.</p><p><a href="/?d=${d}&t=${t}&s=${players}">Try again</a></p>`, 403);
  }

  const res = await fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/actions/workflows/book.yml/dispatches`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'teetime-booker',
    },
    body: JSON.stringify({
      ref: env.GITHUB_BRANCH || 'main',
      inputs: { date: d, time: t, players, practice: practice ? 'true' : 'false' },
    }),
  });
  if (!res.ok) {
    return page('Could not start booking', `<p>GitHub said: ${res.status}. Check the worker's token settings.</p>`, 502);
  }
  return page(practice ? 'Practice run started' : 'Booking started',
    `<p>${pretty(d, t)} for ${players} player${players === '1' ? '' : 's'}.</p>
     <p>You'll get a notification in about a minute saying whether it ${practice ? 'reached the payment step' : 'was booked'}.</p>`);
}

// Constant-time comparison so the PIN can't be guessed character by character.
async function sameText(a, b) {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([a, b].map(s => crypto.subtle.digest('SHA-256', enc.encode(s))));
  const x = new Uint8Array(ha), y = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

function pretty(d, t) {
  const [y, m, day] = d.split('-').map(Number);
  const [h, min] = t.split(':').map(Number);
  const date = new Date(Date.UTC(y, m - 1, day)).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric', timeZone: 'UTC' });
  return `${date} at ${h % 12 || 12}:${String(min).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

function form(d, t, spots) {
  const options = [];
  for (let n = 1; n <= spots; n++) {
    options.push(`<label class="pill"><input type="radio" name="players" value="${n}" ${n === Math.min(2, spots) ? 'checked' : ''}><span>${n}</span></label>`);
  }
  return `
    <p class="when">Francis Byrne<br><strong>${pretty(d, t)}</strong></p>
    <form method="post">
      <input type="hidden" name="d" value="${d}"><input type="hidden" name="t" value="${t}">
      <p class="label">Players (${spots} open)</p>
      <div class="pills">${options.join('')}</div>
      <p class="label">PIN</p>
      <input class="pin" type="password" name="pin" inputmode="numeric" autocomplete="off" required>
      <label class="practice"><input type="checkbox" name="practice"> Practice run (stop before paying)</label>
      <button type="submit">Approve &amp; book</button>
      <p class="note">Your card is charged when the booking goes through. Cancel at least 12 hours ahead to avoid a no-show fee.</p>
    </form>`;
}

function page(title, content, status = 200) {
  return new Response(`<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<style>
  :root { --bg:#f5f6f4; --card:#fff; --text:#1d2a1f; --muted:#5f6b61; --accent:#2e7d32; --line:#d9ded9; }
  @media (prefers-color-scheme: dark) { :root { --bg:#121513; --card:#1c211d; --text:#e8ece8; --muted:#a3ada4; --accent:#66bb6a; --line:#323a33; } }
  body { margin:0; background:var(--bg); color:var(--text); font:17px/1.45 -apple-system, system-ui, sans-serif; }
  main { max-width:420px; margin:0 auto; padding:24px 16px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:20px; }
  h1 { font-size:22px; margin:0 0 12px; }
  .when strong { font-size:20px; }
  .label { margin:18px 0 8px; color:var(--muted); font-size:14px; text-transform:uppercase; letter-spacing:.04em; }
  .pills { display:flex; gap:8px; }
  .pill { flex:1; } .pill input { display:none; }
  .pill span { display:block; text-align:center; padding:12px 0; border:1px solid var(--line); border-radius:10px; font-weight:600; }
  .pill input:checked + span { background:var(--accent); border-color:var(--accent); color:#fff; }
  .pin { width:100%; box-sizing:border-box; font-size:22px; padding:12px; border:1px solid var(--line); border-radius:10px; background:var(--bg); color:var(--text); }
  .practice { display:block; margin:16px 0; color:var(--muted); }
  button { width:100%; padding:15px; font-size:18px; font-weight:700; border:0; border-radius:12px; background:var(--accent); color:#fff; }
  .note { color:var(--muted); font-size:13px; margin-top:14px; }
  a { color:var(--accent); }
</style></head><body><main><div class="card"><h1>${title}</h1>${content}</div></main></body></html>`,
    { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
}
