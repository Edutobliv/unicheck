// index.js (versión ESM)
import 'dotenv/config';
import dns from 'node:dns';
// Prefer IPv4 first to avoid ENETUNREACH when an IPv6 AAAA is returned (Render free often lacks IPv6 egress)
try { dns.setDefaultResultOrder('ipv4first'); } catch {}
import express from "express";
import cors from "cors";
import helmet from "helmet";
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
} from "./db.js";
import { uploadUserAvatarFromDataUrl, createSignedAvatarUrl, replaceUserAvatarFromDataUrl, deleteAvatarPath } from "./storage.js";

const PORT = process.env.PORT || 3000;
const TOKEN_TTL_SECONDS = 15; // cada token/QR dura 15 segundos

// Para este MVP usaremos memoria local solo para evitar reuso de tokens efímeros
const usedJti = new Map();

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
    await seedUsersIfEmpty([
      {
        code: 'U20230001',
        email: 'alumno1@example.edu',
        name: 'Alumno Uno',
        role: 'student',
        program: 'INGENIERIA DE SISTEMAS',
        expiresAt: '30/06/2025',
        photoUrl: null,
        passwordHash: '$2b$10$kex/FEd9ELMutckwBETx2u2E52FdIKsE8YGvXSw02k6BVZpEvGatS'
      },
      {
        code: 'DOC123',
        email: 'docente@example.edu',
        name: 'Docente Uno',
        role: 'teacher',
        passwordHash: '$2b$10$kex/FEd9ELMutckwBETx2u2E52FdIKsE8YGvXSw02k6BVZpEvGatS'
      },
      {
        code: 'PORT001',
        email: 'portero@example.edu',
        name: 'Portero Uno',
        role: 'porter',
        passwordHash: '$2b$10$kex/FEd9ELMutckwBETx2u2E52FdIKsE8YGvXSw02k6BVZpEvGatS'
      }
    ]);
  } catch (e) {
    console.error('DB init error:', e);
  }
})();

// Endpoint para publicar la clave pública (útil para verificadores)
app.get("/.well-known/jwks.json", (req, res) => {
  res.json({ keys: [publicJwk] });
});

// Health check for uptime/Render
app.get('/health', (req, res) => {
  res.json({ ok: true });
});

// Endpoint de login básico
app.post("/auth/login", async (req, res) => {
  const { email, password, code } = req.body || {};
  if ((!email && !code) || !password)
    return res.status(400).json({ error: "missing_credentials" });

  let user;
  if (email) {
    const domain = email.split("@")[1];
    if (ALLOWED_DOMAINS.length && !ALLOWED_DOMAINS.includes(domain)) {
      return res.status(403).json({ error: "domain_not_allowed" });
    }
    user = await getUserByEmail(email);
  } else {
    user = await getUserByCode(code);
  }

  if (!user) return res.status(401).json({ error: "invalid_credentials" });
  const ok = await bcrypt.compare(password, user.passwordHash);
  if (!ok) return res.status(401).json({ error: "invalid_credentials" });

  const token = await new SignJWT({ role: user.role })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuedAt()
    .setExpirationTime("1h")
    .setIssuer("api_carnet")
    .setSubject(user.code)
    .sign(new TextEncoder().encode(JWT_SECRET));

  // If the user has a private avatar path, create a short-lived signed URL
  let signedPhoto = undefined;
  try {
    if (user.photoUrl) signedPhoto = await createSignedAvatarUrl(user.photoUrl, 300);
  } catch {}

  res.json({
    token,
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
});

// Registro de nuevos estudiantes
app.post("/auth/register", async (req, res) => {
  try {
    const { code, email, name, password, program, expiresAt, role, photo } = req.body || {};
    if (!code || !email || !name || !password) {
      return res.status(400).json({ error: "missing_fields" });
    }
    const exists = await userExistsByEmailOrCode(email, code);
    if (exists) {
      return res.status(409).json({ error: "user_exists" });
    }
    const passwordHash = await bcrypt.hash(password, 10);
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
    res.status(500).json({ error: "registration_failed" });
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

// Reemplazar la foto del usuario autenticado (acepta data URL), comprime y sobreescribe avatar único
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

// Endpoint que emite un QR efímero
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
      .setIssuer("http://localhost:" + PORT)
      .setAudience("gate_verifier")
      .setSubject(code)
      .setJti(jti)
      .sign(privateKey);

    usedJti.set(jti, false);
    setTimeout(() => usedJti.delete(jti), TOKEN_TTL_SECONDS * 1000 + 2000);

    const qrUrl = `http://localhost:${PORT}/verify?t=${encodeURIComponent(token)}`;
    const found = await getUserByCode(code);
    const { passwordHash, ...student } = found || {};

    res.json({ token, qrUrl, ttl: TOKEN_TTL_SECONDS, student, ephemeralCode: found?.ephemeralCode });
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

    const { payload, protectedHeader } = await jwtVerify(
      token,
      async (header) => await importJWK(publicJwk, header.alg),
      {
        issuer: "http://localhost:" + PORT,
        audience: "gate_verifier",
        clockTolerance: "5s",
      }
    );

    const jti = payload.jti;
    if (!jti) return res.status(400).json({ valid: false, reason: "missing_jti" });

    if (!usedJti.has(jti)) {
      return res.status(401).json({ valid: false, reason: "expired_or_unknown" });
    }
    if (usedJti.get(jti) === true) {
      return res.status(401).json({ valid: false, reason: "replayed" });
    }

    usedJti.set(jti, true);

    const found = await getUserByCode(payload.sub);
    const { passwordHash, ...student } = found || {};

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

// Profesor inicia una sesión de clase y obtiene un token para QR que los alumnos escanean
app.post("/prof/start-session", requireAuth("teacher"), async (req, res) => {
  try {
    const teacherCode = req.user.code;
    const sessionId = uuidv4();
    const now = Math.floor(Date.now() / 1000);
    const ttlReq = Number(req.body?.ttlSeconds);
    const ttl = Number.isFinite(ttlReq) && ttlReq > 0 ? Math.min(Math.max(ttlReq, 60), 3600) : 10 * 60; // 1-60 min
    const exp = now + ttl;

    // Persist session in DB
    await createSessionWithId(sessionId, teacherCode, now, exp);

    // Token firmado con HS256 (clave compartida del API) para que el alumno lo envíe en check-in
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

// Profesor finaliza una sesión (deja de aceptar check-ins, pero permite consultar lista)
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

// Alumno hace check-in a la sesión escaneada (necesita estar logueado como student)
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

    // Buscar datos del estudiante para devolver información útil
    const newEntry = await addAttendance(sessionId, req.user.code, now);
    const entry = newEntry;

    return res.json({ ok: true, sessionId, entry });
  } catch (e) {
    return res.status(401).json({ error: "invalid_session_token" });
  }
});

// Profesor consulta la asistencia de una sesión
app.get("/prof/session/:id", requireAuth("teacher"), async (req, res) => {
  const sessionId = req.params.id;
  const session = await getSession(sessionId);
  if (!session) return res.status(404).json({ error: "session_not_found" });
  const attendees = await getAttendance(sessionId);
  return res.json({ session, attendees });
});

app.listen(PORT, () => {
  console.log("API QR efímero escuchando en http://localhost:" + PORT);
});

