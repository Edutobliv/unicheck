// index.js (versión ESM)
import express from "express";
import cors from "cors";
import helmet from "helmet";
import { generateKeyPair, SignJWT, jwtVerify, exportJWK, importJWK } from "jose";
import { v4 as uuidv4 } from "uuid";
import bcrypt from "bcryptjs";
import { users } from "./users.js";

const PORT = process.env.PORT || 3000;
const TOKEN_TTL_SECONDS = 15; // cada token/QR dura 15 segundos

// Para este MVP usaremos memoria local en lugar de Redis
const usedJti = new Map();

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
    },
  });
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
    const student = users.find((u) => u.code === code);

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

app.listen(PORT, () => {
  console.log("API QR efímero escuchando en http://localhost:" + PORT);
});
