// src/hooks/useChatApi.ts

import { useState, useEffect, useRef } from "react";

// Client-side guard: input hygiene and a short burst window for instant UX
// feedback. The server is the authority on operating hours, the after-hours
// acknowledgement and the daily caps (100 during operating hours, 25 after
// hours), so there is no daily counter here anymore.

const MAX_LEN       = 1000;
const RATE_WINDOW   = 4_000;
const LAST_SENT_KEY = "jp_last_sent";
const SPAM_RE       = /https?:\/\/|(\S)\1{6,}|[^\w\s,.!?'"()\-:]{4,}/i;

export function sanitizeInput(raw: string): string {
  return raw
    .replace(/<[^>]*>/g, "")
    .replace(/&[a-z]+;/gi, " ")
    .replace(/[\u0000-\u001F\u007F]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_LEN);
}

function getLastSentAt(): number {
  try { return parseInt(localStorage.getItem(LAST_SENT_KEY) ?? "0", 10); } catch { return 0; }
}

function setLastSentAt(ts: number) {
  try { localStorage.setItem(LAST_SENT_KEY, String(ts)); } catch {}
}

export function useInputGuard() {
  const [error, setError]                 = useState<string | null>(null);
  const [cooldownUntil, setCooldownUntil] = useState<number | null>(null);
  // Generic no-arg thunk — works for a delayed text send, a delayed attachment
  // send, or anything else that needs to retry once the rate window clears.
  const pendingRef                        = useRef<(() => void) | null>(null);

  useEffect(() => {
    if (cooldownUntil === null) return;
    const remaining = Math.max(0, cooldownUntil - Date.now());
    const t = setTimeout(() => {
      setCooldownUntil(null);
      if (pendingRef.current) {
        const fn = pendingRef.current;
        pendingRef.current = null;
        fn();
      }
    }, remaining);
    return () => clearTimeout(t);
  }, [cooldownUntil]);

  // Shared burst gate. If a send arrives inside the rate window and the caller
  // supplied onDelayed, it is scheduled for when the window clears.
  function checkLimit(onDelayed?: () => void): boolean {
    const now     = Date.now();
    const elapsed = now - getLastSentAt();

    if (elapsed < RATE_WINDOW) {
      if (onDelayed) {
        setLastSentAt(now);
        setError(null);
        pendingRef.current = onDelayed;
        setCooldownUntil(now + RATE_WINDOW - elapsed); // remaining ms, not a new full window
      }
      return false;
    }

    setLastSentAt(now);
    setError(null);
    return true;
  }

  // Text-message path — sanitizes/spam-checks first, then applies the burst gate.
  function validate(text: string, onDelayed?: (t: string) => void): boolean {
    const t = sanitizeInput(text);

    if (!t || SPAM_RE.test(t)) {
      setError("This is an invalid inquiry.");
      return false;
    }

    return checkLimit(onDelayed ? () => onDelayed(t) : undefined);
  }

  // Attachment path — no text to sanitize/spam-check, same burst window.
  function validateAttachment(onDelayed?: () => void): boolean {
    return checkLimit(onDelayed);
  }

  function clearError() { setError(null); }

  return {
    validate, validateAttachment, sanitizeInput,
    error, clearError, cooldownUntil,
  };
}