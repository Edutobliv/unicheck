# proyecto_carnet

A new Flutter project.

## Backend

The Node API uses PostgreSQL for users, sessions, and attendance.

### Quick start

1) Start Postgres with Docker (recommended):

```bash
cd api_carnet
docker compose up -d
cp .env.example .env   # adjust if needed
npm install
npm run dev            # or: npm start
```

On startup the API will ensure the schema exists and seed sample accounts if the DB is empty.

Environment variables (api_carnet/.env):

```ini
# App
PORT=3000
JWT_SECRET=supersecret
ALLOWED_EMAIL_DOMAINS=example.edu

# Database
# Either individual PG env vars or a single DATABASE_URL.
# For Supabase, prefer DATABASE_URL with SSL required.
DATABASE_URL=postgresql://<user>:<pass>@<host>:5432/postgres
```

### Sample users

Seeded on first run:

- student: `alumno1@example.edu`
- teacher: `docente@example.edu`
- porter: `portero@example.edu`

Password for all three (by default): `password123` (change in DB as needed).

The student `code` is used as the subject in tokens and to track attendance.

## Frontend

Run `flutter pub get` and then start the app on an emulator or device. The app
first shows a login screen and stores the received token to call protected
endpoints.

## Getting Started with Flutter

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
