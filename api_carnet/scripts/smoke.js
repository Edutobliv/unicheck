// Simple smoke test against a deployed API
// Usage:
//   node api_carnet/scripts/smoke.js https://unicheck-api-qr.onrender.com
// or set BASE_URL env var

const BASE_URL = process.argv[2] || process.env.BASE_URL || 'http://localhost:3000';

async function main() {
  const ts = Date.now();
  const code = `U${ts}`;
  const email = `test${ts}@example.edu`;
  const password = 'P@ssw0rd123';

  console.log(`[1/6] Register user ${email} ...`);
  let resp = await fetch(`${BASE_URL}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, email, name: 'Smoke Test', password, program: 'SISTEMAS' }),
  });
  const regText = await resp.text();
  if (resp.status !== 200) {
    console.error('Register failed', resp.status, regText);
    process.exit(1);
  }
  const reg = JSON.parse(regText);
  console.log('Register OK:', { ephemeralCode: reg.ephemeralCode, user: reg.user?.code });

  console.log(`[2/6] Login ${email} ...`);
  resp = await fetch(`${BASE_URL}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const loginText = await resp.text();
  if (resp.status !== 200) {
    console.error('Login failed', resp.status, loginText);
    process.exit(1);
  }
  const login = JSON.parse(loginText);
  const token = login.token;
  if (!token) {
    console.error('No token received');
    process.exit(1);
  }
  console.log('Login OK, token length:', token.length);

  console.log('[3/6] GET /users/me/photo-url (expect null) ...');
  resp = await fetch(`${BASE_URL}/users/me/photo-url`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const pu1 = await resp.json();
  console.log('photo-url #1:', pu1);

  console.log('[4/6] PUT /users/me/photo (1x1 png) ...');
  const tiny = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
  resp = await fetch(`${BASE_URL}/users/me/photo`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ photo: tiny }),
  });
  const putText = await resp.text();
  if (resp.status !== 200) {
    console.error('PUT photo failed', resp.status, putText);
    process.exit(1);
  }
  const putRes = JSON.parse(putText);
  console.log('PUT photo OK, expiresIn:', putRes.expiresIn, 'url?', !!putRes.photoUrl);

  console.log('[5/6] GET /users/me/photo-url (expect signed URL) ...');
  resp = await fetch(`${BASE_URL}/users/me/photo-url`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const pu2 = await resp.json();
  if (!pu2.photoUrl) {
    console.error('Expected signed photoUrl');
    process.exit(1);
  }
  console.log('photo-url #2 OK');

  console.log('[6/6] DELETE /users/me/photo ...');
  resp = await fetch(`${BASE_URL}/users/me/photo`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  });
  const del = await resp.json();
  console.log('DELETE photo:', del);

  console.log('Smoke test completed successfully.');
}

main().catch((e) => {
  console.error('Smoke test error', e);
  process.exit(1);
});

