# Unicheck — Carnet Digital y Asistencia (Flutter + Node + Supabase)

Aplicación móvil (Flutter) y API (Node.js/Express) para:

- Validación de credenciales del estudiante en portería (acceso al campus) mediante QR efímero.
- Control de asistencia a clases para docentes (creación de sesiones, check‑in de estudiantes y reportes).

El backend usa PostgreSQL (Supabase) y Supabase Storage para los avatares. Está preparado para desplegarse en Render con el blueprint `render.yaml`.

---

**Contenido**

- Arquitectura y requisitos
- Configuración y ejecución local (API + App)
- Despliegue en Render (backend)
- Configuración Supabase (DB + Storage)
- Esquema de base de datos y SQL útil (vistas/trigger)
- Endpoints principales del API
- Datos de prueba
- Depuración y resolución de problemas

---

## Arquitectura

- Frontend: Flutter (Android/iOS/Web/Escritorio). Base de API configurable por `--dart-define=API_BASE_URL` (por defecto apunta al servicio de Render).
- Backend: Node.js (ESM) con Express. JWT HS256 para sesiones de usuario y EdDSA (Ed25519) efímero para QR de acceso.
- Base de datos: PostgreSQL (Supabase). Se crean tablas para `users`, `class_sessions`, `attendance`, `used_jti`, `gates`, `access_events`.
- Almacenamiento: Supabase Storage (bucket privado `avatars`) para fotos; el API genera URLs firmadas temporales.

## Requisitos

- Node.js 20+
- npm 9+
- Flutter estable (3.x+)
- Proyecto Supabase (URL y `service_role`)
- (Opcional) Docker para Postgres local

## Ejecución Local (Backend)

```bash
cd api_carnet
npm install

# Configura tu entorno local copiando el ejemplo
cp .env.example .env

# Edita .env con tus valores (ver sección Variables de entorno)

# Arranca en desarrollo
npm run dev  # usa nodemon
# ó en modo producción local
npm start
```

Variables de entorno clave (`api_carnet/.env` o Render):

- `DATABASE_URL` (recomendado Pooler de Supabase):
  `postgresql://<user>.<ref>:<password>@aws-0-<region>.pooler.supabase.com:6543/postgres?sslmode=require&options=project%3D<ref>`
- `JWT_SECRET`: secreto fuerte para firmar tokens de sesión.
- `SUPABASE_URL`: `https://<ref>.supabase.co`.
- `SUPABASE_SERVICE_ROLE`: clave `service_role` del proyecto (mantener en secreto; sólo servidor).
- `AVATAR_BUCKET` (opcional): nombre de bucket privado (default `avatars`).
- `PUBLIC_BASE_URL` (opcional): URL pública del API (si no, Render usará `RENDER_EXTERNAL_URL`).
- `ALLOWED_EMAIL_DOMAINS` (opcional): restringir correos de registro (coma‑separado).
- `DEBUG_KEY` (opcional, sólo staging): habilita `GET /__debug`.

## Despliegue en Render

Este repositorio trae un `render.yaml` para Blueprint Deploy.

1) Conecta el repo a Render y crea “New → Blueprint”.
2) Render creará el servicio web apuntando a `api_carnet/`.
3) Configura Secrets en el servicio:
   - `DATABASE_URL`
   - `JWT_SECRET`
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE`
   - `AVATAR_BUCKET` (opcional)
   - `PUBLIC_BASE_URL` (opcional)
   - `DEBUG_KEY` (temporal para `/__debug`)
4) Deploy. Healthcheck: `GET /health` → `{ ok: true }`.

Notas de Render:

- El servidor escucha en `0.0.0.0` y auto‑detecta la URL pública.
- Si tu Postgres rechaza TLS o SNI, revisa que `sslmode=require` esté en `DATABASE_URL`.

## Configuración de Supabase

- Base de datos: ejecuta las migraciones recomendadas (ver sección SQL). 
- Storage: crea un bucket privado `avatars`. No necesitas políticas públicas; el API genera URLs firmadas temporales.

## App Flutter

```bash
flutter pub get

# Por defecto apunta al API desplegado en Render
flutter run

