import { AnimatePresence, motion } from "framer-motion";
import { CheckCircle2, Loader2 } from "lucide-react";
import type { Lang, Office } from "./types";

// ---------------------------------------------------------------------
// CsmIllustration — custom inline SVG: a feedback clipboard with a star
// rating, built entirely from shapes (no external image asset needed).
// ---------------------------------------------------------------------
function CsmIllustration() {
  return (
    <svg viewBox="0 0 120 120" className="h-full w-full" aria-hidden="true">
      {/* Soft backdrop circle */}
      <circle cx="60" cy="60" r="56" fill="#ECFDF5" />
      <circle cx="60" cy="60" r="56" fill="none" stroke="#A7F3D0" strokeWidth="1.5" />

      {/* Clipboard body */}
      <rect x="34" y="26" width="52" height="66" rx="7" fill="#FFFFFF" stroke="#059669" strokeWidth="2.5" />
      {/* Clipboard clip */}
      <rect x="49" y="20" width="22" height="12" rx="4" fill="#059669" />
      <rect x="53" y="24" width="14" height="4" rx="2" fill="#D1FAE5" />

      {/* Checklist lines */}
      <g stroke="#10B981" strokeWidth="2.4" strokeLinecap="round">
        <path d="M42 42 L46 46 L52 38" fill="none" />
        <line x1="58" y1="42" x2="78" y2="42" />

        <path d="M42 56 L46 60 L52 52" fill="none" />
        <line x1="58" y1="56" x2="78" y2="56" />
      </g>

      {/* Star rating row */}
      <g fill="#FBBF24">
        <path d="M44 72 l2.1 4.3 4.7.7-3.4 3.3.8 4.7-4.2-2.2-4.2 2.2.8-4.7-3.4-3.3 4.7-.7z" />
        <path d="M58 72 l2.1 4.3 4.7.7-3.4 3.3.8 4.7-4.2-2.2-4.2 2.2.8-4.7-3.4-3.3 4.7-.7z" />
        <path d="M72 72 l2.1 4.3 4.7.7-3.4 3.3.8 4.7-4.2-2.2-4.2 2.2.8-4.7-3.4-3.3 4.7-.7z" fillOpacity="0.35" />
      </g>

      {/* Chat bubble accent, top-right */}
      <g transform="translate(80,14)">
        <path
          d="M0 10c0-5.5 4.5-10 10-10h6c5.5 0 10 4.5 10 10s-4.5 10-10 10h-2l-4.5 4.5V20C5.7 19.3 0 15.2 0 10z"
          fill="#059669"
        />
        <circle cx="9" cy="10" r="1.6" fill="#ECFDF5" />
        <circle cx="14.5" cy="10" r="1.6" fill="#ECFDF5" />
        <circle cx="20" cy="10" r="1.6" fill="#ECFDF5" />
      </g>
    </svg>
  );
}

