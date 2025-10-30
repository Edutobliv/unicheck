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
  // Use the connection string as-is to preserve all parameters (sslmode, options=project=...)
  // and proper TLS SNI. Add keepAlive and relaxed SSL verification.
  return new Pool({
    connectionString,
    keepAlive: true,
    application_name: process.env.PG_APP_NAME || 'unicheck-api',
    ssl: { rejectUnauthorized: false },
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 20000,
  });
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
  create extension if not exists "pgcrypto";

  create table if not exists class_offerings (
    id uuid primary key default gen_random_uuid(),
    teacher_code text not null references users(code) on delete cascade,
    name text not null,
    archived boolean not null default false,
    created_at timestamptz not null default now()
  );

  create table if not exists users (
    code text primary key,
    email text unique not null,
    name text not null,
    first_name text,
    middle_name text,
    last_name text,
    second_last_name text,
    role text not null,
    program text,
    expires_at text,
    expires_on date,
    photo_url text,
    password_hash text not null,
    created_at timestamptz default now()
  );

  create table if not exists class_sessions (
    id uuid primary key,
    teacher_code text not null references users(code) on delete cascade,
    started_at timestamptz not null default now(),
    expires_at timestamptz,
    offering_id uuid references class_offerings(id) on delete set null
  );

  create table if not exists attendance (
    id uuid primary key,
    session_id uuid not null references class_sessions(id) on delete cascade,
    student_code text not null references users(code) on delete cascade,
    at timestamptz not null default now(),
    status text not null default 'present' check (status in ('present','late','excused','absent')),
    source text not null default 'qr' check (source in ('qr','manual')),
    recorded_by text references users(code) on delete set null,
    constraint attendance_unique unique(session_id, student_code)
  );

  create table if not exists used_jti (
    jti text primary key,
    used boolean not null default false,
    expires_at timestamptz not null
  );
  create index if not exists used_jti_expires_idx on used_jti (expires_at);

  -- Refresh tokens (server-side revocation)
  create table if not exists refresh_tokens (
    jti text primary key,
    user_code text not null references users(code) on delete cascade,
    created_at timestamptz default now(),
    expires_at timestamptz not null,
    revoked boolean not null default false
  );
  create index if not exists rt_user_idx on refresh_tokens (user_code);

  -- Password reset requests
  create table if not exists password_reset_requests (
    user_code text primary key references users(code) on delete cascade,
    email text not null,
    otp_hash text not null,
    expires_at timestamptz not null,
    attempts int not null default 0,
    max_attempts int not null default 5,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );
  create index if not exists password_reset_requests_expires_idx on password_reset_requests (expires_at);

  -- Gates and access events for porter flow
  create table if not exists gates (
    id uuid primary key default gen_random_uuid(),
    code text unique not null,
    name text not null,
    location text,
    latitude double precision,
    longitude double precision,
    is_active boolean not null default true,
    created_at timestamptz default now()
  );

  create table if not exists access_events (
    id uuid primary key default gen_random_uuid(),
    scanned_at timestamptz not null default now(),
    student_code text not null references users(code) on delete cascade,
    porter_code text references users(code) on delete set null,
    gate_id uuid references gates(id) on delete set null,
    direction text check (direction in ('in','out')) default 'in',
    result text not null check (result in ('valid','expired','replayed','forbidden','unknown','invalid')),
    token_jti text,
    token_kid text,
    issuer text,
    device_id text,
    meta jsonb
  );
  create index if not exists access_events_scanned_idx on access_events (scanned_at desc);
  create index if not exists access_events_student_idx on access_events (student_code);
  `;
  const p = await getPool();
  await p.query(sql);

  try {
    await p.query(
      `alter table class_sessions
         add constraint class_sessions_offering_fk
         foreign key (offering_id)
         references class_offerings(id) on delete set null`
    );
  } catch (err) {
    const code = err && typeof err === 'object' ? err.code : null;
    if (code !== '42P16' && code !== '42710') {
      throw err;
    }
  }

  // One-time migration: fill expires_on from legacy expires_at text (DD/MM/YYYY)
  try {
    await p.query(`
      update users
         set expires_on = coalesce(expires_on, to_date(expires_at, 'DD/MM/YYYY'))
       where expires_at ~ '^[0-3]?[0-9]/[0-1]?[0-9]/[0-9]{4}$'
         and (expires_on is null);
    `);
  } catch {}
}

function mapUserRow(row) {
  if (!row) return null;
  const fmtDate = (d) => {
    if (!d) return undefined;
    // d can be string 'YYYY-MM-DD' or Date
    let y, m, day;
    if (d instanceof Date) {
      y = d.getFullYear();
      m = d.getMonth() + 1;
      day = d.getDate();
    } else if (typeof d === 'string') {
      const m1 = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d);
      if (m1) {
        y = parseInt(m1[1], 10);
        m = parseInt(m1[2], 10);
        day = parseInt(m1[3], 10);
      }
    }
    if (!y) return undefined;
    const dd = String(day).padStart(2, '0');
    const mm = String(m).padStart(2, '0');
    const yyyy = String(y);
    return `${dd}/${mm}/${yyyy}`;
  };
  return {
    code: row.code,
    email: row.email,
    name: row.name,
    firstName: row.first_name,
    middleName: row.middle_name,
    lastName: row.last_name,
    secondLastName: row.second_last_name,
    role: row.role,
    program: row.program ?? undefined,
    expiresAt: fmtDate(row.expires_on) ?? row.expires_at ?? undefined,
    photoUrl: row.photo_url ?? undefined,
    passwordHash: row.password_hash,
    createdAt: row.created_at ? Math.floor(new Date(row.created_at).getTime() / 1000) : undefined,
  };
}
function mapPasswordResetRow(row) {
  if (!row) return null;
  const toNumber = (value) => (typeof value === 'number' ? value : parseInt(String(value ?? 0), 10) || 0);
  return {
    userCode: row.user_code,
    email: row.email,
    otpHash: row.otp_hash,
    expiresAt: row.expires_at ? new Date(row.expires_at) : null,
    attempts: toNumber(row.attempts),
    maxAttempts: toNumber(row.max_attempts),
    createdAt: row.created_at ? new Date(row.created_at) : null,
    updatedAt: row.updated_at ? new Date(row.updated_at) : null,
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

export async function createUser({ code, email, name, firstName, middleName, lastName, secondLastName, role, program, expiresAt, photoUrl, passwordHash }) {
  console.log('Creating user with:', { code, email, name, firstName, middleName, lastName, secondLastName });
  const p = await getPool();
  const { rows } = await p.query(
    `insert into users (code, email, name, first_name, middle_name, last_name, second_last_name, role, program, expires_on, photo_url, password_hash)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9, to_date($10,'DD/MM/YYYY'), $11,$12)
     returning *`,
    [code, email, name, firstName || null, middleName || null, lastName || null, secondLastName || null, role, program || null, expiresAt || null, photoUrl || null, passwordHash]
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

export async function updateUserExpiry(userCode, expiresAt) {
  const p = await getPool();
  const { rows } = await p.query(
    'update users set expires_on = to_date($2,\'DD/MM/YYYY\'), expires_at = null where code=$1 returning *',
    [userCode, expiresAt]
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
    offeringId: row.offering_id || null,
  };
}

function mapOfferingRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    teacherCode: row.teacher_code,
    name: row.name,
    archived: row.archived === true,
    createdAt: row.created_at ? Math.floor(new Date(row.created_at).getTime() / 1000) : undefined,
  };
}

export async function createSessionWithId(id, teacherCode, startedAt, expiresAt, offeringId) {
  const sa = startedAt ? new Date(startedAt * 1000) : new Date();
  const ea = expiresAt ? new Date(expiresAt * 1000) : null;
  const p = await getPool();
  const { rows } = await p.query(
    'insert into class_sessions (id, teacher_code, started_at, expires_at, offering_id) values ($1,$2,$3,$4,$5) returning *',
    [id, teacherCode, sa, ea, offeringId || null]
  );
  return mapSessionRow(rows[0]);
}

export async function createClassOffering(teacherCode, name) {
  if (!teacherCode || !name) return null;
  const id = uuidv4();
  const p = await getPool();
  const { rows } = await p.query(
    'insert into class_offerings (id, teacher_code, name) values ($1,$2,$3) returning *',
    [id, teacherCode, name]
  );
  return mapOfferingRow(rows[0] || null);
}

export async function listClassOfferingsWithStats(teacherCode) {
  const p = await getPool();
  const { rows } = await p.query(
    `select o.id, o.teacher_code, o.name, o.archived, o.created_at,
            count(s.*)::int as sessions_count,
            max(s.started_at) as last_session_at
       from class_offerings o
  left join class_sessions s on s.offering_id = o.id
      where o.teacher_code=$1 and o.archived = false
   group by o.id, o.teacher_code, o.name, o.archived, o.created_at
   order by o.created_at desc`,
    [teacherCode]
  );
  return rows.map((row) => ({
    ...mapOfferingRow(row),
    sessionsCount: Number(row.sessions_count ?? 0),
    lastSessionAt: row.last_session_at
        ? Math.floor(new Date(row.last_session_at).getTime() / 1000)
        : null,
  }));
}

export async function getClassOfferingForTeacher(offeringId, teacherCode) {
  if (!offeringId || !teacherCode) return null;
  const p = await getPool();
  const { rows } = await p.query(
    'select * from class_offerings where id=$1 and teacher_code=$2 and archived = false',
    [offeringId, teacherCode]
  );
  return mapOfferingRow(rows[0] || null);
}

export async function listSessionsForOffering(offeringId, teacherCode) {
  if (!offeringId || !teacherCode) return [];
  const p = await getPool();
  const { rows } = await p.query(
    `select s.id, s.teacher_code, s.started_at, s.expires_at, s.offering_id,
            count(a.*)::int as attendee_count
       from class_sessions s
  left join attendance a on a.session_id = s.id
      where s.offering_id=$1 and s.teacher_code=$2
   group by s.id, s.teacher_code, s.started_at, s.expires_at, s.offering_id
   order by s.started_at desc`,
    [offeringId, teacherCode]
  );
  return rows.map((row) => ({
    ...mapSessionRow(row),
    attendeeCount: Number(row.attendee_count ?? 0),
  }));
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

export async function addAttendanceManual(sessionId, studentCode, atTs, recordedBy) {
  const at = atTs ? new Date(atTs * 1000) : new Date();
  const id = uuidv4();
  const p = await getPool();
  await p.query(
    `insert into attendance (id, session_id, student_code, at, source, recorded_by)
     values ($1,$2,$3,$4,'manual',$5) on conflict do nothing`,
    [id, sessionId, studentCode, at, recordedBy || null]
  );
  // Ensure manual/source even if already existed
  await p.query(
    `update attendance set source='manual', recorded_by=$3
       where session_id=$1 and student_code=$2`,
    [sessionId, studentCode, recordedBy || null]
  );
  const { rows } = await p.query(
    `select a.session_id, a.student_code as code, a.at, a.status,
            u.email, u.name
       from attendance a
       left join users u on u.code = a.student_code
      where a.session_id=$1 and a.student_code=$2`,
    [sessionId, studentCode]
  );
  const row = rows[0];
  return row
    ? { code: row.code, email: row.email, name: row.name, at: Math.floor(new Date(row.at).getTime() / 1000), status: row.status }
    : null;
}

export async function removeAttendance(sessionId, studentCode) {
  const p = await getPool();
  await p.query('delete from attendance where session_id=$1 and student_code=$2', [sessionId, studentCode]);
  return { ok: true };
}

export async function getAttendance(sessionId) {
  const p = await getPool();
  const { rows } = await p.query(
    `select a.session_id, a.student_code as code, a.at, a.status,
            u.email, u.name
       from attendance a
       left join users u on u.code = a.student_code
      where a.session_id=$1
      order by a.at asc`,
    [sessionId]
  );
  return rows.map(r => ({ code: r.code, email: r.email, name: r.name, at: Math.floor(new Date(r.at).getTime() / 1000), status: r.status }));
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

export async function getGateByCode(code) {
  if (!code) return null;
  const p = await getPool();
  const { rows } = await p.query('select id from gates where code=$1', [code]);
  return rows[0]?.id || null;
}

export async function addAccessEvent({ scannedAt, studentCode, porterCode, gateCode, direction = 'in', result, jti, kid, issuer, deviceId, meta }) {
  if (!studentCode || !result) return null;
  const p = await getPool();
  const gateId = gateCode ? await getGateByCode(gateCode) : null;
  const sql = `insert into access_events (scanned_at, student_code, porter_code, gate_id, direction, result, token_jti, token_kid, issuer, device_id, meta)
               values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`;
  const vals = [
    scannedAt ? new Date(scannedAt * 1000) : new Date(),
    studentCode,
    porterCode || null,
    gateId,
    direction || 'in',
    result,
    jti || null,
    kid || null,
    issuer || null,
    deviceId || null,
    meta || null,
  ];
  await p.query(sql, vals);
  return true;
}

export async function upsertPasswordResetRequest({ userCode, email, otpHash, expiresAt, maxAttempts = 5 }) {
  if (!userCode || !email || !otpHash || !expiresAt) return null;
  const p = await getPool();
  await p.query(
    `insert into password_reset_requests (user_code, email, otp_hash, expires_at, attempts, max_attempts, created_at, updated_at)
     values ($1,$2,$3,$4,0,$5,now(),now())
     on conflict (user_code) do update
       set email=excluded.email,
           otp_hash=excluded.otp_hash,
           expires_at=excluded.expires_at,
           attempts=0,
           max_attempts=excluded.max_attempts,
           updated_at=now()`,
    [userCode, email, otpHash, expiresAt, maxAttempts]
  );
  return true;
}

export async function getPasswordResetRequest(userCode) {
  if (!userCode) return null;
  const p = await getPool();
  const { rows } = await p.query('select * from password_reset_requests where user_code=$1', [userCode]);
  return mapPasswordResetRow(rows[0]);
}

export async function incrementPasswordResetAttempts(userCode) {
  if (!userCode) return null;
  const p = await getPool();
  const { rows } = await p.query(
    `update password_reset_requests
        set attempts = attempts + 1,
            updated_at = now()
      where user_code=$1
      returning *`,
    [userCode]
  );
  return mapPasswordResetRow(rows[0]);
}

export async function deletePasswordResetRequest(userCode) {
  if (!userCode) return null;
  const p = await getPool();
  await p.query('delete from password_reset_requests where user_code=$1', [userCode]);
  return true;
}

export async function updateUserPasswordHash(userCode, passwordHash) {
  if (!userCode || !passwordHash) return null;
  const p = await getPool();
  await p.query('update users set password_hash=$2 where code=$1', [userCode, passwordHash]);
  return true;
}

export async function deleteRefreshTokensForUser(userCode) {
  if (!userCode) return null;
  const p = await getPool();
  await p.query('delete from refresh_tokens where user_code=$1', [userCode]);
  return true;
}

export async function searchStudents(q, limit = 10) {
  const p = await getPool();
  const like = `%${q.toLowerCase()}%`;
  const { rows } = await p.query(
    `select code, email, name
       from users
      where role='student'
        and (lower(email) like $1 or lower(name) like $1 or code like $1)
      order by email asc
      limit $2`,
    [like, Math.max(1, Math.min(limit, 20))]
  );
  return rows;
}

export async function getStudentByEmailInsensitive(email) {
  const p = await getPool();
  const { rows } = await p.query(
    `select * from users
      where role='student' and lower(email) = lower($1)
      limit 1`,
    [email]
  );
  return mapUserRow(rows[0]);
}

export async function storeRefreshToken(jti, userCode, expTs) {
  const p = await getPool();
  const expiresAt = new Date(expTs * 1000);
  await p.query('insert into refresh_tokens (jti, user_code, expires_at) values ($1,$2,$3) on conflict do nothing', [jti, userCode, expiresAt]);
}

export async function revokeRefreshToken(jti) {
  const p = await getPool();
  await p.query('update refresh_tokens set revoked=true where jti=$1', [jti]);
}

export async function getRefreshToken(jti) {
  const p = await getPool();
  const { rows } = await p.query('select * from refresh_tokens where jti=$1', [jti]);
  return rows[0] || null;
}