import { createClient } from '@supabase/supabase-js';
import sharp from 'sharp';
import { v4 as uuidv4 } from 'uuid';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE;
const AVATAR_BUCKET = process.env.AVATAR_BUCKET || 'avatars';

// Create a Supabase client using the service role key (server-side only)
export function supabaseAdmin() {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE) {
    throw new Error('Supabase credentials missing. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE');
  }
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, {
    auth: { persistSession: false },
  });
}

const ALLOWED_MIME = new Set(['image/jpeg','image/png','image/webp']);

export function parseDataUrl(dataUrl) {
  // Accepts data URL like: data:image/png;base64,AAA...
  // Returns: { mime, buffer }
  const m = /^data:([^;]+);base64,(.*)$/i.exec(dataUrl || '');
  if (!m) throw new Error('Invalid data URL');
  const mime = m[1].toLowerCase();
  if (!ALLOWED_MIME.has(mime)) {
    throw new Error('Unsupported image type');
  }
  const b64 = m[2];
  return { mime, buffer: Buffer.from(b64, 'base64') };
}

async function toWebpUnderMaxBytes(input, maxBytes) {
  // Progressive quality and resizing to fit under maxBytes
  // Start with a moderate cap on width/height
  let maxWidth = 1200; // initial dimension cap
  const minWidth = 600;
  const qualitySteps = [82, 75, 68, 60, 50, 40, 30];

  while (true) {
    for (const q of qualitySteps) {
      const img = sharp(input).rotate();
      const meta = await img.metadata();
      const needsResize = meta.width && meta.width > maxWidth;
      const pipeline = needsResize ? img.resize({ width: maxWidth }) : img;
      const out = await pipeline.webp({ quality: q }).toBuffer();
      if (out.length <= maxBytes) {
        return { buffer: out, mime: 'image/webp' };
      }
    }
    if (maxWidth <= minWidth) break;
    maxWidth = Math.max(minWidth, Math.floor(maxWidth * 0.85));
  }
  // If still larger, return the smallest attempt at the lowest quality/size
  const out = await sharp(input).rotate().resize({ width: minWidth }).webp({ quality: 30 }).toBuffer();
  return { buffer: out, mime: 'image/webp' };
}

export async function optimizeImageToMax3MB(inputBuffer) {
  const MAX = 3 * 1024 * 1024; // 3MB
  // If already small enough, still convert to webp to optimize delivery
  const { buffer, mime } = await toWebpUnderMaxBytes(inputBuffer, MAX);
  return { buffer, mime };
}

export async function uploadUserAvatarFromDataUrl(dataUrl, userCode) {
  const { buffer: raw } = parseDataUrl(dataUrl);
  const { buffer, mime } = await optimizeImageToMax3MB(raw);

  const sb = supabaseAdmin();
  const filename = uuidv4() + (mime === 'image/webp' ? '.webp' : '.img');
  const path = `users/${userCode}/${filename}`;
  const { error } = await sb.storage.from(AVATAR_BUCKET).upload(path, buffer, {
    contentType: mime,
    upsert: false,
  });
  if (error) throw error;
  return path; // Store this path in DB
}

export async function createSignedAvatarUrl(path, expiresInSec = 300) {
  const sb = supabaseAdmin();
  const { data, error } = await sb.storage.from(AVATAR_BUCKET).createSignedUrl(path, expiresInSec);
  if (error) throw error;
  return data?.signedUrl;
}

export async function deleteAvatarPath(path) {
  if (!path) return { error: null };
  const sb = supabaseAdmin();
  const { data, error } = await sb.storage.from(AVATAR_BUCKET).remove([path]);
  // If object doesn't exist, Supabase still returns success; ignore errors for idempotency
  return { data, error };
}

// Upload to a fixed, predictable path per user to avoid acumulating old files
export async function replaceUserAvatarFromDataUrl(dataUrl, userCode, oldPath) {
  const { buffer: raw } = parseDataUrl(dataUrl);
  const { buffer, mime } = await optimizeImageToMax3MB(raw);
  const sb = supabaseAdmin();
  const newPath = `users/${userCode}/avatar.webp`;
  const { error } = await sb.storage.from(AVATAR_BUCKET).upload(newPath, buffer, {
    contentType: 'image/webp',
    upsert: true,
  });
  if (error) throw error;
  if (oldPath && oldPath !== newPath) {
    try { await sb.storage.from(AVATAR_BUCKET).remove([oldPath]); } catch {}
  }
  return newPath;
}
