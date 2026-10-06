// src/backend/routes/chat.ts

import { Elysia, t } from "elysia";
import { supabaseAdmin as supabase } from "@/backend/config/database";
import { randomBytes, timingSafeEqual } from "crypto";
import { isIP } from "node:net";
import { verifyRecaptcha } from "../utils/recaptcha";

// ── Attachments ───────────────────────────────────────────────────────────
const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"];
const DOC_TYPES = ["application/pdf"];
const ALLOWED_ATTACHMENT_TYPES = [...IMAGE_TYPES, ...DOC_TYPES];
const MAX_ATTACHMENT_SIZE = 10 * 1024 * 1024; // 10MB
const EXT_BY_MIME: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "application/pdf": "pdf",
};

// ── Help desk hours & limits (Philippine Standard Time, UTC+8, no DST) ────
// Operating hours: Mon–Fri 8:00 AM – 5:00 PM. Everything else is "after hours".
// The help desk always accepts messages; after hours the visitor must
// acknowledge the notice first. Conversations are closed by the nightly job.
const PH_OFFSET_MS = 8 * 3_600_000;
const OPEN_HOUR = 8;
const CLOSE_HOUR = 17;
const LIMIT_OPEN = 100;   // visitor messages per PH day, during operating hours
const LIMIT_AFTER = 25;   // visitor messages per PH day, after hours
const BURST_MS = 3_000;   // minimum gap between visitor messages (client window is 4s)
const MAX_NEW_CONV_PER_IP = 5; // new conversations per IP per PH day

function sanitizeName(name: string) {
  return name.trim().replace(/[^a-zA-Z0-9]+/g, "-");
}

