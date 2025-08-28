# proyecto_carnet

A new Flutter project.

## Backend

The Node API now exposes authentication with JWT. Before running, configure:

```bash
export JWT_SECRET=supersecret
export ALLOWED_EMAIL_DOMAINS=example.edu
```

Then start the API from `api_carnet/`:

```bash
node index.js
```

### Sample users

The demo comes with:

- student: `alumno1@example.edu` / `password123`
- teacher: `docente@example.edu` / `password123`
- porter: `portero@example.edu` / `password123`

The student code is used as the main identifier across the system.

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
