"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { createClient } from "@supabase/supabase-js";
import { ChatMessage, ChatStage, UserInfo, CMSContent, generateId } from "@/lib/chatTypes";
import {
  buildDynamicNodes, getNode, getMainMenuNode,
  resolveNodeByKeyword, getSmallTalkResponse,
  injectContent, submitFeedback, sendFollowUp, fetchCMSContent,
} from "@/lib/chatEngine";
import { FlowNode, MAIN_MENU_KEY } from "@/lib/flowData";

import { ChatForm }      from "./chat/ChatForm";
import { ChatHeader }    from "./chat/ChatHeader";
import { ChatMessages }  from "./chat/ChatMessages";
import { ChatInputArea } from "./chat/ChatInputArea";
import { ChatEnded }     from "./chat/ChatEnded";
import { PreOpenBubble } from "./chat/ui/PreOpenBubble";
import { JPAvatar }      from "./chat/ui/JPAvatar";
import { HelpdeskCaptchaModal } from "./chat/ui/HelpdeskCaptchaModal";
import { AfterHoursNotice }     from "./chat/ui/AfterHoursNotice";

import { useInputGuard } from "@/hooks/useChatApi";

const CLOSED_MESSAGE =
  "Natapos na ang usapang ito. Maaari kang magsimula ng bagong chat.";

const LIMIT_MESSAGE =
  "Naabot mo na ang limits ng paggamit ng Help Desk. Subukan muli bukas.";

const ACK_KEY   = "jp_ah_ack";     // PH date (YYYY-MM-DD) of the last after-hours acknowledgement
const LIMIT_KEY = "jp_limit_day";  // PH date (YYYY-MM-DD) on which the new-chat limit was hit
const phToday = () => new Date(Date.now() + 8 * 3_600_000).toISOString().slice(0, 10);

function afterHoursReceived(nextOpenAt: string | null) {
  const when = nextOpenAt
    ? new Date(nextOpenAt).toLocaleDateString("en-PH", {
        weekday: "long", month: "long", day: "numeric", timeZone: "Asia/Manila",
      })
    : "susunod na araw ng trabaho";
  return `✅ Natanggap namin ang iyong mensahe. Ngunit bukas lamang ang Help Desk 8AM - 5PM, Mon - Fri. Babalikan namin ang iyong mensahe sa lalong madaling panahon, salamat!`;
}

const NEEDS_ACK_MESSAGE =
  "Pakikumpirma muna ang abiso ng help desk, pagkatapos ay ipadala muli ang mensahe.";

// Shape of the upload endpoint's JSON response
type UploadResult = {
  success?: boolean;
  data?: { attachment_url: string; attachment_type: string; attachment_size?: number };
  closed?: boolean;
  needsAck?: boolean;
  burst?: boolean;
  retryAfterMs?: number;
  error?: string;
};

const supabaseRealtime = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

const SESSION_CONV_KEY   = "jp_conv_id";
const SESSION_TOKEN_KEY  = "jp_visitor_token";
const STAGE_KEY          = "jp_stage";
const USER_KEY           = "jp_user";
const UNREAD_KEY         = "jp_has_unread";

