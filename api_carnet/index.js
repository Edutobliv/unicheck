// index.js (versiÃ³n ESM)
import 'dotenv/config';
import dns from 'node:dns';
// Prefer IPv4 first to avoid ENETUNREACH when an IPv6 AAAA is returned (Render free often lacks IPv6 egress)
try { dns.setDefaultResultOrder('ipv4first'); } catch {}
import express from "express";
import cors from "cors";
import helmet from "helmet";
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomInt } from 'node:crypto';
import swaggerUi from 'swagger-ui-express';
import YAML from 'yamljs';
import { generateKeyPair, SignJWT, jwtVerify, exportJWK, importJWK } from "jose";
import { v4 as uuidv4 } from "uuid";
import bcrypt from "bcryptjs";
import {
  ensureSchema,
  seedUsersIfEmpty,
  getUserByEmail,
  getUserByCode,
  userExistsByEmailOrCode,
  createUser,
  createSessionWithId,
  getSession,
  endSessionNow,
  addAttendance,
  getAttendance,
  getAttendanceEntry,
  updateUserPhotoPath,
  updateUserExpiry,
  getPool,
  addAttendanceManual,
  removeAttendance,
  searchStudents,
  storeRefreshToken,
  revokeRefreshToken,
  getRefreshToken,
  getStudentByEmailInsensitive,
  upsertPasswordResetRequest,
  getPasswordResetRequest,
  incrementPasswordResetAttempts,
  deletePasswordResetRequest,
  updateUserPasswordHash,
  deleteRefreshTokensForUser,
} from "./db.js";
import { uploadUserAvatarFromDataUrl, createSignedAvatarUrl, replaceUserAvatarFromDataUrl, deleteAvatarPath, supabaseAdmin } from "./storage.js";

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
// Prefer an explicit public base URL, else Render's provided URL, else localhost
const BASE_URL =
  process.env.PUBLIC_BASE_URL ||
  process.env.RENDER_EXTERNAL_URL ||
  `http://localhost:${PORT}`;
const TOKEN_TTL_SECONDS = 15; // cada token/QR dura 15 segundos
const SESSION_TTL = process.env.JWT_TTL || '24h'; // duraciÃ³n del JWT de sesiÃ³n (login)

// Para este MVP usaremos memoria local solo para evitar reuso de tokens efÃ­meros
const ROLE_TTL = {
  student: process.env.JWT_TTL_STUDENT || '15m',
  teacher: process.env.JWT_TTL_TEACHER || '1h',
  porter:  process.env.JWT_TTL_PORTER  || '1h',
};
function ttlForRole(role) { return ROLE_TTL[role] || SESSION_TTL; }

const REFRESH_TTL = process.env.REFRESH_TTL || '30d';

const usedJti = new Map();

function parseDurationToSeconds(s) {
  if (!s || typeof s !== 'string') return 0;
  const m = /^([0-9]+)\s*([smhd])$/.exec(s.trim());
  if (!m) return 0;
  const n = parseInt(m[1], 10);
  const u = m[2];
  const map = { s: 1, m: 60, h: 3600, d: 86400 };
  return n * (map[u] || 0);
}

const PASSWORD_RESET_TTL = parseDurationToSeconds(process.env.PASSWORD_RESET_TTL || '10m') || 600;
const PASSWORD_RESET_MAX_ATTEMPTS = parseInt(process.env.PASSWORD_RESET_MAX_ATTEMPTS || '5', 10) || 5;
const DEBUG_RESET_OTP = process.env.DEBUG_RESET_OTP === '1';

const mailer = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 587),
  secure: process.env.SMTP_SECURE === '1' || String(process.env.SMTP_PORT||'') === '465',
  auth: process.env.SMTP_USER ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS } : undefined,
});

async function sendOtpEmail(to, code) {
  if (!to || !code) return;
  const from = process.env.SMTP_FROM || 'no-reply@unicheck';
  const subject = 'Tu codigo de recuperacion Unicheck';
  const text = `Tu codigo es: ${code}. Vence en ${(PASSWORD_RESET_TTL/60)|0} minutos.`;
  const html = `<p>Tu codigo es: <b>${code}</b></p><p>Vence en ${(PASSWORD_RESET_TTL/60)|0} minutos.</p>`;
  await mailer.sendMail({ from, to, subject, text, html });
}

