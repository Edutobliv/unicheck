import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 20 },
    { duration: '3m', target: 100 },
    { duration: '1m', target: 200 },
    { duration: '3m', target: 100 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<800'],
  },
};

const BASE = __ENV.TARGET_BASE_URL || 'http://localhost:3000';
const STUDENT_EMAIL = __ENV.TEST_EMAIL || '';
const STUDENT_PASSWORD = __ENV.TEST_PASSWORD || '';

export default function () {
  const hjson = { headers: { 'Content-Type': 'application/json' } };
  // Login each VU iteration (stresses DB/auth)
  const lr = http.post(`${BASE}/auth/login`, JSON.stringify({ email: STUDENT_EMAIL, password: STUDENT_PASSWORD }), hjson);
  check(lr, { 'login ok': (r) => r.status === 200 });
  const token = (lr.json('token') || '').toString();
  check(token, { 'has token': (t) => !!t });

  // Protected endpoints
  const me = http.get(`${BASE}/users/me/photo-url`, { headers: { Authorization: `Bearer ${token}` } });
  check(me, { 'me 200': (r) => r.status === 200 });

  // Issue ephemeral and verify (quickly)
  const ie = http.post(`${BASE}/issue-ephemeral`, JSON.stringify({ deviceId: 'k6-stress' }), { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } });
  check(ie, { 'issue ok': (r) => r.status === 200 });
  const qrToken = (ie.json('token') || '').toString();
  const ver = http.post(`${BASE}/verify`, JSON.stringify({ token: qrToken, gate: 'k6-gate', direction: 'in' }), hjson);
  check(ver, { 'verify ok': (r) => r.status === 200 });

  sleep(0.5);
}

