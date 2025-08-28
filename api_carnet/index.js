// index.js (versión ESM)
import express from "express";
import cors from "cors";
import helmet from "helmet";
import { generateKeyPair, SignJWT, jwtVerify, exportJWK, importJWK } from "jose";
import { v4 as uuidv4 } from "uuid";

const PORT = process.env.PORT || 3000;
const TOKEN_TTL_SECONDS = 15; // cada token/QR dura 15 segundos

// Para este MVP usaremos memoria local en lugar de Redis
const usedJti = new Map();

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

// Middleware ficticio de autenticación
function requireStudent(req, res, next) {
  req.user = { studentId: "student_12345", deviceId: "demo-device" };
  next();
}

// Endpoint que emite un QR efímero
app.post("/issue-ephemeral", requireStudent, async (req, res) => {
  try {
    const { studentId, deviceId } = req.user;
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
      .setSubject(studentId)
      .setJti(jti)
      .sign(privateKey);

    usedJti.set(jti, false);
    setTimeout(() => usedJti.delete(jti), TOKEN_TTL_SECONDS * 1000 + 2000);

    const qrUrl = `http://localhost:${PORT}/verify?t=${encodeURIComponent(token)}`;

    res.json({ token, qrUrl, ttl: TOKEN_TTL_SECONDS });
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

    const student = { id: payload.sub, name: "María Pérez", program: "Ingeniería", status: "ACTIVO" };

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