export default function ChatWidget() {

  const [isOpen, setIsOpen]          = useState(false);
  const [bubbleDismissed, setBubble] = useState(false);
  const [stage, setStage]            = useState<ChatStage>("form");

  const [userInfo, setUserInfo]     = useState<UserInfo>({ fullName: "", email: "", phone: "" });
  const [formErrors, setFormErrors] = useState<Partial<UserInfo>>({});

  const [messages, setMessages]      = useState<ChatMessage[]>([]);
  const [isTyping, setIsTyping]      = useState(false);
  const [currentNodeKey, setNodeKey] = useState<string>(MAIN_MENU_KEY);
  const [history, setHistory]        = useState<string[]>([]);
  const [menuOpen, setMenuOpen]      = useState(false);

  const { validate, validateAttachment, sanitizeInput, error: inputError, clearError, cooldownUntil } = useInputGuard();

  const [helpdeskText, setHelpdesk]     = useState("");
  const [formSubmitting, setSubmitting] = useState(false);
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  const [conversationId, setConvId]     = useState<number | null>(null);
  const [visitorToken, setVisitorToken] = useState<string | null>(null);
  const [liveMode, setLiveMode]         = useState(false);
  const [hasUnread, setHasUnread]       = useState(false); // red dot on bubble
  const [convStatus, setConvStatus]     = useState<string | null>(null);
  const [uploading, setUploading]       = useState(false); // attachment upload in progress

  // Help desk hours (server is the authority) + after-hours acknowledgement
  const [hours, setHours]       = useState<{ open: boolean; nextOpenAt: string | null }>({ open: true, nextOpenAt: null });
  const [ackDate, setAckDate]   = useState<string | null>(null);
  const ackToday = ackDate === phToday();

  // New-chat limit (per-IP cap on new conversations). Stored as a PH date so it
  // survives reloads and expires on its own at PH midnight. While set, the
  // captcha modal stays hidden and no creation request is attempted.
  const [limitDate, setLimitDate] = useState<string | null>(null);
  const limitReached = limitDate === phToday();

  const channelRef = useRef<ReturnType<typeof supabaseRealtime.channel> | null>(null);

  const [cms, setCms] = useState<CMSContent>({ services: {}, faqs: {}, loaded: false, error: null });

  // ── Session restore ───────────────────────────────────────────────────

  useEffect(() => {
    try {
      const savedUser  = localStorage.getItem(USER_KEY);
      if (savedUser) setUserInfo(JSON.parse(savedUser) as UserInfo);

      setAckDate(localStorage.getItem(ACK_KEY));
      setLimitDate(localStorage.getItem(LIMIT_KEY));

      const savedConvId = localStorage.getItem(SESSION_CONV_KEY);
      const savedToken  = localStorage.getItem(SESSION_TOKEN_KEY);
      const savedStage  = localStorage.getItem(STAGE_KEY) as ChatStage | null;
      const savedUnread = localStorage.getItem(UNREAD_KEY);

      if (savedUnread === "true") setHasUnread(true);

      if (savedConvId && savedToken && savedStage === "chat") {
        const convId = parseInt(savedConvId);
        setConvId(convId);
        setVisitorToken(savedToken);
        setStage("chat");
        setLiveMode(true);

        fetch(`/api/chat/conversations/${convId}/messages?token=${savedToken}`)
          .then(r => r.json())
          .then(json => {
            // Restore status state here
            if (json.status) {
              setConvStatus(json.status);
            }
            const rows: {
              id: number;
              sender_type: string;
              content: string;
              created_at: string;
              attachment_url?: string | null;
              attachment_type?: string | null;
              attachment_size?: number | null;
            }[] = json?.data ?? [];
            setMessages(rows.map(row => ({
              id:             String(row.id),
              role:           row.sender_type === "agent" ? "bot" : "user",
              text:           row.content,
              timestamp:      new Date(row.created_at),
              attachmentUrl:  row.attachment_url ?? undefined,
              attachmentType: row.attachment_type ?? undefined,
              attachmentSize: row.attachment_size ?? undefined,
            })));
          })
          .catch(() => {
            setMessages([{
              id:        generateId(),
              role:      "bot",
              text:      "Maligayang pagbabalik! Abangan ang tugon ng aming staff.",
              timestamp: new Date(),
            }]);
          });
      }
    } catch {}
  }, []);

  // ── CMS ───────────────────────────────────────────────────────────────

  useEffect(() => {
    fetchCMSContent()
      .then(({ services, faqs }) => {
        const loaded = { services, faqs, loaded: true, error: null };
        setCms(loaded);
        buildDynamicNodes(loaded);
      })
      .catch(() => setCms(p => ({ ...p, loaded: true, error: "CMS unavailable." })));
  }, []);

  // ── Help desk hours ───────────────────────────────────────────────────
  // The server decides whether the help desk is in operating hours
  // (Mon–Fri 8AM–5PM PHT). Outside those hours visitors can still leave
  // messages, but must acknowledge a notice first.

  useEffect(() => {
    if (!isOpen) return;
    let alive = true;
    const load = () =>
      fetch("/api/chat/status")
        .then(r => r.json())
        .then(j => {
          if (alive && j?.success) setHours({ open: j.open, nextOpenAt: j.nextOpenAt });
        })
        .catch(() => {});
    load();
    const id = setInterval(load, 60_000);
    return () => { alive = false; clearInterval(id); };
  }, [isOpen]);

  const clearAck = useCallback(() => {
    setAckDate(null);
    try { localStorage.removeItem(ACK_KEY); } catch {}
  }, []);

  function acknowledgeAfterHours() {
    const d = phToday();
    setAckDate(d);
    try { localStorage.setItem(ACK_KEY, d); } catch {}
  }

  // Remember that the new-chat limit was hit today (expires at PH midnight)
  const markLimitReached = useCallback(() => {
    const d = phToday();
    setLimitDate(d);
    try { localStorage.setItem(LIMIT_KEY, d); } catch {}
  }, []);

  // ── Bubble / open-chat event ──────────────────────────────────────────

  useEffect(() => {
    if (!isOpen && !bubbleDismissed) {
      const t = setTimeout(() => setBubble(true), 6000);
      return () => clearTimeout(t);
    }
  }, [isOpen, bubbleDismissed]);

  useEffect(() => {
    const handler = () => { setIsOpen(true); setBubble(true); };
    window.addEventListener("open-chat", handler);
    return () => window.removeEventListener("open-chat", handler);
  }, []);

  // Clear unread dot when chat is opened
  useEffect(() => {
    if (isOpen && hasUnread) {
      setHasUnread(false);
      try { localStorage.removeItem(UNREAD_KEY); } catch {}
    }
  }, [isOpen, hasUnread]);

  // ── Persist stage ─────────────────────────────────────────────────────

  useEffect(() => {
    try { localStorage.setItem(STAGE_KEY, stage); } catch {}
  }, [stage]);

  // ── Realtime ──────────────────────────────────────────────────────────

  useEffect(() => {
    if (!conversationId) return;
    if (channelRef.current) supabaseRealtime.removeChannel(channelRef.current);

    const channel = supabaseRealtime
      .channel(`conversation-${conversationId}`)
      // Listener 1: Incoming Messages
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "chat_messages" },
        (payload) => {
          const row = payload.new as {
            id: number;
            conversation_id: number;
            sender_type: string;
            content: string;
            created_at: string;
            attachment_url?: string | null;
            attachment_type?: string | null;
            attachment_size?: number | null;
          };

          if (row.conversation_id !== conversationId) return;
          if (row.sender_type !== "agent") return;

          setLiveMode(true);
          setMessages(prev => {
            if (prev.find(m => m.id === String(row.id))) return prev;
            return [...prev, {
              id:             String(row.id),
              role:           "bot" as const,
              text:           row.content,
              timestamp:      new Date(row.created_at),
              attachmentUrl:  row.attachment_url ?? undefined,
              attachmentType: row.attachment_type ?? undefined,
              attachmentSize: row.attachment_size ?? undefined,
            }];
          });

          if (!isOpen) {
            setHasUnread(true);
            try { localStorage.setItem(UNREAD_KEY, "true"); } catch {}
          }
        }
      )
      // Listener 2: Status Updates (Open/Assigned/Closed)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "conversations" },
        (payload) => {
          const row = payload.new as { id: number; status: string };
          if (row.id === conversationId && row.status) {
            setConvStatus(row.status);
          }
        }
      )
      .subscribe();

    channelRef.current = channel;
    return () => { supabaseRealtime.removeChannel(channel); channelRef.current = null; };
  }, [conversationId, isOpen]);

  useEffect(() => {
    return () => { if (channelRef.current) supabaseRealtime.removeChannel(channelRef.current); };
  }, []);

  // ── Message helpers ───────────────────────────────────────────────────

  const pushBotMessage = useCallback((text: string, node?: FlowNode) => {
    setMessages(prev => [...prev, {
      id: generateId(), role: "bot", text, timestamp: new Date(),
      quickReplies: node?.options?.length
        ? node.options.map(o => ({ label: o.label, value: o.value }))
        : undefined,
    }]);
  }, []);

  const pushUserMessage = useCallback((
    text: string,
    attachment?: { url: string; type: string; size?: number }
  ) => {
    setMessages(prev => [...prev, {
      id:             generateId(),
      role:           "user",
      text,
      timestamp:      new Date(),
      attachmentUrl:  attachment?.url,
      attachmentType: attachment?.type,
      attachmentSize: attachment?.size,
    }]);
  }, []);

  const navigateTo = useCallback((nodeKey: string, pushToHistory = true, fromKey?: string) => {
    const node = getNode(nodeKey);
    if (pushToHistory) setHistory(h => [...h, fromKey ?? currentNodeKey]);
    setNodeKey(nodeKey);
    setIsTyping(true);
    setTimeout(() => {
      pushBotMessage(injectContent(node.message, cms), node);
      setIsTyping(false);
    }, 600);
  }, [cms, currentNodeKey, pushBotMessage]);

  // ── Registration ──────────────────────────────────────────────────────

  const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  const PHONE_RE = /^(09|\+639)\d{9}$/;

  function validateForm(): boolean {
    const errors: Partial<UserInfo> = {};
    if (!userInfo.fullName.trim())
      errors.fullName = "Kinakailangan ang buong pangalan.";
    if (!userInfo.email.trim())
      errors.email = "Kinakailangan ang email.";
    else if (!EMAIL_RE.test(userInfo.email.trim()))
      errors.email = "Magbigay ng valid na email.";
    if (!userInfo.phone.trim())
      errors.phone = "Kinakailangan ang numero.";
    else if (!PHONE_RE.test(userInfo.phone.trim().replace(/[-\s]/g, "")))
      errors.phone = "Magbigay ng valid na numero (hal. 09XX-XXX-XXXX).";
    setFormErrors(errors);
    return Object.keys(errors).length === 0;
  }

  // The modal watches this token (via its `verified` prop) and resets its
  // own checkbox internally when it goes back to null — nothing else to do
  // here besides clearing the value.
  function resetCaptcha() {
    setCaptchaToken(null);
  }

  function handleStartChat() {
    if (!validateForm()) return;
    try { localStorage.setItem(USER_KEY, JSON.stringify(userInfo)); } catch {}
    setStage("chat");
    setTimeout(() => {
      const main = getMainMenuNode();
      pushBotMessage(
        `Kamusta, ${userInfo.fullName.split(" ")[0]}! 👋 Welcome sa Opisyal na chatbot ng San Pablo.\n\nI-type o piliin ang iyong kailangan:`,
        main
      );
      setNodeKey(MAIN_MENU_KEY);
    }, 300);
  }

  // ── Navigation ────────────────────────────────────────────────────────

  const handleQuickReply = useCallback((value: string, label: string) => {
    pushUserMessage(label);
    navigateTo(value, true, currentNodeKey);
  }, [currentNodeKey, navigateTo, pushUserMessage]);

  // ── Text send (handles both flow-engine navigation AND Help Desk conversation creation) ──

  const handleTextSend = useCallback((text: string) => {
    const clean = sanitizeInput(text);

    async function doSend(t: string) {
      // Already talking to a human agent — just forward the follow-up.
      // The server enforces closed status, the after-hours acknowledgement,
      // burst limits and the daily caps.
      if (liveMode && conversationId && visitorToken) {
        pushUserMessage(t);

        const trySend = (attempt: number) => {
          sendFollowUp(conversationId, t, visitorToken, ackToday).then(result => {
            // Server burst check: no error text and no bot typing dots. Keep the
            // input spinner on (formSubmitting) and retry once the window clears.
            if (result.burst && attempt < 3) {
              setSubmitting(true);
              setTimeout(() => trySend(attempt + 1), (result.retryAfterMs ?? 3000) + 100);
              return;
            }

            setSubmitting(false);
            if (result.success) return;

            if (result.burst) {
              pushBotMessage("Hindi naipadala ang mensahe. Pakisubukan muli.");
              return;
            }
            if (result.closed) {
              setConvStatus("closed");
              setIsTyping(true);
              setTimeout(() => { pushBotMessage(CLOSED_MESSAGE); setIsTyping(false); }, 400);
              return;
            }
            if (result.needsAck) {
              setHours(h => ({ ...h, open: false }));
              clearAck();
              pushBotMessage(NEEDS_ACK_MESSAGE);
              return;
            }
            setIsTyping(true);
            setTimeout(() => { pushBotMessage(`${result.error}`); setIsTyping(false); }, 400);
          });
        };

        trySend(0);
        clearError();
        return;
      }

      // On the Help Desk node, not live yet — this message creates the conversation.
      if (currentNodeKey === "iba-pa") {
        // New-chat limit already hit today — don't attempt creation.
        if (limitReached) {
          pushUserMessage(t);
          pushBotMessage(LIMIT_MESSAGE);
          return;
        }

        // Belt-and-suspenders: the Send button is already disabled without a
        // token, but this covers the Enter-key path too.
        if (!captchaToken) return;

        setSubmitting(true);
        const msgId = generateId();
        pushUserMessage(t);

        const result = await submitFeedback({
          name:            userInfo.fullName,
          email:           userInfo.email || null,
          phone:           userInfo.phone || null,
          subject:         "Iba Pa",
          message:         t,
          source_node:     currentNodeKey,
          recaptchaToken:  captchaToken,
          ack_after_hours: ackToday,
        });

        setSubmitting(false);

        // The server rejects the new-chat limit BEFORE verifying the captcha,
        // so the token was not spent. Stop here: no captcha reset, and the
        // modal stays hidden because limitReached is now set.
        if (result.limitReached) {
          markLimitReached();
          pushBotMessage(LIMIT_MESSAGE);
          return;
        }

        // A captcha token is single-use — clear it after any attempt that
        // reached verification, whether the submission succeeded or failed.
        resetCaptcha();

        if (result.success && result.conversation_id && result.visitor_token) {
          setConvId(result.conversation_id);
          setVisitorToken(result.visitor_token);
          setLiveMode(true);
          setConvStatus(result.status === "closed" ? "closed" : "open");

          try {
            localStorage.setItem(SESSION_CONV_KEY,  String(result.conversation_id));
            localStorage.setItem(SESSION_TOKEN_KEY, result.visitor_token);
            localStorage.setItem(STAGE_KEY,         "chat");
          } catch {}

          setMessages(prev => prev.map(m => m.id === msgId ? { ...m, delivered: true } : m));

          setTimeout(() => {
            pushBotMessage(
              result.after_hours
                ? afterHoursReceived(hours.nextOpenAt)
                : "✅ Natanggap ang iyong mensahe! Abangan ang tugon ng aming staff. Maaari kang mag-type ng karagdagang tanong habang naghihintay."
            );
          }, 600);

          setNodeKey(MAIN_MENU_KEY);
        } else if (result.needsAck) {
          setHours(h => ({ ...h, open: false }));
          clearAck();
          pushBotMessage(NEEDS_ACK_MESSAGE);
        } else if (!result.success) {
          setIsTyping(true);
          setTimeout(() => { pushBotMessage(`${result.error}`); setIsTyping(false); }, 600);
        }
        return;
      }

      // Everything else — existing flow-engine logic, unchanged.
      pushUserMessage(t);
      const smallTalk = getSmallTalkResponse(t);
      if (smallTalk) {
        setIsTyping(true);
        setTimeout(() => {
          const main = getMainMenuNode();
          pushBotMessage(smallTalk + "\n\n" + injectContent(main.message, cms), main);
          setNodeKey(MAIN_MENU_KEY);
          setIsTyping(false);
        }, 600);
        return;
      }
      const matched = resolveNodeByKeyword(t);
      if (matched) { navigateTo(matched.key, true, currentNodeKey); return; }
      setIsTyping(true);
      setTimeout(() => {
        const main = getMainMenuNode();
        pushBotMessage(
          "Hindi ko maintindihan ang iyong mensahe. Piliin ang isa sa mga pagpipilian:\n\n" +
          injectContent(main.message, cms),
          main
        );
        setNodeKey(MAIN_MENU_KEY);
        setIsTyping(false);
      }, 600);
    }

    if (!validate(clean, doSend)) return;
    doSend(clean);
  }, [cms, currentNodeKey, navigateTo, pushBotMessage, pushUserMessage,
      liveMode, conversationId, visitorToken, validate, sanitizeInput, clearError,
      userInfo, captchaToken, ackToday, hours.nextOpenAt, clearAck,
      limitReached, markLimitReached]);

  // ── Attachment send ───────────────────────────────────────────────────
  // Requires an existing conversation (visitor_token + conversationId), since
  // the upload endpoint is scoped to /chat/conversations/:id/upload.
  // Gated by validateAttachment so it shares the same burst window as a text
  // message — if the window is still open, the actual upload is deferred
  // (doSend) and retried automatically once it clears. The server enforces
  // the closed status, the after-hours acknowledgement and the daily caps;
  // a server-side burst rejection is retried silently while `uploading`
  // keeps the spinner on.

  function handleAttachmentSend(file: File, caption: string) {
    async function doSend() {
      setUploading(true);
      try {
        let convId = conversationId;
        let token  = visitorToken;
        let createdAfterHours = false;

        const fallbackLabel = file.type.startsWith("image/") ? "📷 Photo" : "📎 File";
        const initialMessage = caption || fallbackLabel;

        // No conversation yet — create one first (same as a Help Desk text message would).
        if (!convId || !token) {
          // New-chat limit already hit today — don't attempt creation.
          if (limitReached) {
            pushBotMessage(LIMIT_MESSAGE);
            return;
          }

          if (!captchaToken) {
            setIsTyping(true);
            setTimeout(() => {
              pushBotMessage("Kumpletuhin muna ang CAPTCHA bago magpadala.");
              setIsTyping(false);
            }, 300);
            return;
          }

          const created = await submitFeedback({
            name:            userInfo.fullName,
            email:           userInfo.email || null,
            phone:           userInfo.phone || null,
            subject:         "Iba Pa",
            message:         initialMessage,
            source_node:     currentNodeKey,
            recaptchaToken:  captchaToken,
            ack_after_hours: ackToday,
          });

          // Rejected before captcha verification: token not spent, keep the
          // modal hidden and skip resetCaptcha().
          if (created.limitReached) {
            markLimitReached();
            pushBotMessage(LIMIT_MESSAGE);
            return;
          }

          resetCaptcha();

          if (created.needsAck) {
            setHours(h => ({ ...h, open: false }));
            clearAck();
            pushBotMessage(NEEDS_ACK_MESSAGE);
            return;
          }

          if (!created.success || !created.conversation_id || !created.visitor_token) {
            setIsTyping(true);
            setTimeout(() => { pushBotMessage(`${created.error}`); setIsTyping(false); }, 400);
            return;
          }

          convId = created.conversation_id;
          token  = created.visitor_token;
          createdAfterHours = !!created.after_hours;

          setConvId(convId);
          setVisitorToken(token);
          setLiveMode(true);
          const closedOnArrival = created.status === "closed";
          setConvStatus(closedOnArrival ? "closed" : "open");

          if (closedOnArrival) {
            pushBotMessage(CLOSED_MESSAGE);
            return;
          }

          try {
            localStorage.setItem(SESSION_CONV_KEY,  String(convId));
            localStorage.setItem(SESSION_TOKEN_KEY, token);
            localStorage.setItem(STAGE_KEY,         "chat");
          } catch {}

          setNodeKey(MAIN_MENU_KEY);
        }

        const formData = new FormData();
        formData.append("file", file);
        formData.append("visitor_token", token);
        formData.append("ack_after_hours", ackToday ? "true" : "false");
        // If we just created the conversation, its first message already carries
        // `initialMessage` — don't duplicate that text onto the attachment row too.
        const isNewConversation = convId !== conversationId;
        if (!isNewConversation && caption) formData.append("content", caption);

        // Silent retry if the server's burst check rejects the upload.
        let result: UploadResult = {};
        for (let attempt = 0; attempt < 4; attempt++) {
          const res = await fetch(`/api/chat/conversations/${convId}/upload`, {
            method: "POST",
            body: formData,
          });
          result = await res.json();
          if (!result.burst) break;
          await new Promise(r => setTimeout(r, (result.retryAfterMs ?? 3000) + 100));
        }

        if (result.success && result.data) {
          pushUserMessage(
            isNewConversation ? initialMessage : (caption || fallbackLabel),
            {
              url:  result.data.attachment_url,
              type: result.data.attachment_type,
              size: result.data.attachment_size,
            }
          );
          if (isNewConversation) {
            setTimeout(() => {
              pushBotMessage(
                createdAfterHours
                  ? afterHoursReceived(hours.nextOpenAt)
                  : "✅ Natanggap ang iyong mensahe! Abangan ang tugon ng aming staff."
              );
            }, 600);
          }
        } else if (result.closed) {
          setConvStatus("closed");
          pushBotMessage(CLOSED_MESSAGE);
        } else if (result.needsAck) {
          setHours(h => ({ ...h, open: false }));
          clearAck();
          pushBotMessage(NEEDS_ACK_MESSAGE);
        } else if (result.burst) {
          pushBotMessage("Hindi naipadala ang file. Pakisubukan muli.");
        } else {
          setIsTyping(true);
          setTimeout(() => { pushBotMessage(`${result.error}`); setIsTyping(false); }, 400);
        }
      } catch {
        setIsTyping(true);
        setTimeout(() => { pushBotMessage("Nabigo ang pag-upload. Subukan muli."); setIsTyping(false); }, 400);
      } finally {
        setUploading(false);
      }
    }

    if (!validateAttachment(doSend)) return;
    doSend();
  }

  // ── Hamburger ─────────────────────────────────────────────────────────

  function handleBack() {
    setMenuOpen(false);
    if (!history.length) return;
    const prev = history[history.length - 1];
    setHistory(h => h.slice(0, -1));
    navigateTo(prev, false);
  }

  function handleGoToMenu() {
    setMenuOpen(false);
    setHistory([]);
    navigateTo(MAIN_MENU_KEY, false);
  }

  function handleEndSession() {
    setMenuOpen(false);
    setStage("ended");
    try {
      localStorage.removeItem(SESSION_CONV_KEY);
      localStorage.removeItem(SESSION_TOKEN_KEY);
      localStorage.removeItem(STAGE_KEY);
      localStorage.removeItem(UNREAD_KEY);
    } catch {}
  }

  // ── Reset ─────────────────────────────────────────────────────────────
  // Note: limitDate is intentionally NOT cleared here. The limit is per IP per
  // PH day, so a new chat would just be rejected again. It expires on its own.

  function handleNewChat() {
    setMessages([]);
    setHistory([]);
    setNodeKey(MAIN_MENU_KEY);
    setHelpdesk("");
    setConvId(null);
    setVisitorToken(null);
    setLiveMode(false);
    setHasUnread(false);
    setConvStatus(null);
    setCaptchaToken(null);
    try {
      localStorage.removeItem(SESSION_CONV_KEY);
      localStorage.removeItem(SESSION_TOKEN_KEY);
      localStorage.removeItem(STAGE_KEY);
      localStorage.removeItem(UNREAD_KEY);
    } catch {}
    setStage("form");
  }

  // ── Derived ───────────────────────────────────────────────────────────

  const currentNode = getNode(currentNodeKey);

  const showAfterHoursNotice =
    stage === "chat" && !hours.open && !ackToday && (liveMode || currentNodeKey === "iba-pa");

  // ── Render ────────────────────────────────────────────────────────────

  return (
    <>
      {!isOpen && !bubbleDismissed && (
        <PreOpenBubble onDismiss={() => setBubble(true)} />
      )}

      <div
        aria-label="City virtual assistant chat"
        aria-hidden={!isOpen}
        className={`fixed bottom-[88px] right-6 w-[340px] max-h-[420px] h-[calc(100vh-120px)] z-[9998] flex flex-col rounded-2xl overflow-hidden shadow-[0_8px_32px_rgba(0,0,0,0.12),0_2px_8px_rgba(0,0,0,0.08)] border border-black/10 bg-background transition-all duration-200 ${
          isOpen
            ? "opacity-100 visible translate-y-0 scale-100 pointer-events-auto"
            : "opacity-0 invisible translate-y-3 scale-95 pointer-events-none"
        }`}
      >
        {showAfterHoursNotice && (
          <AfterHoursNotice
            nextOpenAt={hours.nextOpenAt}
            onAcknowledge={acknowledgeAfterHours}
          />
        )}

        {stage === "chat" && currentNodeKey === "iba-pa" && !liveMode && !limitReached && (hours.open || ackToday) && (
          <HelpdeskCaptchaModal
            verified={!!captchaToken}
            onVerified={setCaptchaToken}
            onExpired={() => setCaptchaToken(null)}
          />
        )}

        {stage === "form" && (
          <ChatForm
            userInfo={userInfo}
            formErrors={formErrors}
            onChange={(field, value) => setUserInfo(u => ({ ...u, [field]: value }))}
            onBlur={(field, value) => {
              const err: Partial<UserInfo> = {};
              if (field === "fullName" && !value.trim())
                err.fullName = "Kinakailangan ang buong pangalan.";
              if (field === "email") {
                if (!value.trim()) err.email = "Kinakailangan ang email.";
                else if (!EMAIL_RE.test(value.trim())) err.email = "Magbigay ng valid na email.";
              }
              if (field === "phone") {
                if (!value.trim()) err.phone = "Kinakailangan ang numero.";
                else if (!PHONE_RE.test(value.trim().replace(/[-\s]/g, "")))
                  err.phone = "Magbigay ng valid na numero (hal. 09XX-XXX-XXXX).";
              }
              setFormErrors(prev => ({
                ...prev, ...err,
                ...(Object.keys(err).length === 0 ? { [field]: undefined } : {}),
              }));
            }}
            onSubmit={handleStartChat}
          />
        )}

        {stage === "chat" && (
          <>
            <ChatHeader
              menuOpen={menuOpen}
              hasHistory={history.length > 0}
              onToggleMenu={() => setMenuOpen(v => !v)}
              onBack={handleBack}
              onGoToMenu={handleGoToMenu}
              onEndSession={handleEndSession}
              onCloseMenu={() => setMenuOpen(false)}
            />
            <ChatMessages
              messages={messages}
              isTyping={isTyping}
              onQuickReply={handleQuickReply}
            />

            {convStatus === "closed" && (
              <div className="border-t border-black/5 bg-muted/40 px-4 py-2 text-center text-xs">
                Natapos na ang usapang ito.{" "}
                <button onClick={handleNewChat} className="font-medium text-blue-700 underline">
                  Magsimula ng bagong chat
                </button>
              </div>
            )}

            <ChatInputArea
              mode={liveMode ? "free-text" : currentNode.inputMode}
              submitting={formSubmitting}
              helpdeskText={helpdeskText}
              inputError={inputError}
              isClosed={convStatus === "closed"}
              cooldownUntil={cooldownUntil}
              uploading={uploading}
              onHelpdeskChange={v => { setHelpdesk(v); clearError(); }}
              onHelpdeskSubmit={() => handleTextSend(helpdeskText)}
              onTextSend={handleTextSend}
              onAttachmentSend={handleAttachmentSend}
              onClearError={clearError}
            />
          </>
        )}

        {stage === "ended" && <ChatEnded onNewChat={handleNewChat} />}
      </div>

      <button
        onClick={() => { setIsOpen(v => !v); setBubble(true); }}
        aria-label={isOpen ? "Close chat" : "Open city virtual assistant"}
        aria-expanded={isOpen}
        className="fixed bottom-6 right-6 w-14 h-14 rounded-full bg-gradient-to-br from-blue-500 to-blue-800 border-none cursor-pointer z-[9999] flex items-center justify-center shadow-[0_4px_16px_rgba(8,168,114,0.35),0_2px_4px_rgba(0,0,0,0.1)] transition-transform duration-200 hover:scale-[1.08]"
      >
        {isOpen ? (
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
            <path d="M18 6L6 18M6 6L18 18" stroke="white" strokeWidth="2.5" strokeLinecap="round" />
          </svg>
        ) : (
          <JPAvatar size={40} />
        )}
        {!isOpen && hasUnread && (
          <span className="absolute top-0.5 right-0.5 w-3 h-3 bg-red-500 rounded-full border-2 border-white" />
        )}
      </button>
    </>
  );
}