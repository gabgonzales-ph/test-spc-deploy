"use client";
import React, { useState, useEffect } from "react";
import { usePathname } from "next/navigation";

const EXCLUDED_ROUTES = ["/privacy-policy", "/terms-of-service", "/cookie-policy"];

// Routes where the popup must never mount or lock the page. The CSM form hides
// the site chrome with CSS, so a mounted popup would hold an invisible scroll lock.
const EXCLUDED_PREFIXES = ["/arta/client-feedback"];

const isExcluded = (p: string | null) =>
  !!p &&
  (EXCLUDED_ROUTES.includes(p) || EXCLUDED_PREFIXES.some((x) => p.startsWith(x)));

export default function DataPrivacyPolicyPopup() {
  const pathname = usePathname();
  const [isOpen, setIsOpen] = useState<boolean | null>(null);
  const [isRejected, setIsRejected] = useState(false);

  // Check localStorage immediately after mount — no artificial delay.
  // isOpen stays null on first paint so popup text never becomes the LCP element.
  useEffect(() => {
    if (isExcluded(pathname)) {
      setIsOpen(false);
      setIsRejected(false);
      return;
    }

    const accepted = localStorage.getItem("dataPolicyAccepted");
    setIsOpen(accepted !== "true");
    setIsRejected(false);
  }, [pathname]);

  // Body scroll lock
  useEffect(() => {
    if (isExcluded(pathname)) return;
    if (!isOpen && !isRejected) return;

    const scrollY = window.scrollY;
    document.body.style.position = "fixed";
    document.body.style.top = `-${scrollY}px`;
    document.body.style.width = "100%";
    document.body.style.overflow = "hidden";

    return () => {
      document.body.style.position = "";
      document.body.style.top = "";
      document.body.style.width = "";
      document.body.style.overflow = "";
      window.scrollTo(0, scrollY);
    };
  }, [isOpen, isRejected, pathname]);

  // Restore body styles on excluded routes
  useEffect(() => {
    if (isExcluded(pathname)) {
      document.body.style.position = "";
      document.body.style.top = "";
      document.body.style.width = "";
      document.body.style.overflow = "";
    }
  }, [pathname]);

  if (isOpen === null) return null;
  if (isExcluded(pathname)) return null;

  if (isRejected) {
    return (
      <div className="fixed inset-0 z-[9998] bg-black/60 select-none" aria-hidden="true" />
    );
  }

  if (!isOpen) return null;

  return (
    <>
      <div className="fixed inset-0 z-[9998] bg-black/60 select-none" aria-hidden="true" />
      <div className="fixed bottom-0 left-0 right-0 z-[9999] bg-white shadow-[0_-8px_20px_rgba(0,0,0,0.25)]">
        <div className="p-6 w-full">
          <div className="max-w-6xl mx-auto flex flex-col md:flex-row items-start md:items-center gap-6">
            <div className="flex-1 space-y-3">
              <h2 className="text-2xl font-bold text-slate-900">Data Privacy Policy</h2>
              <p className="text-slate-700 text-sm leading-relaxed">
                The City Government of San Pablo values your privacy and is dedicated to
                protecting your personal data in compliance with the Data Privacy Act (DPA)
                of 2012 (Republic Act No. 10173).{" "}

                <a
                  href="/privacy-policy"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-600 hover:text-blue-700 font-medium underline"
                >
                  Read More
                </a>
              </p>
            </div>
            <div className="flex gap-3 md:flex-shrink-0">
              <button
                onClick={() => {
                  localStorage.setItem("dataPolicyAccepted", "false");
                  setIsOpen(false);
                  setIsRejected(true);
                }}
                className="px-6 py-2.5 font-medium text-slate-700 border border-slate-300 hover:bg-slate-100 transition-colors whitespace-nowrap"
              >
                Reject All
              </button>
              <button
                onClick={() => {
                  localStorage.setItem("dataPolicyAccepted", "true");
                  setIsOpen(false);
                  setIsRejected(false);
                  document.body.style.position = "";
                  document.body.style.top = "";
                  document.body.style.width = "";
                  document.body.style.overflow = "";
                }}
                className="px-6 py-2.5 font-medium text-white bg-slate-900 hover:bg-slate-800 transition-colors whitespace-nowrap"
              >
                Accept All
              </button>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}