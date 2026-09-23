// ─────────────────────────────────────────────
// chatEngine.ts — Dynamic flow engine
// ─────────────────────────────────────────────


//spc-website\src\lib\chatEngine.ts
import {
  STATIC_FLOW_NODES,
  KEYWORD_MAP,
  MAIN_MENU_KEY,
  FlowNode,
} from "./flowData";
import { CMSContent, CMSFaq, CMSService, ComplaintPayload } from "./chatTypes";

// ── Dynamic node registry (built from CMS) ────────────────────────────────
// Merged with STATIC_FLOW_NODES at runtime

let DYNAMIC_NODES: Record<string, FlowNode> = {};

// ── Build dynamic nodes from CMS data ────────────────────────────────────

export function buildDynamicNodes(cms: CMSContent): void {
  const newNodes: Record<string, FlowNode> = {};

  const serviceOptions: FlowNode["options"] = [];

  for (const svc of Object.values(cms.services)) {
    const nodeKey = `service-${svc.slug}`;
    const lines: string[] = [`📋 *${svc.name}*`];
    if (svc.description)            lines.push(`\n${svc.description}`);
    if (svc.requirements)           lines.push(`\n📌 Mga Kinakailangan:\n${svc.requirements}`);
    if (svc.fees)                   lines.push(`\n💰 Bayad: ${svc.fees}`);
    if (svc.processing_time)        lines.push(`\n⏱ Oras ng Proseso: ${svc.processing_time}`);
    if (svc.online_application_url) lines.push(`\n🔗 Link:\n${svc.online_application_url}`);

    newNodes[nodeKey] = {
      key: nodeKey,
      message: lines.join(""),
      options: [],
      inputMode: null,
      isTerminal: true,
    };

    serviceOptions.push({ label: svc.name, value: nodeKey });
    // ← no "Iba Pa" appended here anymore
  }

  newNodes["serbisyo"] = {
    ...STATIC_FLOW_NODES["serbisyo"],
    options: serviceOptions,
  };

  const faqOptions: FlowNode["options"] = [];

  for (const faq of Object.values(cms.faqs)) {
    const nodeKey = `faq-${faq.faq_id}`;
    newNodes[nodeKey] = {
      key: nodeKey,
      message: `❓ *${faq.question}*\n\n${faq.answer}`,
      options: [],
      inputMode: null,
      isTerminal: true,
    };
    faqOptions.push({ label: faq.question, value: nodeKey });
  }

  newNodes["tanong"] = {
    ...STATIC_FLOW_NODES["tanong"],
    options: faqOptions,
  };

  DYNAMIC_NODES = newNodes;
}

// ── Unified node lookup ───────────────────────────────────────────────────

function getAllNodes(): Record<string, FlowNode> {
  return { ...STATIC_FLOW_NODES, ...DYNAMIC_NODES };
}

export function getNode(key: string): FlowNode {
  const all = getAllNodes();
  return all[key] ?? all[MAIN_MENU_KEY];
}

export function getMainMenuNode(): FlowNode {
  return getAllNodes()[MAIN_MENU_KEY];
}

// ── Keyword resolution ────────────────────────────────────────────────────

export function resolveNodeByKeyword(input: string): FlowNode | null {
  const normalized = input.toLowerCase().trim();
  const all = getAllNodes();

  if (KEYWORD_MAP[normalized]) return all[KEYWORD_MAP[normalized]] ?? null;

  for (const [kw, nodeKey] of Object.entries(KEYWORD_MAP)) {
    if (normalized.includes(kw)) return all[nodeKey] ?? null;
  }

  // Also try matching against FAQ questions and service names dynamically
  for (const node of Object.values(DYNAMIC_NODES)) {
    if (node.key.startsWith("faq-") || node.key.startsWith("service-")) {
      const label = node.message.split("\n")[0].replace(/[*❓📋]/g, "").trim().toLowerCase();
      if (normalized.includes(label) || label.includes(normalized)) return node;
    }
  }

  return null;
}

// ── Small talk ────────────────────────────────────────────────────────────

const GREETINGS = ["hi", "hello", "hey", "kumusta", "musta", "good morning", "good afternoon", "good evening"];
const THANKS    = ["thank", "thanks", "thank you", "salamat", "ok", "okay", "noted"];

export function getSmallTalkResponse(input: string): string | null {
  const n = input.toLowerCase();
  if (GREETINGS.some((g) => n.includes(g))) return "Magandang araw! 😊 Piliin ang iyong kailangan sa ibaba.";
  if (THANKS.some((t) => n.includes(t)))    return "Walang anuman! May iba pa ba akong maitutulong? 😊";
  return null;
}

// ── injectContent — kept for backwards compat but no longer needed ────────
// Dynamic nodes have their content baked in at build time.

export function injectContent(template: string, _cms: CMSContent): string {
  return template; // content is already resolved in buildDynamicNodes()
}

// ── Feedback ──────────────────────────────────────────────────────────────

// Only the two functions change — everything else stays the same

export async function submitFeedback(
  payload: ComplaintPayload & { source_node?: string }
): Promise<{ success: boolean; conversation_id?: number; visitor_token?: string; status?: string; error?: string }> {
  try {
    const res = await fetch("/api/chat/conversations", {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        full_name:   payload.name,
        email:       payload.email       ?? null,
        phone:       payload.phone       ?? null,
        subject:     payload.subject,
        message:     payload.message,
        source_node: payload.source_node ?? null,
        recaptchaToken: payload.recaptchaToken,   // ← new
      }),
    });
    const data = await res.json();
    if (!res.ok || !data.success) {
      return { success: false, error: data?.error ?? "Hindi natanggap ang mensahe." };
    }
    return {
      success:        true,
      conversation_id: data.conversation_id,
      visitor_token:  data.visitor_token,
      status:         data.status,
    };
  } catch {
    return { success: false, error: "Network error. Subukan ulit." };
  }
}

export async function sendFollowUp(
  conversationId: number,
  content: string,
  visitorToken: string,
): Promise<{ success: boolean; closed?: boolean; error?: string }> {
  try {
    const res = await fetch(`/api/chat/conversations/${conversationId}/messages`, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content, visitor_token: visitorToken }),
    });
    const data = await res.json();
    if (!res.ok || !data.success) {
      return { success: false, closed: data?.closed, error: data?.error ?? "Hindi natanggap ang mensahe." };
    }
    return { success: true };
  } catch {
    return { success: false, error: "Network error. Subukan ulit." };
  }
}

// ── CMS fetcher ───────────────────────────────────────────────────────────

export async function fetchCMSContent(): Promise<Pick<CMSContent, "services" | "faqs">> {
  const [svcRes, faqRes] = await Promise.allSettled([
    fetch("/api/services").then((r) => r.json()),
    fetch("/api/faqs").then((r) => r.json()),
  ]);

  const services: CMSContent["services"] = {};
  const faqs: CMSContent["faqs"]         = {};

  if (svcRes.status === "fulfilled" && svcRes.value?.success) {
    for (const svc of svcRes.value.data ?? []) {
      services[svc.slug] = svc;
    }
  }

  if (faqRes.status === "fulfilled" && faqRes.value?.success) {
    for (const faq of faqRes.value.data ?? []) {
      faqs[String(faq.faq_id)] = faq;
    }
  }

  return { services, faqs };
}