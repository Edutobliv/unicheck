import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.TARGET_BASE_URL || 'http://localhost:3000';
const STUDENT_EMAIL = __ENV.TEST_EMAIL || '';
const STUDENT_PASSWORD = __ENV.TEST_PASSWORD || '';

export const options = {
  stages: [
    { duration: '5m', target: 10 },
    { duration: '55m', target: 20 },
    { duration: '1h', target: 30 },
    { duration: '5m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<1200'],
  },
};

export default function () {
  const headersJson = { headers: { 'Content-Type': 'application/json' } };

  const loginRes = http.post(
    `${BASE}/auth/login`,
    JSON.stringify({ email: STUDENT_EMAIL, password: STUDENT_PASSWORD }),
    headersJson
  );

  const loginOk = check(loginRes, {
    'login ok': (r) => r && r.status === 200,
  });
  if (!loginOk) {
    sleep(2);
    return;
  }

  const token = loginRes.json('token');
  const tokenOk = check(token, {
    'has token': (t) => typeof t === 'string' && t.length > 0,
  });
  if (!tokenOk) {
    sleep(2);
    return;
  }

  const authHeaders = {
    headers: {
      Authorization: `Bearer ${token}`,
    },
  };

  const meRes = http.get(`${BASE}/users/me/photo-url`, authHeaders);
  check(meRes, {
    'photo-url ok': (r) => r && r.status === 200,
  });

  const issueRes = http.post(
    `${BASE}/issue-ephemeral`,
    JSON.stringify({ deviceId: 'k6-soak' }),
    {
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
    }
  );
  const issueOk = check(issueRes, {
    'issue ok': (r) => r && r.status === 200,
  });

  let qrToken = null;
  if (issueOk) {
    qrToken = issueRes.json('token');
    check(qrToken, {
      'has qr token': (t) => typeof t === 'string' && t.length > 0,
    });
  }

  if (qrToken) {
    const verifyRes = http.post(
      `${BASE}/verify`,
      JSON.stringify({ token: qrToken, gate: 'soak-gate', direction: 'in' }),
      headersJson
    );
    check(verifyRes, {
      'verify ok': (r) => r && r.status === 200 && r.json('valid') === true,
    });
  }

  sleep(Math.random() * 2 + 1);
}
