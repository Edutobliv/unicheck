import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 1,
  duration: '30s',
};

const BASE = __ENV.TARGET_BASE_URL || 'http://localhost:3000';
const STUDENT_EMAIL = __ENV.TEST_EMAIL || '';
const STUDENT_PASSWORD = __ENV.TEST_PASSWORD || '';
const TEACHER_EMAIL = __ENV.TEACHER_EMAIL || '';
const TEACHER_PASSWORD = __ENV.TEACHER_PASSWORD || '';

export default function () {
  const hjson = { headers: { 'Content-Type': 'application/json' } };

  const h = http.get(`${BASE}/health`);
  check(h, { 'health 200': (r) => r.status === 200 });

  // Student login
  const lr = http.post(`${BASE}/auth/login`, JSON.stringify({ email: STUDENT_EMAIL, password: STUDENT_PASSWORD }), hjson);
  check(lr, { 'login 200': (r) => r.status === 200 });
  const token = (lr.json('token') || '').toString();
  check(token, { 'got token': (t) => !!t });

  // Protected GET
  const me = http.get(`${BASE}/users/me/photo-url`, { headers: { Authorization: `Bearer ${token}` } });
  check(me, { 'me 200': (r) => r.status === 200 });

  // Issue ephemeral and verify immediately
  const ie = http.post(`${BASE}/issue-ephemeral`, JSON.stringify({ deviceId: 'k6-smoke' }), { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } });
  check(ie, { 'issue 200': (r) => r.status === 200 });
  const qrToken = (ie.json('token') || '').toString();
  const ver = http.post(`${BASE}/verify`, JSON.stringify({ token: qrToken, gate: 'k6-gate', direction: 'in' }), hjson);
  check(ver, { 'verify ok': (r) => r.status === 200 && r.json('valid') === true });

  // Teacher start-session + student check-in
  if (TEACHER_EMAIL && TEACHER_PASSWORD) {
    const tl = http.post(`${BASE}/auth/login`, JSON.stringify({ email: TEACHER_EMAIL, password: TEACHER_PASSWORD }), hjson);
    check(tl, { 'teacher login 200': (r) => r.status === 200 });
    const tkn = (tl.json('token') || '').toString();
    const ss = http.post(`${BASE}/prof/start-session`, JSON.stringify({ ttlSeconds: 120 }), { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tkn}` } });
    check(ss, { 'start session 200': (r) => r.status === 200 });
    const qrText = (ss.json('qrText') || '').toString();
    const sessionToken = qrText.startsWith('ATTEND:') ? qrText.slice('ATTEND:'.length) : '';
    const ci = http.post(`${BASE}/attendance/check-in`, JSON.stringify({ sessionToken }), { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } });
    check(ci, { 'check-in 200': (r) => r.status === 200 });
  }

  sleep(1);
}