function maskEmail(email) {
  if (!email || typeof email !== 'string') return '';
  const trimmed = email.trim();
  const at = trimmed.indexOf('@');
  if (at <= 0) return trimmed;
  const local = trimmed.slice(0, at);
  const domain = trimmed.slice(at + 1);
  const anonymize = (value) => {
    if (!value) return '';
    if (value.length <= 2) return value[0] + '*';
    return value[0] + '*'.repeat(Math.max(1, value.length - 2)) + value.slice(-1);
  };
  const maskedLocal = anonymize(local);
  if (!domain) return maskedLocal;
  const domainParts = domain.split('.');
  if (domainParts.length === 0) return maskedLocal;
  if (domainParts[0]) {
    domainParts[0] = anonymize(domainParts[0]);
  }
  return `${maskedLocal}@${domainParts.join('.')}`;
}

function generateOtp(length = 6) {
  const max = 10 ** Math.max(1, length);
  return randomInt(0, max).toString().padStart(length, '0');
}

function isStrongPassword(password) {
  if (typeof password !== 'string') return false;
  if (password.length < 8) return false;
  const hasUpper = /[A-Z]/.test(password);
  const hasLower = /[a-z]/.test(password);
  const hasDigit = /\d/.test(password);
  const hasSpecial = /[^A-Za-z0-9]/.test(password);
  return hasUpper && hasLower && hasDigit && hasSpecial;
}

// Permitir cualquier dominio por defecto; si se define ALLOWED_EMAIL_DOMAINS,
// se restringe a los listados (separados por comas)
const ALLOWED_DOMAINS = (process.env.ALLOWED_EMAIL_DOMAINS || "")
  .split(",")
  .map((d) => d.trim())
  .filter(Boolean);
const JWT_SECRET = process.env.JWT_SECRET || "dev-secret";

const app = express();
app.use(cors());
app.use(helmet());
// Allow up to ~20MB JSON payloads to accommodate base64 images (~1.33x overhead for 10MB raw)
app.use(express.json({ limit: '20mb' }));

// Swagger UI / OpenAPI
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
let swaggerDoc = null;
try {
  const specPath = path.join(__dirname, 'openapi.yaml');
  swaggerDoc = YAML.load(specPath);
  // Rutas para servir el spec
  app.get('/openapi.yaml', (req, res) => {
    res.type('text/yaml').send(fs.readFileSync(specPath, 'utf8'));
  });
  app.get('/openapi.json', (req, res) => {
    res.type('application/json').send(JSON.stringify(swaggerDoc));
  });

  // Montar Swagger UI con CSP relajado solo en /docs y apuntando al spec
  const docsRouter = express.Router();
  docsRouter.use(helmet({ contentSecurityPolicy: false }));
  docsRouter.use(swaggerUi.serve, swaggerUi.setup(swaggerDoc, {
    explorer: true,
    swaggerOptions: {
      url: '/openapi.yaml',
      urls: [
        { url: '/openapi.yaml', name: 'OpenAPI (YAML)' },
        { url: '/openapi.json', name: 'OpenAPI (JSON)' },
      ],
      persistAuthorization: true,
      displayOperationId: true,
    },
  }));
  app.use('/docs', docsRouter);
} catch (e) {
  console.warn('Swagger/OpenAPI no disponible:', e?.message || String(e));
}

let privateKey;
let publicJwk;

// Generamos un par de claves (firma de tokens)
(async () => {
  const { publicKey, privateKey: pk } = await generateKeyPair("EdDSA"); // Ed25519
  privateKey = pk;
  publicJwk = await exportJWK(publicKey);
  publicJwk.kid = "ed25519-key-1";
  // Initialize DB schema and seed demo users if empty
  try {
    await ensureSchema();
    // Ya no sembramos usuarios demo aquÃ­; la BD productiva tiene sus registros.
    // Si necesitas poblar en desarrollo, usa seedUsersIfEmpty() en scripts separados.
    await seedUsersIfEmpty();
  } catch (e) {
    console.error('DB init error:', e);
  }
})();

// Endpoint para publicar la clave pÃºblica (Ãºtil para verificadores)
app.get("/.well-known/jwks.json", (req, res) => {
  res.json({ keys: [publicJwk] });
});

// Health check for uptime/Render
app.get('/health', (req, res) => {
  res.json({ ok: true });
});

