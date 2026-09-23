// src/components/chat/ui/HelpdeskCaptchaModal.tsx
"use client";

import { useEffect, useRef, useState } from "react";

// reCAPTCHA v2 checkbox, explicit-render (same underlying pattern as
// EPACDForm). Rendered as a full-panel overlay — the whole chat panel is
// blocked until the checkbox is solved, then this fades away smoothly to
// reveal the panel underneath. Purely reactive to the `verified` prop:
// the widget itself stays mounted the whole time (never remounted), so if
// the token later expires and `verified` flips back to false, the overlay
// fades back in with a freshly reset checkbox — no remount tricks needed.

declare global {
  interface Window {
    grecaptcha?: {
      reset: (widgetId?: number) => void;
      getResponse: (widgetId?: number) => string;
      render: (container: HTMLElement, params: Record<string, unknown>) => number;
      ready: (cb: () => void) => void;
    };
    onHelpdeskCaptchaVerified?: (token: string) => void;
    onHelpdeskCaptchaExpired?: () => void;
  }
}

const RECAPTCHA_SITE_KEY = process.env.NEXT_PUBLIC_RECAPTCHA_SITE_KEY ?? "";

interface HelpdeskCaptchaModalProps {
  // true once a token exists in the parent — triggers the fade-out.
  verified: boolean;
  onVerified: (token: string) => void;
  onExpired: () => void;
}

export function HelpdeskCaptchaModal({ verified, onVerified, onExpired }: HelpdeskCaptchaModalProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const widgetIdRef = useRef<number | null>(null);
  const [scriptLoaded, setScriptLoaded] = useState(false);

  useEffect(() => {
    window.onHelpdeskCaptchaVerified = onVerified;
    window.onHelpdeskCaptchaExpired = onExpired;
    return () => {
      delete window.onHelpdeskCaptchaVerified;
      delete window.onHelpdeskCaptchaExpired;
    };
  }, [onVerified, onExpired]);

  // Load the script once. If some other captcha instance on the page (e.g.
  // EPACDForm) already injected it, reuse that instead of adding a second
  // <script> tag.
  useEffect(() => {
    const existing = document.querySelector<HTMLScriptElement>(
      'script[src^="https://www.google.com/recaptcha/api.js"]'
    );
    if (existing) {
      if (window.grecaptcha) setScriptLoaded(true);
      else existing.addEventListener("load", () => setScriptLoaded(true));
      return;
    }
    const script = document.createElement("script");
    script.src = "https://www.google.com/recaptcha/api.js?render=explicit";
    script.async = true;
    script.onload = () => setScriptLoaded(true);
    document.body.appendChild(script);
  }, []);

  useEffect(() => {
    if (!scriptLoaded || !containerRef.current || widgetIdRef.current !== null) return;
    const render = () => {
      if (!window.grecaptcha || !containerRef.current) return;
      if (containerRef.current.childElementCount > 0) return;
      widgetIdRef.current = window.grecaptcha.render(containerRef.current, {
        sitekey: RECAPTCHA_SITE_KEY,
        callback: "onHelpdeskCaptchaVerified",
        "expired-callback": "onHelpdeskCaptchaExpired",
      });
    };
    window.grecaptcha?.ready ? window.grecaptcha.ready(render) : render();
  }, [scriptLoaded]);

  // Whenever we go back to "not verified" (expiry, or a failed submission
  // cleared the token upstream) and the widget already exists, reset the
  // checkbox so the re-shown overlay isn't stuck showing a checked box
  // that no longer corresponds to a valid token.
  useEffect(() => {
    if (!verified && widgetIdRef.current !== null && window.grecaptcha) {
      window.grecaptcha.reset(widgetIdRef.current);
    }
  }, [verified]);

  return (
    <div
      aria-hidden={verified}
      className={`absolute inset-0 z-20 flex items-center justify-center bg-background/95 backdrop-blur-[2px] transition-all duration-300 ease-out ${
        verified ? "opacity-0 scale-95 pointer-events-none" : "opacity-100 scale-100"
      }`}
    >
      <div className="mx-4 flex flex-col items-center gap-3 bg-background px-5 py-6 shadow-lg ring-1 ring-black/5 text-center">
        <p className="text-[13px] text-foreground leading-relaxed">
          I-check ang kahon at sagutan ang katanungan upang magamit ang Help Desk.
        </p>
        <div ref={containerRef} />
      </div>
    </div>
  );
}