export function CSMIntroSplash({
  show,
  officeSlug,
  office,
  loadingOffice,
  officeError,
  officeNotFound,
  onChooseLanguage,
  onReturn,
}: {
  show: boolean;
  officeSlug?: string;
  office: Office | null;
  loadingOffice: boolean;
  officeError: string;
  officeNotFound: boolean;
  onChooseLanguage: (lang: Lang) => void;
  onReturn: () => void;
}) {
  // Hiding the site chrome is handled by CSMForm for the whole CSM page.
  return (
    <AnimatePresence>
      {show && (
        <motion.section
          key="csm-splash-overlay"
          // Starts fully opaque so the site is never visible behind the splash on first paint.
          initial={{ opacity: 1, y: 0 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -40 }}
          transition={{ duration: 0.6, ease: "easeInOut" }}
          className="fixed inset-0 z-[9999] overflow-hidden bg-gradient-to-br from-white via-emerald-50 to-emerald-100 flex flex-col items-center justify-center px-4"
        >
          {/* Decorative background accents */}
          <div className="pointer-events-none absolute inset-0 overflow-hidden">
            <div className="absolute -top-24 -left-24 h-72 w-72 rounded-full bg-emerald-200/40 blur-3xl" />
            <div className="absolute -bottom-32 -right-16 h-96 w-96 rounded-full bg-emerald-300/30 blur-3xl" />
            <div className="absolute top-1/3 right-10 h-40 w-40 rounded-full bg-teal-100/50 blur-2xl hidden sm:block" />
            <svg className="absolute inset-0 h-full w-full opacity-[0.14]" aria-hidden="true">
              <defs>
                <pattern id="csm-dot-grid" width="28" height="28" patternUnits="userSpaceOnUse">
                  <circle cx="1.5" cy="1.5" r="1.5" fill="#047857" />
                </pattern>
              </defs>
              <rect width="100%" height="100%" fill="url(#csm-dot-grid)" />
            </svg>
          </div>

          <motion.div
            initial={{ opacity: 0, y: 16, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={{ duration: 0.5, ease: "easeOut", delay: 0.1 }}
            className="relative w-full max-w-md rounded-3xl border border-emerald-100 bg-white/90 backdrop-blur-sm shadow-xl shadow-emerald-900/5 px-7 sm:px-10 py-10 text-center"
          >
            {/* Custom illustration */}
            <div className="mx-auto mb-6 h-24 w-24">
              <CsmIllustration />
            </div>

            <p className="text-[11px] font-semibold tracking-[0.16em] uppercase text-emerald-600">
              City Government of San Pablo
            </p>
            <h1 className="mt-2 text-[24px] sm:text-[27px] font-bold text-gray-900 tracking-tight leading-snug">
              We value your feedback!
            </h1>
            <p className="mt-2 text-[13px] text-gray-500">
              Help us improve our services by sharing your experience with us.
            </p>

            {!officeSlug ? (
              // Base route — no office slug at all. No form was ever
              // reachable here without a QR/office link, so just show
              // the unavailable notice in place of the picker/language UI.
              <div className="mt-6 rounded-xl border border-gray-200 bg-gray-50 px-4 py-4 text-center">
                <p className="text-[13.5px] font-medium text-gray-700">
                  This feature is only available after availing our service. Thank you!
                </p>
              </div>
            ) : (
              <>
                {officeNotFound ? (
                  <div className="mt-6 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-left">
                    <p className="text-[13px] font-medium text-amber-800">Office not found</p>
                    <p className="mt-0.5 text-[12.5px] text-amber-700">
                      This feedback link doesn&apos;t match any office on record. Please check the
                      link or QR code and try again, or contact the office directly.
                    </p>
                  </div>
                ) : null}

                {officeError ? <p className="mt-4 text-[12.5px] text-red-600">{officeError}</p> : null}

                {/* Locked-in office (from URL slug) */}
                {!officeNotFound && !officeError ? (
                  <div className="mt-6 text-left">
                    <p className="mb-1.5 text-[12px] font-semibold uppercase tracking-wide text-gray-500">
                      Office / Tanggapan
                    </p>

                    {loadingOffice ? (
                      <div className="flex items-center gap-2.5 rounded-xl border border-gray-200 bg-gray-50 px-4 py-3">
                        <Loader2 className="h-4 w-4 shrink-0 animate-spin text-gray-400" />
                        <p className="text-[13px] text-gray-500">Loading office...</p>
                      </div>
                    ) : office ? (
                      <div className="flex items-center gap-2.5 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3">
                        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-white">
                          <CheckCircle2 className="h-4.5 w-4.5" />
                        </span>
                        <div className="min-w-0">
                          <p className="truncate text-[13.5px] font-semibold text-emerald-900">{office.name}</p>
                          <p className="text-[11.5px] text-emerald-700">Giving feedback for this office</p>
                        </div>
                      </div>
                    ) : null}
                  </div>
                ) : null}

                <div className="mt-6 flex items-center justify-center gap-2 text-[13px] text-gray-500">
                  <span className="h-px w-6 bg-gray-200" />
                  <span>Select language &middot; Piliin ang wika</span>
                  <span className="h-px w-6 bg-gray-200" />
                </div>

                <div
                  className={`mt-5 grid grid-cols-2 gap-3 transition-opacity duration-200 ${
                    office ? "opacity-100" : "opacity-40 pointer-events-none"
                  }`}
                  aria-disabled={!office}
                >
                  <motion.button
                    type="button"
                    onClick={() => office && onChooseLanguage("en")}
                    whileHover={office ? { y: -3 } : undefined}
                    whileTap={office ? { scale: 0.97 } : undefined}
                    className="group flex flex-col items-center gap-1.5 rounded-2xl border border-gray-200 bg-white px-5 py-4 transition-all duration-150 hover:border-emerald-400 hover:bg-emerald-50/70 hover:shadow-md disabled:hover:border-gray-200 disabled:hover:bg-white disabled:hover:shadow-none"
                    disabled={!office}
                  >
                    <span className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-50 text-[12px] font-bold text-emerald-700 transition-colors group-hover:bg-emerald-100">
                      EN
                    </span>
                    <span className="text-[14px] font-semibold text-gray-700 group-hover:text-emerald-800">
                      English
                    </span>
                  </motion.button>
                  <motion.button
                    type="button"
                    onClick={() => office && onChooseLanguage("tl")}
                    whileHover={office ? { y: -3 } : undefined}
                    whileTap={office ? { scale: 0.97 } : undefined}
                    className="group flex flex-col items-center gap-1.5 rounded-2xl border border-gray-200 bg-white px-5 py-4 transition-all duration-150 hover:border-emerald-400 hover:bg-emerald-50/70 hover:shadow-md disabled:hover:border-gray-200 disabled:hover:bg-white disabled:hover:shadow-none"
                    disabled={!office}
                  >
                    <span className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-50 text-[12px] font-bold text-emerald-700 transition-colors group-hover:bg-emerald-100">
                      TL
                    </span>
                    <span className="text-[14px] font-semibold text-gray-700 group-hover:text-emerald-800">
                      Tagalog
                    </span>
                  </motion.button>
                </div>
              </>
            )}
          </motion.div>

          <motion.button
            type="button"
            onClick={onReturn}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4, ease: "easeOut", delay: 0.15 }}
            className="relative mt-5 text-[13px] font-medium text-emerald-600 underline underline-offset-2 transition-colors hover:text-emerald-700"
          >
            Return to Home
          </motion.button>
        </motion.section>
      )}
    </AnimatePresence>
  );
}

export default CSMIntroSplash;