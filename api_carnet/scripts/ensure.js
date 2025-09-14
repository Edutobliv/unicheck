import { ensureSchema, pool } from '../db.js';

try {
  await ensureSchema();
  console.log('DB schema ensured');
} catch (e) {
  console.error('DB schema error:', e);
  process.exitCode = 1;
} finally {
  await pool.end();
}

