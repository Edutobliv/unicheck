import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_FILE = path.join(__dirname, 'users.json');

let users = [];

try {
  const data = fs.readFileSync(DATA_FILE, 'utf8');
  users = JSON.parse(data);
} catch {
  users = [
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
  ];
  fs.writeFileSync(DATA_FILE, JSON.stringify(users, null, 2));
}

function saveUsers() {
  fs.writeFileSync(DATA_FILE, JSON.stringify(users, null, 2));
}

export { users, saveUsers };
