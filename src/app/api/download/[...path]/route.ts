// src/app/api/download/[...path]/route.ts
//
// Serves PDFs from the public "documents" bucket.
//
//   NEW     /api/download/<token>                          (opaque, encrypted path)
//   LEGACY  /api/download/documents/forms/x/abc.pdf        -> 301 redirect to the token URL
//
// Remove the LEGACY branch once all stored links (articles, markdown, Google) are updated.

import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "crypto";
import { encodePath, decodePath } from "@/lib/download/fileToken";
import { getDownloadName, contentDisposition } from "@/lib/download/downloadName";

const CLIENT_COOKIE = "cc_client_id";
const MAX_DOWNLOADS = 3;
const RATE_WINDOW = 30 * 60_000; // 30 minutes

const BUCKET = "documents";

// Files in the same bucket that must never be served by this route
// (CSM PDF/Excel templates are used server-side only).
const BLOCKED_PREFIXES = ["forms/csm/"];

// key = `${clientId}:${fileId}` -> tracks downloads per client, per file
//
// NOTE: responses are served with `Cache-Control: public, s-maxage=86400`, so
// most requests are served from Vercel's edge cache and never reach this
// handler. This rate limiter only runs on cache misses, so it does not reliably
// enforce MAX_DOWNLOADS per client. Known, accepted tradeoff (CDN caching was
// prioritized to reduce Supabase egress). For strict limits use Vercel Firewall
// rate limiting, or switch Cache-Control back to `private, max-age=3600`.
const downloadMap = new Map<string, { count: number; resetAt: number }>();

// periodic cleanup so the map doesn't grow forever
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of downloadMap.entries()) {
    if (now > entry.resetAt) downloadMap.delete(key);
  }
}, 5 * 60_000).unref();

function isDownloadLimited(clientId: string, fileId: string): boolean {
  const key = `${clientId}:${fileId}`;
  const now = Date.now();
  const entry = downloadMap.get(key);

  if (!entry || now > entry.resetAt) {
    downloadMap.set(key, { count: 1, resetAt: now + RATE_WINDOW });
    return false;
  }

  if (entry.count >= MAX_DOWNLOADS) return true;

  entry.count++;
  return false;
}

function isAllowedPath(filePath: string): boolean {
  return (
    filePath.endsWith(".pdf") &&
    !filePath.includes("..") &&
    !filePath.includes("//") &&
    !filePath.startsWith("/") &&
    !BLOCKED_PREFIXES.some((p) => filePath.startsWith(p))
  );
}

function setClientCookie(res: NextResponse, clientId: string) {
  res.cookies.set(CLIENT_COOKIE, clientId, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    maxAge: 60 * 60 * 24 * 365,
    path: "/",
  });
}

// Same response for every failure, so nothing leaks about what exists.
const notFound = () => new NextResponse("Not found", { status: 404 });

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path: segments } = await params;

  // ---------------------------------------------------------------
  // LEGACY: /api/download/documents/<folder>/<file>.pdf -> 301 to token URL
  // ---------------------------------------------------------------
  if (segments.length >= 2) {
    const [bucket, ...rest] = segments;
    const legacyPath = rest.join("/");

    if (bucket !== BUCKET || !isAllowedPath(legacyPath)) return notFound();

    const res = NextResponse.redirect(
      new URL(`/api/download/${encodePath(legacyPath)}`, req.url),
      301
    );
    res.headers.set("Cache-Control", "public, s-maxage=86400");
    return res;
  }

  // ---------------------------------------------------------------
  // NEW: /api/download/<token>
  // ---------------------------------------------------------------
  const filePath = decodePath(segments[0] ?? "");
  if (!filePath || !isAllowedPath(filePath)) return notFound();

  // identify the client via cookie (create one if missing)
  const existingCookie = req.cookies.get(CLIENT_COOKIE)?.value;
  const clientId = existingCookie || randomUUID();
  const fileId = `${BUCKET}/${filePath}`;

  if (isDownloadLimited(clientId, fileId)) {
    const res = new NextResponse(
      "Download limit reached for this file. Try again in a bit.",
      { status: 429 }
    );
    if (!existingCookie) setClientCookie(res, clientId);
    return res;
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!supabaseUrl) {
    return new NextResponse("Server misconfiguration", { status: 500 });
  }

  // Encode each segment (keeps "/" separators, escapes spaces, "ñ", etc.)
  const encodedPath = filePath.split("/").map(encodeURIComponent).join("/");
  const storageUrl = `${supabaseUrl}/storage/v1/object/public/${BUCKET}/${encodedPath}`;

  let upstream: Response;
  try {
    // Public object path: no auth header needed.
    upstream = await fetch(storageUrl);
  } catch {
    return new NextResponse("Failed to fetch file", { status: 502 });
  }

  if (!upstream.ok) return notFound();

  const fileName = await getDownloadName(filePath);

  const contentLength = upstream.headers.get("content-length");
  const headers = new Headers({
    "Content-Type": "application/pdf",
    "Content-Disposition": contentDisposition(fileName, "inline"),
    // `public` + `s-maxage` lets Vercel's edge cache PDFs, cutting repeat
    // Supabase egress (see the note on downloadMap above).
    // The filename in Content-Disposition is cached too: after adding titles,
    // already-cached files keep the old name until the cache expires or is purged.
    "Cache-Control": "public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "SAMEORIGIN",
  });

  if (contentLength) headers.set("Content-Length", contentLength);

  const res = new NextResponse(upstream.body, { status: 200, headers });
  if (!existingCookie) setClientCookie(res, clientId);

  return res;
}