// Lightweight diagnostics (guarded by DEBUG_KEY)
const DEBUG_KEY = process.env.DEBUG_KEY;
app.get('/__debug', async (req, res) => {
  const provided = req.query?.k || req.headers['x-debug-key'];
  if (!DEBUG_KEY || provided !== DEBUG_KEY) return res.status(403).json({ ok: false, error: 'forbidden' });
  const out = {
    ok: true,
    env: {
      hasDatabaseUrl: !!process.env.DATABASE_URL,
      hasSupabaseUrl: !!process.env.SUPABASE_URL,
      hasSupabaseServiceRole: !!process.env.SUPABASE_SERVICE_ROLE,
      avatarBucket: process.env.AVATAR_BUCKET || 'avatars',
      baseUrl: BASE_URL,
    },
    db: {},
    storage: {},
  };
  try {
    const p = await getPool();
    const { rows } = await p.query('select now() as now');
    out.db.now = rows?.[0]?.now;
    out.db.ok = true;
  } catch (e) {
    out.db.ok = false;
    out.db.error = e?.message || String(e);
  }
  try {
    const sb = supabaseAdmin();
    const bucket = process.env.AVATAR_BUCKET || 'avatars';
    const { data, error } = await sb.storage.from(bucket).list('', { limit: 1 });
    if (error) throw error;
    out.storage.ok = true;
    out.storage.sample = data?.[0]?.name || null;
  } catch (e) {
    out.storage.ok = false;
    out.storage.error = e?.message || String(e);
  }
  res.json(out);
});

// Endpoint de login bÃ¡sico
app.post("/auth/login", async (req, res) => {
  try {
    const { email, password, code } = req.body || {};
    if ((!email && !code) || !password)
      return res.status(400).json({ error: "missing_credentials", message: "Falta email/cÃ³digo o contraseÃ±a" });

    let user;
    if (email) {
      const domain = email.split("@")[1];
      if (ALLOWED_DOMAINS.length && !ALLOWED_DOMAINS.includes(domain)) {
        return res.status(403).json({ error: "domain_not_allowed", message: "Dominio de correo no permitido" });
      }
      user = await getUserByEmail(email);
    } else {
      user = await getUserByCode(code);
    }

    if (!user) return res.status(401).json({ error: "invalid_credentials", message: "Usuario o contraseÃ±a incorrectos" });
    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) return res.status(401).json({ error: "invalid_credentials", message: "Usuario o contraseÃ±a incorrectos" });

    // Auto-renew student expiry to 6 months if missing or expired
    try {
      if (user.role === 'student') {
        const parseDMY = (s) => {
          if (!s || typeof s !== 'string') return null;
          const m = /^([0-3]?\d)\/(1[0-2]|0?\d)\/(\d{4})$/.exec(s.trim());
          if (!m) return null;
          const d = parseInt(m[1], 10);
          const mo = parseInt(m[2], 10) - 1;
          const y = parseInt(m[3], 10);
          const dt = new Date(y, mo, d);
          return isNaN(dt.getTime()) ? null : dt;
        };
        const now = new Date();
        const expDate = parseDMY(user.expiresAt);
        if (!expDate || expDate < now) {
          const future = new Date(now.getFullYear(), now.getMonth() + 6, now.getDate());
          const dd = String(future.getDate()).padStart(2, '0');
          const mm = String(future.getMonth() + 1).padStart(2, '0');
          const yyyy = String(future.getFullYear());
          const newExp = `${dd}/${mm}/${yyyy}`;
          const updated = await updateUserExpiry(user.code, newExp);
          if (updated) user = updated;
        }
      }
    } catch {}

    const token = await new SignJWT({ role: user.role })
      .setProtectedHeader({ alg: "HS256", typ: "JWT" })
      .setIssuedAt()
      .setExpirationTime(ttlForRole(user.role))
      .setIssuer("api_carnet")
      .setSubject(user.code)
      .sign(new TextEncoder().encode(JWT_SECRET));

    // Refresh token (rotation)
    const refreshJti = uuidv4();
    const nowSec = Math.floor(Date.now()/1000);
    const refreshExpSec = nowSec + (parseDurationToSeconds(REFRESH_TTL) || (30*24*3600));
    const refreshToken = await new SignJWT({ scope: 'refresh' })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setIssuedAt(nowSec)
      .setExpirationTime(refreshExpSec)
      .setIssuer('api_carnet')
      .setSubject(user.code)
      .setJti(refreshJti)
      .sign(new TextEncoder().encode(JWT_SECRET));
    try { await storeRefreshToken(refreshJti, user.code, refreshExpSec); } catch {}

    // If the user has a private avatar path, create a short-lived signed URL
    let signedPhoto = undefined;
    try {
      if (user.photoUrl) signedPhoto = await createSignedAvatarUrl(user.photoUrl, 300);
    } catch {}

    res.json({
      token,
      refreshToken,
      user: {
        code: user.code,
        email: user.email,
        role: user.role,
        name: user.name,
        program: user.program,
        expiresAt: user.expiresAt,
        photoUrl: signedPhoto || user.photoUrl || null,
      },
    });
  } catch (e) {
    console.error('login_error', e);
    return res.status(500).json({ error: 'login_failed', message: 'Error del servidor' });
  }
});