function parseId(raw: string): number | null {
  const n = Number(raw);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function tokenMatches(stored: string | null, provided: string): boolean {
  if (!stored) return false;
  const a = Buffer.from(stored);
  const b = Buffer.from(provided);
  return a.length === b.length && timingSafeEqual(a, b);
}

// UTC instant of 00:00 PHT for the PH day containing `now`
function phMidnightUtc(now: Date): Date {
  const ph = new Date(now.getTime() + PH_OFFSET_MS);
  ph.setUTCHours(0, 0, 0, 0);
  return new Date(ph.getTime() - PH_OFFSET_MS);
}

function phParts(d: Date) {
  const ph = new Date(d.getTime() + PH_OFFSET_MS);
  return { dow: ph.getUTCDay(), hour: ph.getUTCHours() };
}

const isWorkday = (d: Date) => {
  const { dow } = phParts(d);
  return dow >= 1 && dow <= 5; // Mon–Fri
};

function getHelpdeskState(now = new Date()) {
  const { hour } = phParts(now);
  let open = isWorkday(now) && hour >= OPEN_HOUR && hour < CLOSE_HOUR;

  // Testing only — set HELPDESK_FORCE in local/preview env, never in production.
  if (process.env.HELPDESK_FORCE === "open")   open = true;
  if (process.env.HELPDESK_FORCE === "closed") open = false;

  let nextOpenAt: string | null = null;
  if (!open) {
    for (let i = 0; i < 8; i++) {
      const openTime = new Date(
        phMidnightUtc(now).getTime() + i * 86_400_000 + OPEN_HOUR * 3_600_000,
      );
      if (openTime > now && isWorkday(openTime)) {
        nextOpenAt = openTime.toISOString();
        break;
      }
    }
  }
  return { open, nextOpenAt };
}

// Single gate for visitor follow-ups and uploads:
// closed check → after-hours acknowledgement → burst check → daily cap.
async function gateVisitorSend(
  conv: { id: number; status: string; after_hours_ack_at: string | null },
  ack?: boolean,
) {
  const now = new Date();

  if (conv.status === "closed") {
    return {
      ok: false as const,
      status: 400,
      body: {
        success: false,
        closed: true,
        error: "This chat has been closed. Please start a new chat.",
      },
    };
  }

  const { open } = getHelpdeskState(now);
  const afterHours = !open;
  const dayStart = phMidnightUtc(now);

  if (afterHours) {
    const acked =
      !!conv.after_hours_ack_at && new Date(conv.after_hours_ack_at) >= dayStart;
    if (!acked && !ack) {
      return {
        ok: false as const,
        status: 428,
        body: {
          success: false,
          needsAck: true,
          error: "Please acknowledge the after-hours notice first.",
        },
      };
    }
    if (!acked) {
      await supabase
        .from("conversations")
        .update({ after_hours_ack_at: now.toISOString() })
        .eq("id", conv.id);
    }
  }

  // Burst check. The response is flagged `burst` so the widget can retry
  // silently instead of showing an error to the visitor.
  const { data: last } = await supabase
    .from("chat_messages")
    .select("created_at")
    .eq("conversation_id", conv.id)
    .eq("sender_type", "visitor")
    .order("created_at", { ascending: false })
    .limit(1);

  if (last?.[0]) {
    const elapsed = now.getTime() - new Date(last[0].created_at).getTime();
    if (elapsed < BURST_MS) {
      return {
        ok: false as const,
        status: 429,
        body: {
          success: false,
          burst: true,
          retryAfterMs: BURST_MS - elapsed,
          error: "Too many messages at once.", // not shown to the visitor
        },
      };
    }
  }

  const { count } = await supabase
    .from("chat_messages")
    .select("id", { count: "exact", head: true })
    .eq("conversation_id", conv.id)
    .eq("sender_type", "visitor")
    .eq("after_hours", afterHours)
    .gte("created_at", dayStart.toISOString());

  if ((count ?? 0) >= (afterHours ? LIMIT_AFTER : LIMIT_OPEN)) {
    return {
      ok: false as const,
      status: 429,
      body: {
        success: false,
        limitReached: true,
        error: "Daily message limit reached. Please try again tomorrow.",
      },
    };
  }

  return { ok: true as const, afterHours };
}

export const chatRoutes = new Elysia({ prefix: "/chat" })

  // Help desk status — the widget uses this for the after-hours notice
  .get("/status", async () => {
    const s = getHelpdeskState();
    return { success: true, open: s.open, nextOpenAt: s.nextOpenAt };
  })

  // Start a conversation
  .post("/conversations", async ({ body, request, set }) => {
    const { full_name, email, phone, subject, message, source_node } = body;

    const forwardedFor =
      request.headers.get("x-forwarded-for") ??
      request.headers.get("x-real-ip");
    const rawIp = forwardedFor ? forwardedFor.split(",")[0].trim() : null;
    const ip_address = rawIp && isIP(rawIp) ? rawIp : null; // column is inet

    const now = new Date();
    const afterHours = !getHelpdeskState(now).open;

    // ── Cheap checks FIRST ────────────────────────────────────────────────
    // reCAPTCHA tokens are single-use. Every check that can reject the
    // request must run before verifyRecaptcha, otherwise a rejected request
    // burns the token and the widget has to show the captcha again.

    // 1. Per-IP daily cap on new conversations
    if (ip_address) {
      const { count } = await supabase
        .from("conversations")
        .select("id", { count: "exact", head: true })
        .eq("ip_address", ip_address)
        .gte("created_at", phMidnightUtc(now).toISOString());

      if ((count ?? 0) >= MAX_NEW_CONV_PER_IP) {
        set.status = 429;
        return {
          success: false,
          limitReached: true,
          error: "Too many chats started today. Please try again tomorrow.",
        };
      }
    }

    // 2. After-hours acknowledgement
    if (afterHours && !body.ack_after_hours) {
      set.status = 428;
      return {
        success: false,
        needsAck: true,
        error: "Please acknowledge the after-hours notice first.",
      };
    }

    // ── Captcha (consumes the token) ──────────────────────────────────────
    const captchaOk = await verifyRecaptcha(body.recaptchaToken, ip_address ?? "unknown");
    if (!captchaOk) {
      set.status = 400;
      return { success: false, error: "CAPTCHA verification failed. Please try again." };
    }

    // Generate a secure ownership token
    const visitor_token = randomBytes(32).toString("hex");

    const { data: conversation, error: convError } = await supabase
      .from("conversations")
      .insert({
        full_name:          full_name.trim(),
        email:              email?.trim() || null,
        phone:              phone?.trim() || null,
        subject:            subject.trim(),
        message:            message.trim(),
        source_node:        source_node?.trim() || null,
        ip_address,
        status:             "open",
        visitor_token,
        after_hours_ack_at: afterHours ? now.toISOString() : null,
      })
      .select("id, status")
      .single();

    if (convError || !conversation) {
      set.status = 500;
      return { success: false, error: convError?.message ?? "Failed to create conversation" };
    }

    const { error: msgError } = await supabase
      .from("chat_messages")
      .insert({
        conversation_id: conversation.id,
        sender_type:     "visitor",
        sender_id:       null,
        content:         message.trim(),
        is_read:         false,
        after_hours:     afterHours,
      });

    if (msgError) {
      set.status = 500;
      return { success: false, error: msgError.message };
    }

    // Return token to client — stored client-side
    return {
      success:         true,
      conversation_id: conversation.id,
      visitor_token,
      status:          conversation.status,
      after_hours:     afterHours,
    };
  }, {
    body: t.Object({
      full_name:        t.String({ minLength: 1, maxLength: 100 }),
      email:            t.Optional(t.String({ maxLength: 254 })),
      phone:            t.Optional(t.String({ maxLength: 30 })),
      subject:          t.String({ minLength: 1, maxLength: 200 }),
      message:          t.String({ minLength: 1, maxLength: 1000 }),
      source_node:      t.Optional(t.String({ maxLength: 100 })),
      recaptchaToken:   t.String({ minLength: 1 }),
      ack_after_hours:  t.Optional(t.Boolean()),
    }),
  })

  // Visitor follow-up — requires visitor_token
  .post("/conversations/:id/messages", async ({ params, body, set }) => {
    const conversationId = parseId(params.id);
    if (conversationId === null) {
      set.status = 404;
      return { success: false, error: "Conversation not found" };
    }

    const { data: conversation, error: fetchError } = await supabase
      .from("conversations")
      .select("id, status, visitor_token, after_hours_ack_at")
      .eq("id", conversationId)
      .single();

    if (fetchError || !conversation) {
      set.status = 404;
      return { success: false, error: "Conversation not found" };
    }

    // Verify ownership
    if (!tokenMatches(conversation.visitor_token, body.visitor_token)) {
      set.status = 403;
      return { success: false, error: "Unauthorized" };
    }

    const gate = await gateVisitorSend(conversation, body.ack_after_hours);
    if (!gate.ok) {
      set.status = gate.status;
      return gate.body;
    }

    const { error } = await supabase
      .from("chat_messages")
      .insert({
        conversation_id: conversationId,
        sender_type:     "visitor",
        sender_id:       null,
        content:         body.content.trim(),
        is_read:         false,
        after_hours:     gate.afterHours,
      });

    if (error) {
      set.status = 500;
      return { success: false, error: error.message };
    }

    return { success: true, after_hours: gate.afterHours };
  }, {
    params: t.Object({ id: t.String() }),
    body:   t.Object({
      content:         t.String({ minLength: 1, maxLength: 1000 }),
      visitor_token:   t.String(),
      ack_after_hours: t.Optional(t.Boolean()),
    }),
  })

  // Visitor attachment upload — requires visitor_token, same rules as /messages
  .post("/conversations/:id/upload", async ({ params, body, set }) => {
    const conversationId = parseId(params.id);
    if (conversationId === null) {
      set.status = 404;
      return { success: false, error: "Conversation not found" };
    }

    const { file, visitor_token, content } = body;
    const ack = body.ack_after_hours === "true"; // multipart fields arrive as strings

    const { data: conversation, error: fetchError } = await supabase
      .from("conversations")
      .select("id, status, visitor_token, full_name, after_hours_ack_at")
      .eq("id", conversationId)
      .single();

    if (fetchError || !conversation) {
      set.status = 404;
      return { success: false, error: "Conversation not found" };
    }

    if (!tokenMatches(conversation.visitor_token, visitor_token)) {
      set.status = 403;
      return { success: false, error: "Unauthorized" };
    }

    // Cheap validation first, before the gate does any writes
    if (!ALLOWED_ATTACHMENT_TYPES.includes(file.type)) {
      set.status = 415;
      return { success: false, error: "Unsupported file type. Only JPG, PNG, WEBP, and PDF are allowed." };
    }

    if (file.size > MAX_ATTACHMENT_SIZE) {
      set.status = 413;
      return { success: false, error: "File exceeds the 10MB size limit." };
    }

    const gate = await gateVisitorSend(conversation, ack);
    if (!gate.ok) {
      set.status = gate.status;
      return gate.body;
    }

    const isImage = IMAGE_TYPES.includes(file.type);
    const label = isImage ? "image" : "file";

    const ext = EXT_BY_MIME[file.type]; // derived from validated MIME, not the filename
    const timestamp = Date.now();
    const safeName = sanitizeName(conversation.full_name);
    const filename = `${safeName}_${label}_${timestamp}.${ext}`;
    const path = `${conversationId}/${filename}`;

    const { error: uploadError } = await supabase.storage
      .from("chat_attachments")
      .upload(path, file, { contentType: file.type });

    if (uploadError) {
      set.status = 500;
      return { success: false, error: "Upload failed." };
    }

    const { data: publicUrlData } = supabase.storage
      .from("chat_attachments")
      .getPublicUrl(path);

    const { error: msgError } = await supabase
      .from("chat_messages")
      .insert({
        conversation_id:  conversationId,
        sender_type:      "visitor",
        sender_id:        null,
        content:          content?.trim() || "",
        is_read:          false,
        after_hours:      gate.afterHours,
        attachment_url:   publicUrlData.publicUrl,
        attachment_type:  file.type,
        attachment_size:  file.size,
      });

    if (msgError) {
      set.status = 500;
      return { success: false, error: msgError.message };
    }

    return {
      success: true,
      data: {
        attachment_url:  publicUrlData.publicUrl,
        attachment_type: file.type,
        attachment_size: file.size,
      },
    };
  }, {
    params: t.Object({ id: t.String() }),
    body:   t.Object({
      file:            t.File(),
      visitor_token:   t.String(),
      content:         t.Optional(t.String({ maxLength: 1000 })),
      ack_after_hours: t.Optional(t.String()),
    }),
  })

  // Message history — requires visitor_token
  .get("/conversations/:id/messages", async ({ params, query, set }) => {
    const convId = parseId(params.id);
    const token  = query.token as string | undefined;

    if (convId === null) {
      set.status = 404;
      return { success: false, error: "Conversation not found" };
    }

    if (!token) {
      set.status = 403;
      return { success: false, error: "Unauthorized" };
    }

    const { data: conversation, error: fetchError } = await supabase
      .from("conversations")
      .select("id, status, visitor_token")
      .eq("id", convId)
      .single();

    if (fetchError || !conversation) {
      set.status = 404;
      return { success: false, error: "Conversation not found" };
    }

    if (!tokenMatches(conversation.visitor_token, token)) {
      set.status = 403;
      return { success: false, error: "Unauthorized" };
    }

    // Closing is handled by agents, the nightly job and the 3-day rule,
    // so the stored status is the truth.
    const status = conversation.status;

    const { data, error } = await supabase
      .from("chat_messages")
      .select("id, sender_type, content, created_at, attachment_url, attachment_type, attachment_size")
      .eq("conversation_id", convId)
      .order("created_at", { ascending: true });

    if (error) {
      set.status = 500;
      return { success: false, error: error.message };
    }

    return { success: true, status, data: data ?? [] };
  }, {
    params: t.Object({ id: t.String() }),
    query:  t.Object({ token: t.Optional(t.String()) }),
  });