import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '.env') });
import { Pool } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import { promises as dns } from 'node:dns';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.warn('[db] DATABASE_URL no definido. Configura api_carnet/.env');
}

let pool; // lazy singleton

async function createPool() {
  // Prefer IPv4: resolve DB host to A record and connect by IP to avoid IPv6 ENETUNREACH on some hosts
  try {
    const url = new URL(connectionString);
    const host = url.hostname;
    const port = Number(url.port || 5432);
    const user = decodeURIComponent(url.username || '');
    const password = decodeURIComponent(url.password || '');
    const database = url.pathname?.replace(/^\//, '') || 'postgres';
    const { address } = await dns.lookup(host, { family: 4 });
    return new Pool({
      host: address,
      port,
      user,
      password,
      database,
      ssl: { rejectUnauthorized: false },
    });
  } catch (e) {
    // Fallback to connectionString if anything fails
    return new Pool({ connectionString, ssl: { rejectUnauthorized: false } });
  }
}

export async function getPool() {
  if (!pool) pool = await createPool();
  return pool;
}

export async function endPool() {
  if (pool) {
    await pool.end();
    pool = undefined;
  }
}

export async function ensureSchema() {
  const sql = `
  create table if not exists users (
    code text primary key,
    email text unique not null,
    name text not null,
    role text not null,
    program text,
    expires_at text,
    photo_url text,
    password_hash text not null,
    created_at timestamptz default now()
  );

  create table if not exists class_sessions (
    id uuid primary key,
    teacher_code text not null references users(code) on delete cascade,
    started_at timestamptz not null default now(),
    expires_at timestamptz
  );

  create table if not exists attendance (
    id uuid primary key,
    session_id uuid not null references class_sessions(id) on delete cascade,
    student_code text not null references users(code) on delete cascade,
    at timestamptz not null default now(),
    constraint attendance_unique unique(session_id, student_code)
  );

  create table if not exists used_jti (
    jti text primary key,
    used boolean not null default false,
    expires_at timestamptz not null
  );
  create index if not exists used_jti_expires_idx on used_jti (expires_at);
  `;
  const p = await getPool();
  await p.query(sql);
}

function mapUserRow(row) {
  if (!row) return null;
  return {
    code: row.code,
    email: row.email,
    name: row.name,
    role: row.role,
    program: row.program ?? undefined,
    expiresAt: row.expires_at ?? undefined,
    photoUrl: row.photo_url ?? undefined,
    passwordHash: row.password_hash,
    createdAt: row.created_at ? Math.floor(new Date(row.created_at).getTime() / 1000) : undefined,
  };
}

export async function getUserByEmail(email) {
  const p = await getPool();
  const { rows } = await p.query('select * from users where email=$1', [email]);
  return mapUserRow(rows[0]);
}

export async function getUserByCode(code) {
  const p = await getPool();
  const { rows } = await p.query('select * from users where code=$1', [code]);
  return mapUserRow(rows[0]);
}

export async function userExistsByEmailOrCode(email, code) {
  const p = await getPool();
  const { rows } = await p.query('select 1 from users where email=$1 or code=$2 limit 1', [email, code]);
  return rows.length > 0;
}

export async function createUser({ code, email, name, role, program, expiresAt, photoUrl, passwordHash }) {
  const p = await getPool();
  const { rows } = await p.query(
    `insert into users (code, email, name, role, program, expires_at, photo_url, password_hash)
     values ($1,$2,$3,$4,$5,$6,$7,$8)
     returning *`,
    [code, email, name, role, program || null, expiresAt || null, photoUrl || null, passwordHash]
  );
  return mapUserRow(rows[0]);
}

export async function updateUserPhotoPath(userCode, photoPath) {
  const p = await getPool();
  const { rows } = await p.query(
    'update users set photo_url=$2 where code=$1 returning *',
    [userCode, photoPath]
  );
  return mapUserRow(rows[0]);
}

export async function storeJti(jti, expTs) {
  const expiresAt = new Date(expTs * 1000);
  const p = await getPool();
  await p.query('insert into used_jti (jti, expires_at, used) values ($1,$2,false) on conflict (jti) do nothing', [jti, expiresAt]);
}

export async function findJti(jti) {
  const p = await getPool();
  const { rows } = await p.query('select * from used_jti where jti=$1', [jti]);
  return rows[0] || null;
}

export async function markJtiUsed(jti) {
  const p = await getPool();
  await p.query('update used_jti set used=true where jti=$1', [jti]);
}

function mapSessionRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    teacherCode: row.teacher_code,
    startedAt: row.started_at ? Math.floor(new Date(row.started_at).getTime() / 1000) : undefined,
    expiresAt: row.expires_at ? Math.floor(new Date(row.expires_at).getTime() / 1000) : null,
  };
}