// Refresh access token using refresh token
app.post("/auth/password-reset/request", async (req, res) => {
  try {
    const { email, code } = req.body || {};
    const rawEmail = typeof email === "string" ? email.trim() : "";
    const rawCode = typeof code === "string" ? code.trim() : "";
    const identifier = rawEmail || rawCode;
    if (!identifier) {
      return res.status(400).json({
        error: "missing_identifier",
        message: "Debes proporcionar tu correo institucional o codigo.",
      });
    }

    let user = null;
    if (rawEmail) {
      user = await getUserByEmail(rawEmail);
    } else if (rawCode) {
      user = await getUserByCode(rawCode);
    }

    if (!user) {
      return res.json({ ok: true, maskedEmail: null, expiresIn: PASSWORD_RESET_TTL });
    }

    // Send Supabase OTP to email\n    const sb = supabaseAdmin();\n    await sb.auth.signInWithOtp({ email: user.email });

    await upsertPasswordResetRequest({
      userCode: user.code,
      email: user.email,
      otpHash,
      expiresAt,
      maxAttempts: PASSWORD_RESET_MAX_ATTEMPTS,
    });

    if (DEBUG_RESET_OTP) {
      console.log(`[password-reset] OTP for ${user.email} (${user.code}): ${otp}`);
    } else {
      console.log(`[password-reset] OTP enviado a ${user.email}`);
    }

    const payload = {
      ok: true,
      maskedEmail: maskEmail(user.email),
      expiresIn: PASSWORD_RESET_TTL,
    };
    return res.json(payload);
  } catch (err) {
    console.error("[password-reset][request]", err);
    return res.status(500).json({
      error: "reset_request_failed",
      message: "No se pudo enviar el codigo. Intentalo mas tarde.",
    });
  }
});

app.post("/auth/password-reset/confirm", async (req, res) => {
  try {
    const { email, code, otp, newPassword } = req.body || {};
    const rawEmail = typeof email === "string" ? email.trim() : "";
    const rawCode = typeof code === "string" ? code.trim() : "";
    const identifier = rawEmail || rawCode;
    const otpValue = typeof otp === "string" ? otp.trim() : String(otp ?? "").trim();
    const passwordValue = typeof newPassword === "string" ? newPassword.trim() : "";

    if (!identifier || !otpValue || !passwordValue) {
      return res.status(400).json({
        error: "missing_params",
        message: "Faltan datos para restablecer la contrasena.",
      });
    }

    if (!isStrongPassword(passwordValue)) {
      return res.status(400).json({
        error: "weak_password",
        message: "La contrasena debe tener minimo 8 caracteres, con mayusculas, minusculas, numero y simbolo.",
      });
    }

    let user = null;
    if (rawEmail) {
      user = await getUserByEmail(rawEmail);
    } else if (rawCode) {
      user = await getUserByCode(rawCode);
    }

    if (!user) {
      return res.status(400).json({
        error: "invalid_request",
        message: "Solicitud invalida.",
      });
    }

    const reset = await getPasswordResetRequest(user.code);
    if (!reset) {
      return res.status(400).json({
        error: "otp_required",
        message: "Solicita un nuevo codigo antes de continuar.",
      });
    }

    if (reset.expiresAt && reset.expiresAt.getTime() <= Date.now()) {
      await deletePasswordResetRequest(user.code);
      return res.status(400).json({
        error: "otp_expired",
        message: "El codigo expiro. Solicita uno nuevo.",
      });
    }

    if (reset.attempts >= reset.maxAttempts) {
      await deletePasswordResetRequest(user.code);
      return res.status(400).json({
        error: "otp_locked",
        message: "Se agotaron los intentos. Solicita un nuevo codigo.",
      });
    }

    const otpOk = await bcrypt.compare(otpValue, reset.otpHash || "");
    if (!otpOk) {
      const updated = await incrementPasswordResetAttempts(user.code);
      if (updated && updated.attempts >= updated.maxAttempts) {
        await deletePasswordResetRequest(user.code);
        return res.status(400).json({
          error: "otp_locked",
          message: "Se agotaron los intentos. Solicita un nuevo codigo.",
        });
      }
      return res.status(400).json({
        error: "otp_invalid",
        message: "Codigo incorrecto. Verifica e intenta de nuevo.",
      });
    }

    const newHash = await bcrypt.hash(passwordValue, 10);
    await updateUserPasswordHash(user.code, newHash);
    await deletePasswordResetRequest(user.code);
    await deleteRefreshTokensForUser(user.code);

    return res.json({ ok: true });
  } catch (err) {
    console.error("[password-reset][confirm]", err);
    return res.status(500).json({
      error: "reset_confirm_failed",
      message: "No se pudo actualizar la contrasena. Intentalo mas tarde.",
    });
  }
});

