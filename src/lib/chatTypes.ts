// ─────────────────────────────────────────────
// chatTypes.ts — Core types & state schema
// ─────────────────────────────────────────────

export interface UserInfo {
  fullName: string;
  email: string;
  phone: string;
}

export type ChatStage = "form" | "chat" | "ended";

export type MessageRole = "user" | "bot";

export interface QuickReply {
  label: string;
  value: string; // node key or keyword to navigate to
}

export interface ChatMessage {
  id: string;
  role: MessageRole;
  text: string;
  timestamp: Date;
  quickReplies?: QuickReply[]; // only on bot messages
  delivered?: boolean; // ← add this
  attachmentUrl?: string; // URL of an uploaded file/image attached to this message
  attachmentType?: string; // MIME type of the attachment (e.g. "image/png")
  attachmentSize?: number; // Size of the attachment in bytes
}

// Navigation history entry
export interface HistoryEntry {
  nodeKey: string;
}

// CMS-fetched content cache
export interface CMSContent {
  services: Record<string, CMSService>;   // keyed by slug
  faqs: Record<string, CMSFaq>;           // keyed by faq_id (string)
  loaded: boolean;
  error: string | null;
}

export interface CMSService {
  service_id: number;
  name: string;
  slug: string;
  description: string | null;
  requirements: string | null;
  fees: string | null;
  processing_time: string | null;
  online_application_url: string | null;
}

export interface CMSFaq {
  faq_id: number;
  question: string;
  answer: string;
  service_id: number | null;
  category_id: number | null;
}

// Sumbong / Feedback form payload
export interface ComplaintPayload {
  name:         string;
  email:        string | null;
  phone?:       string | null;
  subject:      string;
  message:      string;
  source_node?: string | null;
  ip_address?:  string | null;
  recaptchaToken:  string;   // ← new, required
}

export function generateId(): string {
  return Math.random().toString(36).slice(2, 9);
}

export function formatTime(date: Date): string {
  return date.toLocaleTimeString("en-PH", {
    hour: "2-digit",
    minute: "2-digit",
  });
}