# Para apuntar a otra API (ej. local):
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000   # Emulador Android
```

Optimizaciones implementadas:

- El carnet obtiene una URL firmada del avatar directamente en `POST /issue-ephemeral` y la cachea con su expiración para no re‑pedirla hasta que venza.

## Esquema y SQL útil

Tablas principales (resumen):

- `users` (con `first_name`, `middle_name`, `last_name`, `second_last_name`, `expires_on` y `photo_url`).
- `class_sessions` (sesiones de clase; `offering_id` opcional).
- `attendance` (asistencias con `status`, `source`, `recorded_by`).
- `used_jti` (JTI efímeros; protección contra reuso).
- `gates` (puertas de acceso) y `access_events` (logs de portería).

Vistas/Triggers:

- Vista de resumen por sesión (totales por estado): archivo `api_carnet/sql/session_reports.sql`.
- Trigger para mantener `users.name` sincronizado a partir de nombres/apellidos (ver ejemplo en la sección de SQL avanzada más abajo si lo necesitas).

## Endpoints (resumen)

- `GET /health` → `{ ok: true }`.
- `GET /.well-known/jwks.json` → clave pública EdDSA (verificación de tokens efímeros).
- `POST /auth/register` → crea estudiante. Cuerpo JSON:
  - `code`, `email`, `name`, `password`, `program`, `expiresAt?` (DD/MM/AAAA), `photo?` en `data:image/...;base64,...`.
  - Devuelve `{ success, ephemeralCode, user }`.
- `POST /auth/login` → `{ token, user }`. 
  - Si el usuario es estudiante y su vencimiento faltaba o expiró, se renueva por 6 meses automáticamente.
- `POST /issue-ephemeral` (Bearer) → emite QR efímero:
  - `{ token, qrUrl, ttl, student { ..., photoUrl (firmada), photoUrlExpiresIn }, ephemeralCode }`.
- `POST /verify` → verificación (portería). 
  - Acepta `t` en query o `token` en body; opcional `Authorization: Bearer <porter>`, `gate`, `direction`.
  - Responde `{ valid, student }` o `{ valid:false, reason }`. Registra evento en `access_events`.
- `POST /prof/start-session` (teacher) → inicia sesión de clase. Body: `{ ttlSeconds?, offeringId? }`.
- `POST /attendance/check-in` (student) → envía `sessionToken` (`ATTEND:...`).
- `POST /prof/end-session` (teacher) → finaliza y devuelve asistentes.
- `GET /prof/session/:id` (teacher) → detalle de asistencia.
- `GET /__debug?k=...` (sólo staging) → verifica DB/Storage (controlado por `DEBUG_KEY`).

## Datos de Prueba

Usuarios de ejemplo (password para todos: `password123`):

- Docentes: `carolina.alvarez@profes.upc.edu.co`, `andres.salazar@profes.upc.edu.co`
- Porteros: `luis.medina@seguridad.upc.edu.co`, `nelson.patino@seguridad.upc.edu.co`
- Estudiantes: uno por programa (p. ej. `santiago.rojas@upc.edu.co`, `felipe.garcia@upc.edu.co`, etc.)

El código del estudiante (`code`) es el sujeto en tokens y la clave para asistencia.

## Ejemplos cURL (rápidos)

Reemplaza `BASE=https://unicheck-api-qr.onrender.com` con tu URL.

```bash
BASE=https://unicheck-api-qr.onrender.com

# 1) Registro (estudiante)
curl -sS -X POST "$BASE/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "code":"U123456",
    "email":"test@example.edu",
    "name":"Test Estudiante",
    "password":"P@ssw0rd123",
    "program":"Ingenieria de Sistemas"
  }'

# 2) Login → guarda el token
TOKEN=$(curl -sS -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"email":"test@example.edu","password":"P@ssw0rd123"}' | jq -r .token)
echo "TOKEN=$TOKEN"

# 3) Emitir QR efímero (alumno)
curl -sS -X POST "$BASE/issue-ephemeral" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}'

# 4) Obtener URL firmada de foto (si no vino en #3)
curl -sS -H "Authorization: Bearer $TOKEN" "$BASE/users/me/photo-url"

# 5) Subir/actualizar foto (data URL mínima de 1x1 PNG)
curl -sS -X PUT "$BASE/users/me/photo" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"photo":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII="}'

# 6) Iniciar sesión de clase (docente)
TEACHER_TOKEN=... # token de un usuario con rol teacher
curl -sS -X POST "$BASE/prof/start-session" \
  -H "Authorization: Bearer $TEACHER_TOKEN" -H "Content-Type: application/json" \
  -d '{"ttlSeconds": 900}'

# 7) Check-in de asistencia (alumno)
# Usa el sessionToken devuelto en #6 dentro de ATTEND:...
SESSION_TOKEN=... # el valor después del prefijo ATTEND:
curl -sS -X POST "$BASE/attendance/check-in" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"sessionToken":"'$SESSION_TOKEN'"}'

# 8) Finalizar sesión de clase (docente)
SESSION_ID=... # devuelta en #6
curl -sS -X POST "$BASE/prof/end-session" \
  -H "Authorization: Bearer $TEACHER_TOKEN" -H "Content-Type: application/json" \
  -d '{"sessionId":"'$SESSION_ID'"}'

# 9) Ver detalle de asistencia (docente)
curl -sS -H "Authorization: Bearer $TEACHER_TOKEN" "$BASE/prof/session/$SESSION_ID"
```

