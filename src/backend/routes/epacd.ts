import { Elysia, t } from "elysia";
import nodemailer from "nodemailer";
import { verifyRecaptcha } from "../utils/recaptcha";
import { supabase } from "../config/database";

// EPACD (Electronic Public Assistance Complaints Desk) route
// Receives complaint submissions from the public site and forwards
// them via email to the designated recipient.

const RECIPIENT_EMAIL = "epacd.spc@gmail.com";

// ---- Validation rules -----------------------------------------------
// givenName / surname: required
// middleName / suffix: optional
// address: region/province/city/barangay come from PSGC dropdowns (codes + labels),
//          so they're validated as non-empty strings (selection required), plus
//          an optional free-text street/unit line capped at a sane length.
// contact: exactly 11 digits (PH mobile format, e.g. 09XXXXXXXXX)
// email: optional, max 30 chars
// message: required, max 255 chars

const epacdBody = t.Object({
  givenName: t.String({ minLength: 1, maxLength: 50 }),
  middleName: t.Optional(t.String({ maxLength: 50 })),
  surname: t.String({ minLength: 1, maxLength: 50 }),
  suffix: t.Optional(t.String({ maxLength: 10 })),

  regionCode: t.String({ minLength: 1 }),
  regionName: t.String({ minLength: 1 }),
  provinceCode: t.String({ minLength: 1 }),
  provinceName: t.String({ minLength: 1 }),
  cityCode: t.String({ minLength: 1 }),
  cityName: t.String({ minLength: 1 }),
  barangayCode: t.String({ minLength: 1 }),
  barangayName: t.String({ minLength: 1 }),
  streetName: t.Optional(t.String({ maxLength: 155 })),

  contact: t.String({ minLength: 11, maxLength: 11, pattern: "^[0-9]{11}$" }),
  email: t.Optional(t.String({ maxLength: 50 })),
  message: t.String({ minLength: 1, maxLength: 500 }),

  // Google reCAPTCHA v2 checkbox token, verified server-side before sending.
  recaptchaToken: t.String({ minLength: 1 }),

  // attachments: photos / PDFs of the complaint, sent as multipart form
  // fields. Individual type is restricted here; the *combined* 5MB size
  // cap is enforced in the handler below since Elysia's t.File maxSize
  // option only limits a single file, not the sum of several.
  attachments: t.Optional(
    t.Files({
      type: ["image/jpeg", "image/png", "image/webp", "application/pdf"],
    })
  ),
});

// Combined size cap for all attachments on a single submission.
const MAX_TOTAL_ATTACHMENT_BYTES = 5 * 1024 * 1024; // 5MB

// ---- Throttling --------------------------------------------------------
// 3 submissions per IP per rolling hour. Backed by a Supabase table so the
// limit holds even across multiple server instances/deploys.
//
// Run this once in Supabase SQL editor:
//
//   create table epacd_rate_limit (
//     id uuid primary key default gen_random_uuid(),
//     ip_address text not null,
//     created_at timestamptz not null default now()
//   );
//   create index epacd_rate_limit_ip_created_idx
//     on epacd_rate_limit (ip_address, created_at);
//
// This route uses the anon-key `supabase` client (public user), so RLS
// must explicitly allow it to insert and select on this table, e.g.:
//
//   alter table epacd_rate_limit enable row level security;
//   create policy "epacd anon insert" on epacd_rate_limit
//     for insert to anon with check (true);
//   create policy "epacd anon select" on epacd_rate_limit
//     for select to anon using (true);
//
// Optionally add a cron/scheduled job to prune rows older than a day or two
// so the table doesn't grow unbounded.
const RATE_LIMIT_MAX_REQUESTS = 3;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour

function getClientIp(headers: Record<string, string | undefined>): string {
  // Behind a proxy/load balancer (Vercel, nginx, etc.) the real client IP
  // is the first entry in X-Forwarded-For. Fall back to X-Real-IP, then
  // "unknown" so a missing header never crashes the handler (it just won't
  // be throttled correctly in that edge case).
  const forwardedFor = headers["x-forwarded-for"];
  if (forwardedFor) {
    return forwardedFor.split(",")[0].trim();
  }
  return headers["x-real-ip"] ?? "unknown";
}

async function isRateLimited(ip: string): Promise<boolean> {
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString();

  const { count, error } = await supabase
    .from("epacd_rate_limit")
    .select("id", { count: "exact", head: true })
    .eq("ip_address", ip)
    .gte("created_at", windowStart);

  if (error) {
    // Fail open on infra errors rather than blocking legitimate submitters,
    // but log loudly so it gets noticed.
    console.error("EPACD rate limit check failed:", error);
    return false;
  }

  return (count ?? 0) >= RATE_LIMIT_MAX_REQUESTS;
}

async function recordSubmission(ip: string): Promise<void> {
  const { error } = await supabase
    .from("epacd_rate_limit")
    .insert({ ip_address: ip });
  if (error) {
    console.error("EPACD rate limit record failed:", error);
  }
}


