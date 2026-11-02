import { useEffect, useMemo, useRef, useState } from "react";
import { cleanOptional, isValidContactNo, isValidEmail } from "@/lib/csm/csmContact";

import { useRouter } from "next/navigation";
import {
  CC2_NA_VALUE,
  CC3_NA_VALUE,
  CONTENT,
  PSGC_BASE,
  SQD_CANONICAL,
  extractArray,
  initialState,
} from "@/components/arta/client-feedback/csmContent";
import type {
  CSMFormProps,
  FieldError,
  FormState,
  Lang,
  Office,
  PsgcOption,
  SubmitStatus,
} from "@/components/arta/client-feedback/types";

// ---------------------------------------------------------------------
// useCSMForm — all state, effects, validation, and submission logic for
// the CSM form. Presentational components just read from / call into
// the object this hook returns.
// ---------------------------------------------------------------------
export function useCSMForm({ officeSlug }: CSMFormProps) {
  const router = useRouter();
  const [showIntro, setShowIntro] = useState(true);
  const [lang, setLang] = useState<Lang>("en");

  // Office is locked in from the URL slug only — there is no dropdown
  // picker anymore. When there's no slug at all (base route), we never
  // fetch anything and just show the "unavailable" message in the splash.
  const [office, setOffice] = useState<Office | null>(null);
  const [loadingOffice, setLoadingOffice] = useState(!!officeSlug);
  const [officeError, setOfficeError] = useState("");
  const [officeNotFound, setOfficeNotFound] = useState(false);

  const formTopRef = useRef<HTMLDivElement>(null);
  const [step, setStep] = useState(0);
  const [form, setForm] = useState<FormState>(initialState);
  const [status, setStatus] = useState<SubmitStatus>("idle");
  const [pdfDownloadFailed, setPdfDownloadFailed] = useState(false);
  const [errorMsg, setErrorMsg] = useState("");
  const [showSuccessOverlay, setShowSuccessOverlay] = useState(false);

  const t = CONTENT[lang];

  // PSGC regions only — the CSM form asks for "region of residence", not a
  // full address, so no province/city/barangay cascade is needed.
  const [regions, setRegions] = useState<PsgcOption[]>([]);
  const [loadingRegions, setLoadingRegions] = useState(false);
  const [regionError, setRegionError] = useState("");

  useEffect(() => {
    if (!officeSlug) {
      // Base route, no slug — nothing to fetch.
      setLoadingOffice(false);
      return;
    }

    let cancelled = false;
    setLoadingOffice(true);
    setOfficeError("");
    setOfficeNotFound(false);

    // Locked-in office via URL — fetch just that one office.
    fetch(`/api/offices/slug/${encodeURIComponent(officeSlug)}`)
      .then(async (res) => {
        if (res.status === 404) {
          if (!cancelled) setOfficeNotFound(true);
          return;
        }
        if (!res.ok) throw new Error("Failed to load office");
        const json = await res.json();
        const data = (json?.data ?? json) as Office;
        if (!cancelled) setOffice(data);
      })
      .catch(() => {
        if (!cancelled) setOfficeError("Couldn't load this office right now. Please refresh and try again.");
      })
      .finally(() => {
        if (!cancelled) setLoadingOffice(false);
      });

    return () => {
      cancelled = true;
    };
  }, [officeSlug]);

  useEffect(() => {
    let cancelled = false;
    setLoadingRegions(true);
    fetch(`${PSGC_BASE}/regions`)
      .then((res) => {
        if (!res.ok) throw new Error("Failed to load regions");
        return res.json();
      })
      .then((data: unknown) => {
        if (!cancelled) setRegions(extractArray<PsgcOption>(data));
      })
      .catch(() => {
        if (!cancelled) setRegionError("Couldn't load regions right now. Please refresh and try again.");
      })
      .finally(() => {
        if (!cancelled) setLoadingRegions(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (status !== "success") {
      setShowSuccessOverlay(false);
      return;
    }
    const raf = requestAnimationFrame(() => setShowSuccessOverlay(true));
    return () => cancelAnimationFrame(raf);
  }, [status]);

  // When CC1 = 4 ("does not know what a CC is"), CC2/CC3 are not
  // applicable and are auto-set + locked, per the paper form's instructions.
  const cc1IsNotAware = form.cc1 === 4;
  useEffect(() => {
    if (cc1IsNotAware) {
      setForm((prev) => ({ ...prev, cc2: CC2_NA_VALUE, cc3: CC3_NA_VALUE }));
    }
  }, [cc1IsNotAware]);

  const [fieldError, setFieldError] = useState<FieldError | null>(null);

  const setField = <K extends keyof FormState>(key: K, value: FormState[K]) => {
    setForm((prev) => ({ ...prev, [key]: value }));
    setFieldError((prev) => (prev && prev.field === (key as string) ? null : prev));
  };

  // Reset the selected service whenever the office changes (or is cleared)
  // so a stale value from a previously-selected office's list can never be
  // submitted. Keyed on office.id so this doesn't fire on every re-render.
  useEffect(() => {
    setForm((prev) => (prev.service ? { ...prev, service: "" } : prev));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [office?.id]);

  // ---- Intro -> Form transition ----
  const chooseLanguage = (l: Lang) => {
    setLang(l);
    setShowIntro(false);
  };

  // ---- Per-step validation ----
  // Returns which field failed (so we can scroll/highlight it) alongside the message.
  const stepError = useMemo((): FieldError | null => {
    if (step === 0) {
      if (!form.clientType) return { field: "clientType", message: t.errClientType };
      if (!form.transactionDate) return { field: "transactionDate", message: t.errDate };
      if (!form.region) return { field: "region", message: t.errRegion };
      if (!form.service.trim()) return { field: "service", message: t.errService };
      if (form.age && (Number(form.age) < 1 || Number(form.age) > 129))
        return { field: "age", message: t.errAge };
      return null;
    }
    if (step === 1) {
      if (!form.cc1) return { field: "cc1", message: t.errCc1 };
      if (!cc1IsNotAware && !form.cc2) return { field: "cc2", message: t.errCc2 };
      if (!cc1IsNotAware && !form.cc3) return { field: "cc3", message: t.errCc3 };
      return null;
    }
    if (step === 2) {
      const keys: (keyof FormState)[] = [
        "sqd0", "sqd1", "sqd2", "sqd3", "sqd4", "sqd5", "sqd6", "sqd7", "sqd8",
      ];
      const missingKey = keys.find((k) => !form[k]);
      if (missingKey) return { field: missingKey, message: t.errSqd };
      return null;
    }
// step 3
if (step === 3) {
  if (form.contactNo.trim() && !isValidContactNo(form.contactNo.trim()))
    return { field: "contactNo", message: t.errContactNo };
  if (form.emailAddress.trim() && !isValidEmail(form.emailAddress.trim()))
    return { field: "emailAddress", message: t.errEmail };
  return null;
}
    return null;
  }, [step, form, cc1IsNotAware, t]);

  // Refs to each field's container, keyed by field name, so a validation
  // failure can pan to (and highlight) the specific field instead of
  // showing a generic message at the bottom of the form.
  const fieldRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const registerField = (name: string) => (el: HTMLDivElement | null) => {
    fieldRefs.current[name] = el;
  };

  const scrollToField = (field: string) => {
    const el = fieldRefs.current[field];
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "center" });
    } else {
      scrollToFormTop();
    }
  };

  const scrollToFormTop = () => {
    formTopRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const goNext = () => {
    if (stepError) {
      setFieldError(stepError);
      scrollToField(stepError.field);
      return;
    }
    setFieldError(null);
    setErrorMsg("");
    setStatus("idle");
    setStep((s) => Math.min(s + 1, t.steps.length - 1));
    scrollToFormTop();
  };

  const goBack = () => {
    setFieldError(null);
    setErrorMsg("");
    setStatus("idle");
    setStep((s) => Math.max(s - 1, 0));
    scrollToFormTop();
  };

  const handleSubmit = async () => {
    if (stepError) {
      setFieldError(stepError);
      scrollToField(stepError.field);
      return;
    }
    if (!office) {
      setErrorMsg(t.errGeneric);
      setStatus("error");
      return;
    }

    setStatus("submitting");
    setErrorMsg("");
    setPdfDownloadFailed(false);

    try {
      const res = await fetch("/api/csm-response", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          language: lang,
          officeId: office.id,
          clientType: form.clientType,
          transactionDate: form.transactionDate,
          sex: form.sex || undefined,
          age: form.age ? Number(form.age) : undefined,
          region: form.region,
          service: form.service.trim(),
          cc1: form.cc1,
          cc2: form.cc2,
          cc3: form.cc3,
          // sqdN are always stored as their canonical English phrase
          // regardless of display language — see setSqd below.
          sqd0: form.sqd0,
          sqd1: form.sqd1,
          sqd2: form.sqd2,
          sqd3: form.sqd3,
          sqd4: form.sqd4,
          sqd5: form.sqd5,
          sqd6: form.sqd6,
          sqd7: form.sqd7,
          sqd8: form.sqd8,
          comments: form.comments.trim() || undefined,
          emailAddress: form.emailAddress.trim() || undefined,
          clientName: cleanOptional(form.clientName) ?? undefined,
contactNo: cleanOptional(form.contactNo) ?? undefined,
        }),
      });

      const contentType = res.headers.get("content-type") || "";

      // Validation/server errors always come back as JSON, regardless of the
      // success-path content type below.
      if (!res.ok) {
        let message = t.errGeneric;
        try {
          const data = await res.json();
          message = data?.message || message;
        } catch {
          // response body wasn't JSON (e.g. a raw 500) — fall back to generic message
        }
        throw new Error(message);
      }

      if (contentType.includes("application/pdf")) {
        // Submission succeeded and the server generated the filled-in form —
        // trigger a browser download of it.
        const blob = await res.blob();
        const disposition = res.headers.get("content-disposition") || "";
        const filenameMatch = disposition.match(/filename="?([^"]+)"?/);
        const filename = filenameMatch ? filenameMatch[1] : "CSM-form.pdf";

        const url = URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = url;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        link.remove();
        URL.revokeObjectURL(url);

        setStatus("success");
      } else {
        // Submission succeeded but the PDF couldn't be generated server-side
        // (see pdfError flag) — the response row was still saved.
        const data = await res.json();
        if (!data.success) {
          throw new Error(data?.message || t.errGeneric);
        }
        setStatus("success");
        setPdfDownloadFailed(Boolean(data.pdfError));
      }

      setTimeout(() => {
        router.push("/");
      }, 6000);
    } catch (err) {
      setStatus("error");
      setErrorMsg(err instanceof Error ? err.message : t.errGeneric);
    }
  };

  // Sets an SQD field by display index (0-5), always storing the canonical
  // English phrase so the backend/DB never has to know the display language.
  const setSqd = (key: keyof FormState, displayIndex: number) => {
    setField(key, SQD_CANONICAL[displayIndex] as never);
  };
  const sqdDisplayIndex = (value: string | null) =>
    value ? SQD_CANONICAL.indexOf(value as (typeof SQD_CANONICAL)[number]) : -1;

  return {
    // intro / language
    showIntro,
    lang,
    setLang,
    chooseLanguage,
    // office
    office,
    loadingOffice,
    officeError,
    officeNotFound,
    // regions
    regions,
    loadingRegions,
    regionError,
    // wizard state
    formTopRef,
    step,
    form,
    status,
    pdfDownloadFailed,
    errorMsg,
    showSuccessOverlay,
    cc1IsNotAware,
    t,
    // field handling
    fieldError,
    setField,
    registerField,
    // navigation
    goNext,
    goBack,
    handleSubmit,
    // sqd helpers
    setSqd,
    sqdDisplayIndex,
  };
}

export type UseCSMFormReturn = ReturnType<typeof useCSMForm>;
