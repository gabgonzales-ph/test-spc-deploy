// src/lib/download/fileToken.ts
// SERVER ONLY. Never import this from a client component: the key must not reach the browser.
//
// Turns a storage path ("forms/permits_licensing/abc.pdf") into an opaque,
// tamper-proof token, and back. Deterministic: the same path always gives the
// same token, so CDN caching and shared links keep working.
//
// Setup: generate a key once with `openssl rand -base64 32`
// and set it as FILE_TOKEN_KEY in .env.local and in Vercel.
// WARNING: changing the key invalidates every token already published.

import { createCipheriv, createDecipheriv, createHmac } from "crypto";

function getKey(): Buffer {
  const raw = process.env.FILE_TOKEN_KEY;
  if (!raw) throw new Error("FILE_TOKEN_KEY is not set");
  const key = Buffer.from(raw, "base64");
  if (key.length !== 32) {
    throw new Error("FILE_TOKEN_KEY must be 32 bytes (base64 of `openssl rand -base64 32`)");
  }
  return key;
}

// Synthetic IV derived from the path (deterministic, so tokens are stable).
function ivFor(key: Buffer, path: string): Buffer {
  return createHmac("sha256", key).update(path).digest().subarray(0, 12);
}

export function encodePath(path: string): string {
  const key = getKey();
  const iv = ivFor(key, path);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const enc = Buffer.concat([cipher.update(path, "utf8"), cipher.final()]);
  // layout: iv (12) | auth tag (16) | ciphertext
  return Buffer.concat([iv, cipher.getAuthTag(), enc]).toString("base64url");
}

export function decodePath(token: string): string | null {
  try {
    const key = getKey();
    const buf = Buffer.from(token, "base64url");
    if (buf.length < 29) return null;
    const decipher = createDecipheriv("aes-256-gcm", key, buf.subarray(0, 12));
    decipher.setAuthTag(buf.subarray(12, 28));
    return Buffer.concat([decipher.update(buf.subarray(28)), decipher.final()]).toString("utf8");
  } catch {
    return null; // tampered, truncated or garbage
  }
}

/** Public URL for a file stored in the "documents" bucket. */
export function downloadUrl(filePath: string): string {
  return `/api/download/${encodePath(filePath)}`;
}