app.post('/auth/refresh', async (req, res) => {
  try {
    const { refreshToken } = req.body || {};
    if (!refreshToken) return res.status(400).json({ error: 'missing_refresh_token' });
    const { payload } = await jwtVerify(refreshToken, new TextEncoder().encode(JWT_SECRET), { issuer: 'api_carnet' });
    if (payload.scope !== 'refresh') return res.status(400).json({ error: 'invalid_scope' });
    const jti = payload.jti;
    const sub = payload.sub;
    if (!jti || !sub) return res.status(400).json({ error: 'invalid_token' });
    const row = await getRefreshToken(jti);
    const now = new Date();
    if (!row || row.revoked || (row.expires_at && now > new Date(row.expires_at))) {
      return res.status(401).json({ error: 'refresh_invalid' });
    }
    try { await revokeRefreshToken(jti); } catch {}

    const user = await getUserByCode(sub);
    if (!user) return res.status(404).json({ error: 'user_not_found' });
    const access = await new SignJWT({ role: user.role })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setIssuedAt()
      .setExpirationTime(ttlForRole(user.role))
      .setIssuer('api_carnet')
      .setSubject(user.code)
      .sign(new TextEncoder().encode(JWT_SECRET));

    const newJti = uuidv4();
    const nowSec = Math.floor(Date.now()/1000);
    const refreshExpSec = nowSec + (parseDurationToSeconds(REFRESH_TTL) || (30*24*3600));
    const newRefresh = await new SignJWT({ scope: 'refresh' })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setIssuedAt(nowSec)
      .setExpirationTime(refreshExpSec)
      .setIssuer('api_carnet')
      .setSubject(user.code)
      .setJti(newJti)
      .sign(new TextEncoder().encode(JWT_SECRET));
    try { await storeRefreshToken(newJti, user.code, refreshExpSec); } catch {}

    return res.json({ token: access, refreshToken: newRefresh });
  } catch (e) {
    return res.status(401).json({ error: 'invalid_refresh' });
  }
});

// Registro de nuevos estudiantes
app.post("/auth/register", async (req, res) => {
  try {
    let { code, email, name, firstName, middleName, lastName, secondLastName, password, program, expiresAt, role, photo } = req.body || {};
    if (!code || !email || !name.trim() || !password || !firstName || !lastName) {
      return res.status(400).json({ error: "missing_fields", message: "Faltan campos obligatorios (nombre, apellido)" });
    }
    const exists = await userExistsByEmailOrCode(email, code);
    if (exists) {
      return res.status(409).json({ error: "user_exists", message: "El usuario ya existe" });
    }
    const passwordHash = await bcrypt.hash(password, 10);
    // Default expiration to 6 months if not provided
    if (!expiresAt) {
      const now = new Date();
      const future = new Date(now.getFullYear(), now.getMonth() + 6, now.getDate());
      const dd = String(future.getDate()).padStart(2, '0');
      const mm = String(future.getMonth() + 1).padStart(2, '0');
      const yyyy = String(future.getFullYear());
      expiresAt = `${dd}/${mm}/${yyyy}`;
    }
    let photoPath = null;
    if (photo && typeof photo === 'string' && photo.startsWith('data:')) {
      try {
        // Use fixed path to avoid acumulating objects; no previous photo on new user
        photoPath = await replaceUserAvatarFromDataUrl(photo, code, null);
      } catch (e) {
        console.warn('Avatar upload failed:', e?.message || e);
      }
    }

    const newUser = await createUser({
      code,
      email,
      name,
      firstName,
      middleName,
      lastName,
      secondLastName,
      role: role || "student",
      program,
      expiresAt,
      photoUrl: photoPath,
      passwordHash,
    });

    const ephemeralCode = uuidv4();
    // Return a signed URL if private avatar was stored
    let signedPhoto = null;
    try {
      if (newUser.photoUrl) signedPhoto = await createSignedAvatarUrl(newUser.photoUrl, 300);
    } catch {}
    res.json({ success: true, ephemeralCode, user: { ...newUser, photoUrl: signedPhoto || newUser.photoUrl } });
  } catch (e) {
    console.error('registration_error', e);
    res.status(500).json({ error: "registration_failed", message: 'No se pudo registrar. Intenta mÃ¡s tarde.' });
  }
});