> Consejo: si no tienes `jq`, cambia los comandos que lo usan por inspección manual del JSON.

## Preguntas Frecuentes (FAQ)

- No carga la foto en el carnet
  - Asegúrate de que el usuario tenga `photo_url` en DB y que el bucket `avatars` sea privado.
  - El API devuelve una URL firmada en `POST /issue-ephemeral`; el front la cachea hasta su expiración.

- Error 500 tras desplegar en Render
  - Revisa `DATABASE_URL`: usa el Pooler y `sslmode=require` (y `options=project=<ref>` si aplica).
  - Valida `/__debug?k=...` con `DEBUG_KEY` temporal para ver `db.ok` y `storage.ok`.

- “forbidden” en `/__debug`
  - La clave no coincide o no se recargó el servicio. Ajusta `DEBUG_KEY` y haz Manual Deploy.

- El login dice “Credenciales inválidas” pero los usuarios existen
  - Si usas códigos, recuerda que deben ser numéricos (validado en el frontend). 
  - Asegúrate de que el password sea `password123` para los usuarios de prueba o actualiza el hash.

- Android emulador no conecta al backend local
  - Usa `--dart-define=API_BASE_URL=http://10.0.2.2:3000`.

- ¿Cómo cambio el dominio de la API?
  - Define `PUBLIC_BASE_URL` en Render o usa un dominio custom; el servidor construye QR/issuer con esa URL.

## Depuración y Consejos

- Error TLS en Postgres (SELF_SIGNED_CERT_IN_CHAIN): usa `sslmode=require` en `DATABASE_URL` o el Pooler de Supabase.
- Foto no muestra: asegúrate de que exista `photo_url` en DB y que el bucket `avatars` sea privado; el API devuelve una URL firmada.
- Minimiza requests: el carnet cachea la URL firmada y la renueva al vencer.

## Scripts de prueba

- `api_carnet/scripts/smoke.http` (REST Client) y `api_carnet/scripts/smoke.js` (Node) para probar registro/login/foto.

---

## Apéndice — SQL de apoyo

Vista de resumen por sesión (si no la tienes ya):

```sql
create or replace view public.session_attendance_summary as
select
  s.id as session_id,
  s.teacher_code,
  extract(epoch from s.started_at)::bigint as started_at,
  extract(epoch from s.expires_at)::bigint as expires_at,
  s.offering_id,
  count(a.id) as total,
  count(a.id) filter (where a.status = 'present') as present,
  count(a.id) filter (where a.status = 'late') as late,
  count(a.id) filter (where a.status = 'excused') as excused,
  count(distinct a.student_code) as unique_students
from public.class_sessions s
left join public.attendance a on a.session_id = s.id
group by s.id, s.teacher_code, s.started_at, s.expires_at, s.offering_id
order by s.started_at desc;
```

Trigger para mantener `users.name` sincronizado (opcional):

```sql
create or replace function public.users_sync_full_name()
returns trigger language plpgsql as $$
begin
  new.name := btrim(
    regexp_replace(
      concat_ws(' ', coalesce(new.first_name,''), coalesce(new.middle_name,''), coalesce(new.last_name,''), coalesce(new.second_last_name,'')),
      '\\s+', ' ', 'g'
    )
  );
  return new;
end; $$;

drop trigger if exists trg_users_sync_full_name on public.users;
create trigger trg_users_sync_full_name
before insert or update of first_name, middle_name, last_name, second_last_name, name
on public.users for each row execute function public.users_sync_full_name();
```

---

## English (Brief)

- Flutter app + Node/Express API on Render. Postgres on Supabase with Storage for avatars.
- Env vars: `DATABASE_URL`, `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE`, optional `AVATAR_BUCKET`, `PUBLIC_BASE_URL`.
- Key endpoints: `/auth/register`, `/auth/login`, `/issue-ephemeral`, `/verify`, `/prof/start-session`, `/attendance/check-in`.
- Debug: `/__debug?k=...` controlled by `DEBUG_KEY` (staging only).
- The app caches signed avatar URLs and refreshes on expiry.
