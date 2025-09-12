// index.js (versión ESM)
import express from "express";
import cors from "cors";
import helmet from "helmet";
import { generateKeyPair, SignJWT, jwtVerify, exportJWK, importJWK } from "jose";
import { v4 as uuidv4 } from "uuid";
import bcrypt from "bcryptjs";
import { users, saveUsers } from "./users.js";

const PORT = process.env.PORT || 3000;
const TOKEN_TTL_SECONDS = 15; // cada token/QR dura 15 segundos

// Para este MVP usaremos memoria local en lugar de Redis
const usedJti = new Map();

// Sesiones de clase (profesor genera QR, alumnos hacen check-in)
const classSessions = new Map(); // sessionId -> { id, teacherCode, startedAt, expiresAt }
const attendanceBySession = new Map(); // sessionId -> [ { code, email, name, at } ]

const ALLOWED_DOMAINS = (process.env.ALLOWED_EMAIL_DOMAINS || "example.edu")
  .split(",")
  .map((d) => d.trim())
  .filter(Boolean);
const JWT_SECRET = process.env.JWT_SECRET || "dev-secret";

const app = express();
app.use(cors());
app.use(helmet());
app.use(express.json());

let privateKey;
let publicJwk;

// Generamos un par de claves (firma de tokens)
(async () => {
  const { publicKey, privateKey: pk } = await generateKeyPair("EdDSA"); // Ed25519
  privateKey = pk;
  publicJwk = await exportJWK(publicKey);
  publicJwk.kid = "ed25519-key-1";
})();

// Endpoint para publicar la clave pública (útil para verificadores)
app.get("/.well-known/jwks.json", (req, res) => {
  res.json({ keys: [publicJwk] });
});

// Endpoint de login básico
app.post("/auth/login", async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password)
    return res.status(400).json({ error: "missing_credentials" });
  const domain = email.split("@")[1];
  if (ALLOWED_DOMAINS.length && !ALLOWED_DOMAINS.includes(domain)) {
    return res.status(403).json({ error: "domain_not_allowed" });
  }
  const user = users.find((u) => u.email === email);
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

  res.json({
    token,
    user: {
      code: user.code,
      email: user.email,
      role: user.role,
      name: user.name,
      program: user.program,
      expiresAt: user.expiresAt,
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
    const exists = users.some((u) => u.email === email || u.code === code);
    if (exists) {
      return res.status(409).json({ error: "user_exists" });
    }
    const passwordHash = await bcrypt.hash(password, 10);
    const newUser = {
      code,
      email,
      name,
      role: role || "student",
      program,
      expiresAt,
      photoUrl: photo || null,
      passwordHash,
    };
    users.push(newUser);
    // Persist the new account so it can log in later
    saveUsers();
    const ephemeralCode = uuidv4();
    res.json({ success: true, ephemeralCode });
  } catch (e) {
    res.status(500).json({ error: "registration_failed" });
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
    const found = users.find((u) => u.code === code);
    const { passwordHash: _ph, ...student } = found || {};

    res.json({ token, qrUrl, ttl: TOKEN_TTL_SECONDS, student });
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

    const student = users.find((u) => u.code === payload.sub);

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

    classSessions.set(sessionId, {
      id: sessionId,
      teacherCode,
      startedAt: now,
      expiresAt: exp,
    });
    attendanceBySession.set(sessionId, []);

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
app.post("/prof/end-session", requireAuth("teacher"), (req, res) => {
  const sessionId = req.body?.sessionId || req.query?.id;
  if (!sessionId) return res.status(400).json({ error: "missing_session_id" });
  const session = classSessions.get(sessionId);
  if (!session) return res.status(404).json({ error: "session_not_found" });
  if (session.teacherCode !== req.user.code) return res.status(403).json({ error: "forbidden" });
  const now = Math.floor(Date.now() / 1000);
  session.expiresAt = now;
  classSessions.set(sessionId, session);
  const attendees = attendanceBySession.get(sessionId) || [];
  return res.json({ ok: true, session, attendees });
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

    const session = classSessions.get(sessionId);
    if (!session) return res.status(404).json({ error: "session_not_found" });

    const now = Math.floor(Date.now() / 1000);
    if (session.expiresAt && now > session.expiresAt) {
      return res.status(400).json({ error: "session_expired" });
    }

    const attendees = attendanceBySession.get(sessionId) || [];
    const already = attendees.find((a) => a.code === req.user.code);
    if (already) {
      return res.json({ ok: true, already: true, at: already.at, sessionId });
    }

    // Buscar datos del estudiante para devolver información útil
    const student = users.find((u) => u.code === req.user.code);
    const entry = {
      code: student?.code || req.user.code,
      email: student?.email,
      name: student?.name,
      at: now,
    };
    attendees.push(entry);
    attendanceBySession.set(sessionId, attendees);

    return res.json({ ok: true, sessionId, entry });
  } catch (e) {
    return res.status(401).json({ error: "invalid_session_token" });
  }
});

// Profesor consulta la asistencia de una sesión
app.get("/prof/session/:id", requireAuth("teacher"), (req, res) => {
  const sessionId = req.params.id;
  const session = classSessions.get(sessionId);
  if (!session) return res.status(404).json({ error: "session_not_found" });
  const attendees = attendanceBySession.get(sessionId) || [];
  return res.json({ session, attendees });
});

app.listen(PORT, () => {
  console.log("API QR efímero escuchando en http://localhost:" + PORT);
});