// Obtener una URL firmada temporal para la foto del usuario autenticado
app.get("/users/me/photo-url", requireAuth(), async (req, res) => {
  try {
    const user = await getUserByCode(req.user.code);
    if (!user) return res.status(404).json({ error: "user_not_found" });
    if (!user.photoUrl) return res.json({ photoUrl: null, expiresIn: 0 });
    const ttl = 300; // 5 minutos
    const signed = await createSignedAvatarUrl(user.photoUrl, ttl);
    return res.json({ photoUrl: signed, expiresIn: ttl });
  } catch (e) {
    return res.status(500).json({ error: "sign_url_failed" });
  }
});

// Reemplazar la foto del usuario autenticado (acepta data URL), comprime y sobreescribe avatar Ãºnico
app.put("/users/me/photo", requireAuth(), async (req, res) => {
  try {
    const { photo } = req.body || {};
    if (!photo || typeof photo !== 'string' || !photo.startsWith('data:')) {
      return res.status(400).json({ error: 'invalid_photo' });
    }
    const user = await getUserByCode(req.user.code);
    if (!user) return res.status(404).json({ error: 'user_not_found' });

    const newPath = await replaceUserAvatarFromDataUrl(photo, req.user.code, user.photoUrl);
    // Persist path
    await updateUserPhotoPath(req.user.code, newPath);
    const ttl = 300;
    const signed = await createSignedAvatarUrl(newPath, ttl);
    return res.json({ photoUrl: signed, expiresIn: ttl });
  } catch (e) {
    console.error('photo_update_error', e);
    return res.status(500).json({ error: 'photo_update_failed' });
  }
});

// Eliminar la foto del usuario autenticado y liberar espacio en el bucket
app.delete("/users/me/photo", requireAuth(), async (req, res) => {
  try {
    const user = await getUserByCode(req.user.code);
    if (!user) return res.status(404).json({ error: 'user_not_found' });
    if (!user.photoUrl) return res.json({ ok: true, deleted: false });
    await deleteAvatarPath(user.photoUrl);
    await updateUserPhotoPath(req.user.code, null);
    return res.json({ ok: true, deleted: true });
  } catch (e) {
    console.error('photo_delete_error', e);
    return res.status(500).json({ error: 'photo_delete_failed' });
  }
});

function requireAuth(role) {
  return async (req, res, next) => {
    try {
      const auth = req.headers.authorization || "";
      const token = auth.startsWith("Bearer ") ? auth.slice(7) : null;
      if (!token) return res.status(401).json({ error: "missing_token" });
      const { payload } = await jwtVerify(
        token,
        new TextEncoder().encode(JWT_SECRET),
        { issuer: "api_carnet" }
      );
      if (role && payload.role !== role)
        return res.status(403).json({ error: "forbidden" });
      req.user = { code: payload.sub, role: payload.role };
      next();
    } catch (e) {
      return res.status(401).json({ error: "invalid_token" });
    }
  };
}

// Endpoint que emite un QR efÃ­mero
app.post("/issue-ephemeral", requireAuth("student"), async (req, res) => {
  try {
    const { code } = req.user;
    const deviceId = req.body?.deviceId || "demo-device";
    const jti = uuidv4();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + TOKEN_TTL_SECONDS;

    const token = await new SignJWT({
      scope: "campus_access",
      device_id: deviceId,
    })
      .setProtectedHeader({ alg: "EdDSA", kid: "ed25519-key-1", typ: "JWT" })
      .setIssuedAt(now)
      .setExpirationTime(exp)
      .setIssuer(BASE_URL)
      .setAudience("gate_verifier")
      .setSubject(code)
      .setJti(jti)
      .sign(privateKey);

    usedJti.set(jti, false);
    setTimeout(() => usedJti.delete(jti), TOKEN_TTL_SECONDS * 1000 + 2000);

    const qrUrl = `${BASE_URL}/verify?t=${encodeURIComponent(token)}`;
    const found = await getUserByCode(code);
    const { passwordHash, ...student } = found || {};
    // Include a signed photo URL to avoid an extra request from the client
    let photoSigned = null;
    const photoTtl = 300; // 5 minutes
    try {
      if (student?.photoUrl) photoSigned = await createSignedAvatarUrl(student.photoUrl, photoTtl);
    } catch {}
    const studentOut = {
      ...student,
      photoUrl: photoSigned || student?.photoUrl || null,
      photoUrlExpiresIn: photoSigned ? photoTtl : 0,
    };

    res.json({ token, qrUrl, ttl: TOKEN_TTL_SECONDS, student: studentOut, ephemeralCode: found?.ephemeralCode });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "issue_failed" });
  }
});