// Configure via environment variables. Example for Gmail SMTP:
// SMTP_HOST=smtp.gmail.com
// SMTP_PORT=465
// SMTP_SECURE=true
// SMTP_USER=your-sending-address@gmail.com
// SMTP_PASS=app-password  (use a Gmail App Password, not the account password)
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT ?? 465),
  secure: process.env.SMTP_SECURE !== "false",
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function buildFullName(
  givenName: string,
  middleName: string | undefined,
  surname: string,
  suffix: string | undefined
) {
  const parts = [givenName, middleName, surname, suffix].filter(
    (p) => p && p.trim().length > 0
  );
  return parts.join(" ");
}

function buildFullAddress(fields: {
  streetName?: string;
  barangayName: string;
  cityName: string;
  provinceName: string;
  regionName: string;
}) {
  const parts = [
    fields.streetName,
    fields.barangayName,
    fields.cityName,
    fields.provinceName,
    fields.regionName,
  ].filter((p) => p && p.trim().length > 0);
  return parts.join(", ");
}

export const epacdRoutes = new Elysia({ prefix: "/epacd" }).post(
  "/",
  async ({ body, set, headers }) => {
    const clientIp = getClientIp(headers);

    // ---- Throttle: 3 submissions / hour / IP ----
    if (await isRateLimited(clientIp)) {
      set.status = 429;
      return {
        success: false,
        message:
          "You've reached the submission limit. Please try again in a bit.",
      };
    }

    // Count this as a submission attempt now, before CAPTCHA/processing —
    // otherwise someone could hammer CAPTCHA verification indefinitely
    // without ever tripping the throttle.
    await recordSubmission(clientIp);

    const {
      givenName,
      middleName,
      surname,
      suffix,
      regionName,
      provinceName,
      cityName,
      barangayName,
      streetName,
      contact,
      email,
      message,
      attachments,
      recaptchaToken,
    } = body;

    // ---- CAPTCHA ----
    const captchaOk = await verifyRecaptcha(recaptchaToken, clientIp);
    if (!captchaOk) {
      set.status = 400;
      return {
        success: false,
        message: "CAPTCHA verification failed. Please try again.",
      };
    }

    // Normalize: Elysia gives a single File when exactly one is uploaded,
    // or an array when multiple are. Treat "no files" as an empty array.
    const files: File[] = attachments
      ? Array.isArray(attachments)
        ? attachments
        : [attachments]
      : [];

    const totalBytes = files.reduce((sum, f) => sum + f.size, 0);
    if (totalBytes > MAX_TOTAL_ATTACHMENT_BYTES) {
      set.status = 400;
      return {
        success: false,
        message: "Attachments must not exceed 5MB in total.",
      };
    }

    const fullName = buildFullName(givenName, middleName, surname, suffix);
    const fullAddress = buildFullAddress({
      streetName,
      barangayName,
      cityName,
      provinceName,
      regionName,
    });

    const html = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background:#047857;padding:20px 24px;border-radius:8px 8px 0 0;">
          <h2 style="color:#ffffff;margin:0;font-size:18px;">
            EPACD Submission — City Government of San Pablo
          </h2>
        </div>
        <div style="border:1px solid #e5e7eb;border-top:none;padding:24px;border-radius:0 0 8px 8px;">
          <table style="width:100%;border-collapse:collapse;font-size:14px;color:#111827;">
            <tr>
              <td style="padding:8px 0;font-weight:600;width:120px;vertical-align:top;">Name</td>
              <td style="padding:8px 0;">${escapeHtml(fullName)}</td>
            </tr>
            <tr>
              <td style="padding:8px 0;font-weight:600;vertical-align:top;">Address</td>
              <td style="padding:8px 0;">${escapeHtml(fullAddress)}</td>
            </tr>
            <tr>
              <td style="padding:8px 0;font-weight:600;vertical-align:top;">Contact No.</td>
              <td style="padding:8px 0;">${escapeHtml(contact)}</td>
            </tr>
            <tr>
              <td style="padding:8px 0;font-weight:600;vertical-align:top;">Email</td>
              <td style="padding:8px 0;">${email ? escapeHtml(email) : "—"}</td>
            </tr>
          </table>
          <div style="margin-top:16px;">
            <p style="font-weight:600;font-size:14px;color:#111827;margin:0 0 6px;">Mensahe</p>
            <p style="white-space:pre-wrap;font-size:14px;color:#374151;line-height:1.6;margin:0;">${escapeHtml(
              message
            )}</p>
          </div>
        </div>
      </div>
    `;

    try {
      const mailAttachments = await Promise.all(
        files.map(async (file) => ({
          filename: file.name || "attachment",
          content: Buffer.from(await file.arrayBuffer()),
          contentType: file.type || "application/octet-stream",
        }))
      );

      await transporter.sendMail({
        from: process.env.SMTP_USER,
        to: RECIPIENT_EMAIL,
        replyTo: email && email.length > 0 ? email : undefined,
        subject: `EPACD Complaint — ${fullName}`,
        html,
        attachments: mailAttachments,
      });

      return { success: true, message: "Complaint sent successfully." };
    } catch (err) {
      console.error("EPACD email send failed:", err);
      set.status = 500;
      return {
        success: false,
        message: "Failed to send complaint. Please try again later.",
      };
    }
  },
  { body: epacdBody }
);