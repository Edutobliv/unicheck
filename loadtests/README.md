# Pruebas de carga (Artillery y k6)

Este directorio contiene configuraciones listas para ejecutar contra tu despliegue en Render.

## Variables requeridas

Exporta estas variables antes de ejecutar (PowerShell):

```
$env:TARGET_BASE_URL = "https://TU-URL.onrender.com"
$env:TEST_EMAIL = "alumno@tu-dominio.edu"
$env:TEST_PASSWORD = "Secreta123!"
# Opcional (para flujos de profesor)
$env:TEACHER_EMAIL = "docente@tu-dominio.edu"
$env:TEACHER_PASSWORD = "SecretaDocente123!"
```

En bash:

```
export TARGET_BASE_URL=https://TU-URL.onrender.com
export TEST_EMAIL=alumno@tu-dominio.edu
export TEST_PASSWORD='Secreta123!'
export TEACHER_EMAIL=docente@tu-dominio.edu
export TEACHER_PASSWORD='SecretaDocente123!'
```

## Artillery

- Smoke test:

```
cd api_carnet
npm run load:artillery:smoke
```

- Stress test (ramp + spike):

```
cd api_carnet
npm run load:artillery:stress
```

Artillery se ejecuta via `npx` (no necesitas instalarlo como dependencia).

## k6 (opcional)

Requiere `k6` instalado localmente.

```
cd api_carnet
npm run load:k6:smoke
npm run load:k6:stress
npm run load:k6:soak
```

- `load:k6:soak`: prueba de resistencia (~2h) con carga moderada (10→30 VUs).

## Consejos

- Asegúrate de tener usuarios válidos (student y teacher) con esas credenciales en la base de datos.
- Los tokens efímeros expiran en ~15s; las pruebas los verifican inmediatamente.
- Monitorea `/__debug?k=...` durante la prueba para revisar conectividad a DB/Storage (si tienes `DEBUG_KEY`).
- Observa métricas en Render (CPU, memoria) y en tu base de datos de Supabase (conexiones, latencia) mientras se ejecutan.