// Endpoint que verifica el QR
app.post("/verify", async (req, res) => {
  try {
    const token = (req.body && req.body.token) || (req.query && req.query.t);
    if (!token) return res.status(400).json({ valid: false, reason: "missing_token" });
    // Optional porter auth to attribute the scan event
    let porterCode = null;
    try {
      const auth = req.headers.authorization || "";
      const bearer = auth.startsWith("Bearer ") ? auth.slice(7) : null;
      if (bearer) {
        const { payload } = await jwtVerify(
          bearer,
          new TextEncoder().encode(JWT_SECRET),
          { issuer: "api_carnet" }
        );
        if (payload?.role === 'porter') porterCode = payload.sub;
      }
    } catch {}
    const gateCode = req.query?.gate || req.body?.gate || null;
    const direction = req.query?.direction || req.body?.direction || 'in';

    const { payload, protectedHeader } = await jwtVerify(
      token,
      async (header) => await importJWK(publicJwk, header.alg),
      {
        issuer: BASE_URL,
        audience: "gate_verifier",
        clockTolerance: "5s",
      }
    );

    const jti = payload.jti;
    if (!jti) return res.status(400).json({ valid: false, reason: "missing_jti" });

    if (!usedJti.has(jti)) {
      try { await addAccessEvent({ studentCode: payload.sub, porterCode, gateCode, direction, result: 'expired', jti, kid: protectedHeader?.kid, issuer: BASE_URL, deviceId: payload?.device_id }); } catch {}
      return res.status(401).json({ valid: false, reason: "expired_or_unknown" });
    }
    if (usedJti.get(jti) === true) {
      try { await addAccessEvent({ studentCode: payload.sub, porterCode, gateCode, direction, result: 'replayed', jti, kid: protectedHeader?.kid, issuer: BASE_URL, deviceId: payload?.device_id }); } catch {}
      return res.status(401).json({ valid: false, reason: "replayed" });
    }

    usedJti.set(jti, true);

    const found = await getUserByCode(payload.sub);
    const { passwordHash, ...student } = found || {};
    try { await addAccessEvent({ studentCode: payload.sub, porterCode, gateCode, direction, result: 'valid', jti, kid: protectedHeader?.kid, issuer: BASE_URL, deviceId: payload?.device_id }); } catch {}
    return res.json({
      valid: true,
      kid: protectedHeader.kid,
      student,
    });
  } catch (e) {
    return res.status(401).json({ valid: false, reason: "invalid_token" });
  }
});

// --- Flujo Profesor: sesiones y asistencia ---

// Profesor inicia una sesiÃ³n de clase y obtiene un token para QR que los alumnos escanean
app.post("/prof/start-session", requireAuth("teacher"), async (req, res) => {
  try {
    const teacherCode = req.user.code;
    const sessionId = uuidv4();
    const now = Math.floor(Date.now() / 1000);
    const ttlReq = Number(req.body?.ttlSeconds);
    const ttl = Number.isFinite(ttlReq) && ttlReq > 0 ? Math.min(Math.max(ttlReq, 60), 3600) : 10 * 60; // 1-60 min
    const exp = now + ttl;
    const offeringId = req.body?.offeringId || null;

    // Persist session in DB
    await createSessionWithId(sessionId, teacherCode, now, exp, offeringId);

    // Token firmado con HS256 (clave compartida del API) para que el alumno lo envÃ­e en check-in
    const sessionToken = await new SignJWT({ scope: "attendance", session_id: sessionId })
      .setProtectedHeader({ alg: "HS256", typ: "JWT" })
      .setIssuedAt(now)
      .setExpirationTime(exp)
      .setIssuer("api_carnet")
      .setSubject(teacherCode)
      .sign(new TextEncoder().encode(JWT_SECRET));

    // Texto para QR: se puede incluir URL directa del endpoint de check-in con el token como query
    const qrText = `ATTEND:${sessionToken}`;

    return res.json({
      session: { id: sessionId, startedAt: now, expiresAt: exp },
      qrText,
      ttl,
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: "start_session_failed" });
  }
});

