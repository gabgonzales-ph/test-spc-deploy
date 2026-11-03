"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle, Languages } from "lucide-react";
import { motion } from "framer-motion";
import { fadeInUp, staggerContainer } from "./csmContent";
import { CSMIntroSplash } from "./CSMIntroSplash";
import { CSMStepProgress } from "./CSMStepProgress";
import { CSMBody } from "./CSMBody";
import { CSMSuccessOverlay } from "./CSMSuccessOverlay";
import { useCSMForm } from "@/hooks/useCSMForm";
import type { CSMFormProps } from "./types";

// Set on <html> for as long as this page is mounted. global.css uses it to
// hide the site chrome (header, footer, chat widget, privacy popup) during
// both the intro splash and the form itself, on every screen size.
const CHROME_HIDDEN_ATTR = "data-csm-intro";

export default function CSMForm({ officeSlug }: CSMFormProps) {
  const router = useRouter();
  const csm = useCSMForm({ officeSlug });
  const { showIntro, lang, setLang, chooseLanguage, office, loadingOffice, officeError, officeNotFound, t, formTopRef, step, status, pdfDownloadFailed, showSuccessOverlay } = csm;

  useEffect(() => {
    document.documentElement.setAttribute(CHROME_HIDDEN_ATTR, "true");
    // Restore the site chrome when leaving the CSM page.
    return () => document.documentElement.removeAttribute(CHROME_HIDDEN_ATTR);
  }, []);

  return (
    <>
      <CSMIntroSplash
        show={showIntro}
        officeSlug={officeSlug}
        office={office}
        loadingOffice={loadingOffice}
        officeError={officeError}
        officeNotFound={officeNotFound}
        onChooseLanguage={chooseLanguage}
        onReturn={() => router.push("/")}
      />

      {/* Main form content */}
      {!showIntro && (
        <motion.div
          ref={formTopRef}
          className="w-full sm:max-w-2xl mx-auto sm:mt-12 scroll-mt-6"
          initial="hidden"
          animate="visible"
          variants={staggerContainer}
        >
          {/* Below sm: full-screen, no card chrome. From sm up: the original card. */}
          <div className="min-h-screen sm:min-h-0 bg-white sm:rounded-2xl overflow-hidden sm:drop-shadow-lg sm:shadow-gray-900/5 sm:border border-gray-200">
            {/* Header */}
            <motion.div
              variants={fadeInUp}
              transition={{ duration: 0.4, ease: "easeOut" }}
              className="px-4 sm:px-8 py-5 sm:py-6 bg-gray-50/60"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-[12px] font-semibold tracking-[0.12em] uppercase text-emerald-700">
                    {t.orgLabel}
                  </p>
                  <h2 className="mt-1 text-[22px] sm:text-[24px] font-semibold text-gray-900 tracking-tight">
                    {t.appTitle}
                  </h2>
                </div>
                <button
                  type="button"
                  onClick={() => setLang(lang === "en" ? "tl" : "en")}
                  className="shrink-0 inline-flex items-center gap-1.5 rounded-lg border border-gray-200 px-2.5 py-1.5 text-[12px] font-medium text-gray-500 transition-all duration-150 hover:border-emerald-300 hover:bg-emerald-50/60 hover:text-emerald-800"
                  title="Switch language"
                >
                  <Languages className="h-3.5 w-3.5" />
                  {lang === "en" ? "Tagalog" : "English"}
                </button>
              </div>
              <p className="mt-1 text-[13px] text-gray-500 leading-relaxed">{t.appDesc}</p>
              {office && (
                <p className="mt-2.5 inline-flex items-center gap-1.5 rounded-full  px-3 py-1 text-[11.5px] font-medium text-emerald-800">
                  <CheckCircle className="h-3.5 w-3.5" />
                  {office.name}
                </p>
              )}
            </motion.div>

            <CSMStepProgress steps={t.steps} step={step} lang={lang} />

            <CSMBody csm={csm} />
          </div>

          <CSMSuccessOverlay
            status={status}
            showSuccessOverlay={showSuccessOverlay}
            pdfDownloadFailed={pdfDownloadFailed}
            successTitle={t.successTitle}
            successMsg={t.successMsg}
            pdfFailedNote={t.pdfFailedNote}
            redirectMsg={t.redirectMsg}
          />
        </motion.div>
      )}
    </>
  );
}