# Unicheck - Carnet Digital y Asistencia

[![Flutter](https://img.shields.io/badge/Frontend-Flutter-02569B?logo=flutter)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Backend-Node.js-339933?logo=nodedotjs)](https://nodejs.org)
[![Express.js](https://img.shields.io/badge/Framework-Express.js-000000?logo=express)](https://expressjs.com)
[![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL-336791?logo=postgresql)](https://www.postgresql.org)
[![Supabase](https://img.shields.io/badge/PaaS-Supabase-3FCF8E?logo=supabase)](https://supabase.com)

**Unicheck** es una solución integral para la gestión de identidad y asistencia en entornos educativos. Consiste en una aplicación móvil multiplataforma (Flutter) para estudiantes, docentes y personal de seguridad, y una API robusta (Node.js/Express) que gestiona la lógica de negocio.

---

## ✨ Características Principales

-   **Carnet Digital con QR Efímero**: Los estudiantes pueden generar un carnet digital con un código QR que expira a los pocos segundos, garantizando que no pueda ser reutilizado o falsificado.
-   **Validación de Acceso en Portería**: El personal de seguridad puede escanear los QR para validar el acceso al campus, registrando cada evento (entrada/salida).
-   **Gestión de Asistencia a Clases**:
    -   **Docentes**: Pueden iniciar y finalizar sesiones de clase, generando un QR único para cada sesión.
    -   **Estudiantes**: Escanean el QR de la clase para registrar su asistencia.
    -   **Reportes**: Los docentes pueden ver reportes de asistencia en tiempo real y consultar el historial.
-   **Roles de Usuario**: Sistema de permisos diferenciado para `student`, `teacher` y `porter`.
-   **Gestión de Perfil**: Los usuarios pueden subir y actualizar su foto de perfil, almacenada de forma segura.

---

## 🛠️ Tech Stack

| Componente | Tecnología | Descripción |
| :--- | :--- | :--- |
| **Frontend** | Flutter | Aplicación móvil para Android, iOS y Web. |
| **Backend** | Node.js, Express.js | API RESTful para toda la lógica de negocio. |
| **Base de Datos** | PostgreSQL | Alojada en Supabase para persistencia de datos. |
| **Autenticación** | JWT (HS256 & EdDSA) | Tokens de sesión y tokens efímeros para los QR. |
| **Almacenamiento** | Supabase Storage | Bucket privado para las fotos de perfil de los usuarios. |
| **Despliegue** | Render | Configuración "Infrastructure as Code" con `render.yaml`. |

---

## 📁 Estructura del Proyecto

```
.
├── api_carnet/         # Backend en Node.js (Express)
│   ├── index.js        # Punto de entrada del servidor
│   ├── openapi.yaml    # Especificación de la API
│   ├── package.json    # Dependencias y scripts
│   └── ...
├── lib/                # Código fuente de la aplicación Flutter
│   ├── main.dart       # Punto de entrada de la app
│   ├── login_page.dart # Lógica de UI para las páginas
│   └── ...
├── assets/             # Imágenes y otros recursos estáticos
├── pubspec.yaml        # Dependencias y configuración de Flutter
├── render.yaml         # Blueprint para despliegue en Render
└── README.md           # Este archivo
```

---

## 🚀 Puesta en Marcha

### Requisitos Previos

-   **Node.js**: Versión `20.x` o superior.
-   **Flutter**: Versión `3.x` o superior.
-   **Supabase**: Un proyecto creado para la base de datos y el almacenamiento.
-   **(Opcional) Docker**: Para una base de datos PostgreSQL local.

### 1. Configuración del Backend (`api_carnet`)

1.  **Navega al directorio de la API:**
    ```bash
    cd api_carnet
    ```

2.  **Instala las dependencias:**
    ```bash
    npm install
    ```

3.  **Configura las variables de entorno:**
    Copia el archivo de ejemplo y edítalo con tus credenciales de Supabase y secretos.
    ```bash
    cp .env.example .env
    ```
    **Variables clave en `.env`:**
    -   `DATABASE_URL`: La URL de conexión a tu base de datos PostgreSQL (se recomienda el Pooler de Supabase).
    -   `JWT_SECRET`: Un secreto robusto para firmar los tokens de sesión.
    -   `SUPABASE_URL`: La URL de tu proyecto Supabase.
    -   `SUPABASE_SERVICE_ROLE`: La clave de servicio (`service_role`) de Supabase.

4.  **Inicia el servidor en modo desarrollo:**
    El servidor se reiniciará automáticamente con cada cambio.
    ```bash
    npm run dev
    ```
    La API estará disponible en `http://localhost:3000`.

### 2. Configuración del Frontend (Flutter App)

1.  **Instala las dependencias de Flutter** desde el directorio raíz del proyecto:
    ```bash
    flutter pub get
    ```

2.  **Ejecuta la aplicación:**
    Por defecto, la app apunta a la API desplegada en Render. Para apuntar a tu backend local, usa la variable `--dart-define`.

    -   **Para emulador de Android:**
        ```bash
        flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
        ```
    -   **Para simulador de iOS o web:**
        ```bash
        flutter run --dart-define=API_BASE_URL=http://localhost:3000
        ```
    -   **Para un dispositivo físico:**
        Usa la dirección IP de tu máquina en la red local.
        ```bash
        flutter run --dart-define=API_BASE_URL=http://<TU_IP_LAN>:3000
        ```

---

## 📖 Documentación de la API

La API expone su documentación a través de Swagger UI. Una vez que el backend esté corriendo, puedes acceder a ella en:
**`http://localhost:3000/docs`**

A continuación, un resumen de los endpoints disponibles.

### System

| Método | Endpoint | Descripción |
| :--- | :--- | :--- |
| `GET` | `/health` | Verifica el estado de salud de la API. |
| `GET` | `/.well-known/jwks.json` | Expone la clave pública para verificar los QR efímeros. |

### Auth

| Método | Endpoint | Rol Requerido | Descripción |
| :--- | :--- | :--- | :--- |
| `POST` | `/auth/register` | Público | Registra un nuevo usuario. |
| `POST` | `/auth/login` | Público | Inicia sesión y devuelve un token JWT. |
| `POST` | `/auth/refresh` | Público | Refresca un token de sesión expirado. |

### Users

| Método | Endpoint | Rol Requerido | Descripción |
| :--- | :--- | :--- | :--- |
| `GET` | `/users/me/photo-url` | `student`, `teacher`, `porter` | Obtiene una URL firmada y temporal para la foto de perfil. |
| `PUT` | `/users/me/photo` | `student`, `teacher`, `porter` | Sube o actualiza la foto de perfil (en formato Data URL). |
| `DELETE`| `/users/me/photo` | `student`, `teacher`, `porter` | Elimina la foto de perfil del usuario. |

### QR & Verify

| Método | Endpoint | Rol Requerido | Descripción |
| :--- | :--- | :--- | :--- |
| `POST` | `/issue-ephemeral` | `student` | Emite un nuevo carnet digital con QR efímero. |
| `POST` | `/verify` | Público | Verifica la validez de un token de QR. Puede ser usado por un `porter` para registrar el evento. |

### Professor & Attendance

| Método | Endpoint | Rol Requerido | Descripción |
| :--- | :--- | :--- | :--- |
| `POST` | `/prof/start-session` | `teacher` | Inicia una nueva sesión de clase para tomar asistencia. |
| `POST` | `/prof/end-session` | `teacher` | Finaliza una sesión de clase y obtiene el reporte. |
| `GET` | `/prof/session/{id}` | `teacher` | Obtiene los detalles y asistentes de una sesión específica. |
| `POST` | `/attendance/check-in` | `student` | Registra la asistencia de un estudiante a una clase. |
| `POST` | `/prof/attendance/add` | `teacher` | Añade manualmente a un estudiante a una sesión de asistencia. |
| `DELETE`| `/prof/attendance` | `teacher` | Elimina un registro de asistencia. |
| `GET` | `/prof/students/search`| `teacher` | Busca estudiantes por nombre o código. |

---

## ☁️ Despliegue en Render

Este repositorio está configurado para un despliegue automático en [Render](https://render.com/) usando el archivo `render.yaml`.

1.  Crea una cuenta en Render y conecta este repositorio.
2.  Crea un nuevo servicio de tipo **Blueprint**. Render detectará `render.yaml` automáticamente.
3.  Configura las **Variables de Entorno** en el dashboard de Render con las mismas credenciales que usaste en tu archivo `.env` local.
4.  Render desplegará la API y la hará accesible a través de una URL pública. El health check se realiza en el endpoint `/health`.

---

## 🔧 Configuración de Supabase

### Base de Datos

El esquema de la base de datos incluye tablas para `users`, `class_sessions`, `attendance`, `gates`, y `access_events`. Se recomienda ejecutar el SQL en `api_carnet/sql/session_reports.sql` para crear una vista que facilite los reportes de asistencia.

### Almacenamiento (Storage)

1.  Ve a la sección de **Storage** en tu dashboard de Supabase.
2.  Crea un nuevo bucket llamado `avatars`.
3.  **Importante**: Asegúrate de que el bucket sea **privado**. La API se encargará de generar URLs firmadas y temporales para acceder a las imágenes de forma segura.

<details>
<summary>
🧪 Ejemplos con cURL
</summary>

Reemplaza `BASE` con la URL de tu API (local o desplegada).

```bash
BASE=http://localhost:3000

# 1. Registrar un estudiante
curl -X POST "$BASE/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "code":"U123456",
    "email":"test@example.edu",
    "name":"Test Estudiante",
    "firstName": "Test",
    "lastName": "Estudiante",
    "password":"P@ssw0rd123",
    "program":"Ingenieria de Sistemas"
  }'

# 2. Iniciar sesión para obtener un token
TOKEN=$(curl -s -X POST "$BASE/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.edu","password":"P@ssw0rd123"}' | jq -r .token)

echo "Token obtenido: $TOKEN"

# 3. Emitir un QR efímero (como estudiante)
curl -X POST "$BASE/issue-ephemeral" \
  -H "Authorization: Bearer $TOKEN"

# 4. Iniciar una sesión de clase (como profesor, requiere un token de docente)
TEACHER_TOKEN="<token_de_profesor>"
curl -X POST "$BASE/prof/start-session" \
  -H "Authorization: Bearer $TEACHER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ttlSeconds": 600}'
```
</details>