// Profesor finaliza una sesiÃ³n (deja de aceptar check-ins, pero permite consultar lista)
app.post("/prof/end-session", requireAuth("teacher"), async (req, res) => {
  const sessionId = req.body?.sessionId || req.query?.id;
  if (!sessionId) return res.status(400).json({ error: "missing_session_id" });
  const session = await getSession(sessionId);
  if (!session) return res.status(404).json({ error: "session_not_found" });
  if (session.teacherCode !== req.user.code) return res.status(403).json({ error: "forbidden" });
  const now = Math.floor(Date.now() / 1000);
  const updated = await endSessionNow(sessionId, now);
  const attendees = await getAttendance(sessionId);
  return res.json({ ok: true, session: updated, attendees });
});

// Alumno hace check-in a la sesiÃ³n escaneada (necesita estar logueado como student)
app.post("/attendance/check-in", requireAuth("student"), async (req, res) => {
  try {
    const sessionToken = req.body?.sessionToken || req.query?.t;
    if (!sessionToken) return res.status(400).json({ error: "missing_session_token" });

    const { payload } = await jwtVerify(
      sessionToken,
      new TextEncoder().encode(JWT_SECRET),
      { issuer: "api_carnet" }
    );

    if (payload.scope !== "attendance") {
      return res.status(400).json({ error: "invalid_scope" });
    }
    const sessionId = payload.session_id;
    if (!sessionId) return res.status(400).json({ error: "missing_session_id" });

    const session = await getSession(sessionId);
    if (!session) return res.status(404).json({ error: "session_not_found" });

    const now = Math.floor(Date.now() / 1000);
    if (session.expiresAt && now > session.expiresAt) {
      return res.status(400).json({ error: "session_expired" });
    }

    const existing = await getAttendanceEntry(sessionId, req.user.code);
    if (existing) {
      return res.json({ ok: true, already: true, at: existing.at, sessionId });
    }

    // Buscar datos del estudiante para devolver informaciÃ³n Ãºtil
    const newEntry = await addAttendance(sessionId, req.user.code, now);
    const entry = newEntry;

    return res.json({ ok: true, sessionId, entry });
  } catch (e) {
    return res.status(401).json({ error: "invalid_session_token" });
  }
});

// Profesor consulta la asistencia de una sesiÃ³n
app.get("/prof/session/:id", requireAuth("teacher"), async (req, res) => {
  const sessionId = req.params.id;
  const session = await getSession(sessionId);
  if (!session) return res.status(404).json({ error: "session_not_found" });
  const attendees = await getAttendance(sessionId);
  return res.json({ session, attendees });
});

// AÃ±adir asistencia manual por profesor
app.post('/prof/attendance/add', requireAuth('teacher'), async (req, res) => {
  try {
    const { sessionId, code, email } = req.body || {};
    if (!sessionId || (!code && !email)) return res.status(400).json({ error: 'missing_params' });
    const session = await getSession(sessionId);
    if (!session) return res.status(404).json({ error: 'session_not_found' });
    if (session.teacherCode !== req.user.code) return res.status(403).json({ error: 'forbidden' });
    // Resolver estudiante por cÃ³digo o email
    let student = null;
    if (code) student = await getUserByCode(code);
    if (!student && email) student = await getUserByEmail(email);
    if (!student || student.role !== 'student') return res.status(404).json({ error: 'student_not_found' });
    const entry = await addAttendanceManual(sessionId, student.code, Math.floor(Date.now()/1000), req.user.code);
    return res.json({ ok: true, entry });
  } catch (e) {
    return res.status(500).json({ error: 'manual_add_failed' });
  }
});

// Eliminar asistencia de un estudiante en la sesiÃ³n
app.delete('/prof/attendance', requireAuth('teacher'), async (req, res) => {
  try {
    const { sessionId, studentCode } = req.body || {};
    if (!sessionId || !studentCode) return res.status(400).json({ error: 'missing_params' });
    const session = await getSession(sessionId);
    if (!session) return res.status(404).json({ error: 'session_not_found' });
    if (session.teacherCode !== req.user.code) return res.status(403).json({ error: 'forbidden' });
    await removeAttendance(sessionId, studentCode);
    return res.json({ ok: true });
  } catch (e) {
    return res.status(500).json({ error: 'remove_failed' });
  }
});

// Autocomplete de estudiantes (email/name). SÃ³lo para docente
app.get('/prof/students/search', requireAuth('teacher'), async (req, res) => {
  try {
    const q = String(req.query?.q || '').trim();
    if (!q) return res.json({ items: [] });
    const items = await searchStudents(q, 10);
    return res.json({ items });
  } catch (e) {
    return res.status(500).json({ error: 'search_failed' });
  }
});

app.listen(PORT, HOST, () => {
  console.log("API QR efÃ­mero escuchando en " + BASE_URL);
});


