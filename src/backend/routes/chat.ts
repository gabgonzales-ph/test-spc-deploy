// src/backend/routes/chat.ts

import { Elysia, t } from "elysia";
import { supabase } from "@/backend/config/database";
import { randomBytes } from "crypto";
import { verifyRecaptcha } from "../utils/recaptcha";

const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"];
const DOC_TYPES = ["application/pdf"];
const ALLOWED_ATTACHMENT_TYPES = [...IMAGE_TYPES, ...DOC_TYPES];
const MAX_ATTACHMENT_SIZE = 10 * 1024 * 1024; // 10MB

function sanitizeName(name: string) {
  return name.trim().replace(/[^a-zA-Z0-9]+/g, "-");
}

// ── Help desk session cutoff (5:00 PM Philippine Standard Time, UTC+8, no DST) ──
const CUTOFF_HOUR_PH = 17;

function isAfterCutoffPH(): boolean {
  const now = new Date();
  const phHour = (now.getUTCHours() + 8) % 24;
  return phHour >= CUTOFF_HOUR_PH;
}

// Closes a conversation server-side the moment it's touched after cutoff.
// Returns the effective status to use for the rest of the request.
async function enforceCutoff(conversationId: number, currentStatus: string): Promise<string> {
  if (currentStatus === "closed") return "closed";
  if (!isAfterCutoffPH()) return currentStatus;

  await supabase
    .from("conversations")
    .update({ status: "closed" })
    .eq("id", conversationId);

  return "closed";
}

export const chatRoutes = new Elysia({ prefix: "/chat" })

  .post("/conversations", async ({ body, request, set }) => {
    const { full_name, email, phone, subject, message, source_node } = body;

    const forwardedFor =
      request.headers.get("x-forwarded-for") ??
      request.headers.get("x-real-ip");
    const ip_address = forwardedFor ? forwardedFor.split(",")[0].trim() : null;

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
        full_name:     full_name.trim(),
        email:         email?.trim()       || null,
        phone:         phone?.trim()       || null,
        subject:       subject.trim(),
        message:       message.trim(),
        source_node:   source_node?.trim() || null,
        ip_address,
        status:        isAfterCutoffPH() ? "closed" : "open",
        visitor_token,
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
      });

    if (msgError) {
      set.status = 500;
      return { success: false, error: msgError.message };
    }

    // Return token to client — stored in sessionStorage
    return {
      success:         true,
      conversation_id: conversation.id,
      visitor_token,
      status:          conversation.status,
    };
  }, {
    body: t.Object({
      full_name:   t.String({ minLength: 1 }),
      email:       t.Optional(t.String()),
      phone:       t.Optional(t.String()),
      subject:     t.String({ minLength: 1 }),
      message:     t.String({ minLength: 1 }),
      source_node: t.Optional(t.String()),
      recaptchaToken: t.String({ minLength: 1 }),

    }),
  })

  // Visitor follow-up — requires visitor_token
  .post("/conversations/:id/messages", async ({ params, body, set }) => {
    const conversationId = parseInt(params.id);

    const { data: conversation, error: fetchError } = await supabase
      .from("conversations")
      .select("id, status, visitor_token")
      .eq("id", conversationId)
      .single();

    if (fetchError || !conversation) {
      set.status = 404;
      return { success: false, error: "Conversation not found" };
    }

    // Verify ownership
    if (conversation.visitor_token !== body.visitor_token) {
      set.status = 403;
      return { success: false, error: "Unauthorized" };
    }

    const status = await enforceCutoff(conversation.id, conversation.status);
    if (status === "closed") {
      set.status = 400;
      return {
        success: false,
        error:   "Chat support hours have ended for today (after 5:00 PM). Please start a new chat tomorrow.",
        closed:  true,
      };
    }

    const { error } = await supabase
      .from("chat_messages")
      .insert({
        conversation_id: conversationId,
        sender_type:     "visitor",
        sender_id:       null,
        content:         body.content.trim(),
        is_read:         false,
      });

    if (error) {
      set.status = 500;
      return { success: false, error: error.message };
    }

    return { success: true };
  }, {
    params: t.Object({ id: t.String() }),
    body:   t.Object({
      content:       t.String({ minLength: 1 }),
      visitor_token: t.String(),
    }),
  })

  // Visitor attachment upload — requires visitor_token, same ownership rules as /messages
  .post("/conversations/:id/upload", async ({ params, body, set }) => {
    const conversationId = parseInt(params.id);
    const { file, visitor_token, content } = body;

    const { data: conversation, error: fetchError } = await supabase
      .from("conversations")
      .select("id, status, visitor_token, full_name")
      .eq("id", conversationId)
      .single();

    if (fetchError || !conversation) {
      set.status = 404;
      return { success: false, error: "Conversation not found" };
    }

    if (conversation.visitor_token !== visitor_token) {
      set.status = 403;
      return { success: false, error: "Unauthorized" };
    }

    const status = await enforceCutoff(conversation.id, conversation.status);
    if (status === "closed") {
      set.status = 400;
      return {
        success: false,
        error:   "Chat support hours have ended for today (after 5:00 PM). Please start a new chat tomorrow.",
        closed:  true,
      };
    }

    if (!ALLOWED_ATTACHMENT_TYPES.includes(file.type)) {
      set.status = 415;
      return { success: false, error: "Unsupported file type. Only JPG, PNG, WEBP, and PDF are allowed." };
    }

    if (file.size > MAX_ATTACHMENT_SIZE) {
      set.status = 413;
      return { success: false, error: "File exceeds the 10MB size limit." };
    }

    const isImage = IMAGE_TYPES.includes(file.type);
    const label = isImage ? "image" : "file";

    const ext = file.name.split(".").pop();
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
      file:          t.File(),
      visitor_token: t.String(),
      content:       t.Optional(t.String()),
    }),
  })

  // Message history — requires visitor_token
  .get("/conversations/:id/messages", async ({ params, query, set }) => {
    const convId = parseInt(params.id);
    const token  = query.token as string | undefined;

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

    if (conversation.visitor_token !== token) {
      set.status = 403;
      return { success: false, error: "Unauthorized" };
    }

    const status = await enforceCutoff(conversation.id, conversation.status);

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