export async function createSessionWithId(id, teacherCode, startedAt, expiresAt) {
  const sa = startedAt ? new Date(startedAt * 1000) : new Date();
  const ea = expiresAt ? new Date(expiresAt * 1000) : null;
  const p = await getPool();
  const { rows } = await p.query(
    'insert into class_sessions (id, teacher_code, started_at, expires_at) values ($1,$2,$3,$4) returning *',
    [id, teacherCode, sa, ea]
  );
  return mapSessionRow(rows[0]);
}

export async function endSessionNow(sessionId, nowTs) {
  const now = nowTs ? new Date(nowTs * 1000) : new Date();
  const p = await getPool();
  const { rows } = await p.query('update class_sessions set expires_at=$2 where id=$1 returning *', [sessionId, now]);
  return mapSessionRow(rows[0] || null);
}

export async function getSession(sessionId) {
  const p = await getPool();
  const { rows } = await p.query('select * from class_sessions where id=$1', [sessionId]);
  return mapSessionRow(rows[0] || null);
}

export async function addAttendance(sessionId, studentCode, atTs) {
  const at = atTs ? new Date(atTs * 1000) : new Date();
  const id = uuidv4();
  const p = await getPool();
  await p.query(
    'insert into attendance (id, session_id, student_code, at) values ($1, $2, $3, $4) on conflict do nothing',
    [id, sessionId, studentCode, at]
  );
  const { rows } = await p.query(
    `select a.session_id, a.student_code as code, a.at,
            u.email, u.name
       from attendance a
       left join users u on u.code = a.student_code
      where a.session_id=$1 and a.student_code=$2`,
    [sessionId, studentCode]
  );
  const row = rows[0];
  return row
    ? { code: row.code, email: row.email, name: row.name, at: Math.floor(new Date(row.at).getTime() / 1000) }
    : null;
}

export async function getAttendance(sessionId) {
  const p = await getPool();
  const { rows } = await p.query(
    `select a.session_id, a.student_code as code, a.at,
            u.email, u.name
       from attendance a
       left join users u on u.code = a.student_code
      where a.session_id=$1
      order by a.at asc`,
    [sessionId]
  );
  return rows.map(r => ({ code: r.code, email: r.email, name: r.name, at: Math.floor(new Date(r.at).getTime() / 1000) }));
}

export async function getAttendanceEntry(sessionId, studentCode) {
  const p = await getPool();
  const { rows } = await p.query('select at from attendance where session_id=$1 and student_code=$2', [sessionId, studentCode]);
  if (!rows[0]) return null;
  return { at: Math.floor(new Date(rows[0].at).getTime() / 1000) };
}

export async function seedUsersIfEmpty(seedList = []) {
  // If there are any users, do nothing
  const p = await getPool();
  const { rows } = await p.query('select count(*)::int as c from users');
  if (rows[0]?.c > 0) return;
  for (const u of seedList) {
    await createUser({
      code: u.code,
      email: u.email,
      name: u.name,
      role: u.role,
      program: u.program,
      expiresAt: u.expiresAt,
      photoUrl: u.photoUrl,
      passwordHash: u.passwordHash,
    });
  }
}
