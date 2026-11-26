// Mint a 1h GitHub App installation token for Renovate (Renovate can't use an App key directly).
// Prints shell exports consumed by `eval` in the CronJob. Node built-ins only.
const crypto = require('crypto');
const appId = process.env.GITHUB_APP_ID;
const key = process.env.GITHUB_APP_PRIVATE_KEY;
const repo = process.env.RENOVATE_REPOSITORIES.split(',')[0].trim();
const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = b64({ alg: 'RS256', typ: 'JWT' }) + '.' + b64({ iat: now - 60, exp: now + 540, iss: appId });
const jwt = unsigned + '.' + crypto.sign('RSA-SHA256', Buffer.from(unsigned), key).toString('base64url');
const gh = async (path, auth, method = 'GET') => {
  const r = await fetch(`https://api.github.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${auth}`, Accept: 'application/vnd.github+json',
               'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'homelab-renovate' },
  });
  const body = await r.json();
  if (!r.ok) throw new Error(`${method} ${path} -> ${r.status}: ${body.message}`);
  return body;
};
(async () => {
  const app = await gh('/app', jwt);
  const inst = await gh(`/repos/${repo}/installation`, jwt);
  const { token } = await gh(`/app/installations/${inst.id}/access_tokens`, jwt, 'POST');
  const bot = await gh(`/users/${app.slug}%5Bbot%5D`, token);
  const author = `${app.slug}[bot] <${bot.id}+${app.slug}[bot]@users.noreply.github.com>`;
  console.error(`minted installation token for ${app.slug} (installation ${inst.id})`);
  process.stdout.write(`export RENOVATE_TOKEN=${JSON.stringify(token)}\n`);
  process.stdout.write(`export RENOVATE_GIT_AUTHOR=${JSON.stringify(author)}\n`);
})().catch((e) => { console.error(e.message); process.exit(1); });
