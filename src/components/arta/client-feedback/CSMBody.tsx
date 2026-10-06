import { motion } from "framer-motion";
import { AlertCircle, ChevronLeft, ChevronRight, Loader2, Send } from "lucide-react";
import { choiceBtnClass, fadeInUp, inputClass, orderSqdOptions, SQD_ICONS } from "./csmContent";
import { RadioGroup } from "./RadioGroup";
import type { ClientType, Sex } from "./types";
import type { UseCSMFormReturn } from "@/hooks/useCSMForm";


type Props = { csm: UseCSMFormReturn };

export function CSMBody({ csm }: Props) {
  const {
    step,
    form,
    setField,
    t,
    fieldError,
    registerField,
    office,
    loadingRegions,
    regions,
    regionError,
    cc1IsNotAware,
    setSqd,
    sqdDisplayIndex,
    status,
    errorMsg,
    goBack,
    goNext,
    handleSubmit,
  } = csm;

  return (
    <motion.div
      variants={fadeInUp}
      transition={{ duration: 0.4, ease: "easeOut" }}
      className="px-6 sm:px-8 py-7"
    >
      {step === 0 && (
          <div className="space-y-5">
            <div ref={registerField("clientType")}>
              <p className="text-[13px] font-medium text-gray-700 mb-1.5">
                {t.clientTypeLabel} <span className="text-emerald-600">*</span>
              </p>
              <div className="grid grid-cols-3 gap-2">
                {(["citizen", "business", "government"] as ClientType[]).map((v) => (
                  <button
                    key={v}
                    type="button"
                    onClick={() => setField("clientType", v)}
                    className={choiceBtnClass(form.clientType === v) + " text-center font-medium"}
                  >
                    {t.clientTypes[v]}
                  </button>
                ))}
              </div>
              {fieldError?.field === "clientType" && (
                <p className="mt-1.5 text-[12px] text-red-600">{fieldError.message}</p>
              )}
            </div>

            <div className="grid sm:grid-cols-2 gap-4">
              <div ref={registerField("transactionDate")}>
                <label className="block text-[13px] font-medium text-gray-700 mb-1.5">
                  {t.dateLabel} <span className="text-emerald-600">*</span>
                </label>
                <input
                  type="date"
                  value={form.transactionDate}
                  onChange={(e) => setField("transactionDate", e.target.value)}
                  className={inputClass}
                />
                {fieldError?.field === "transactionDate" && (
                  <p className="mt-1.5 text-[12px] text-red-600">{fieldError.message}</p>
                )}
              </div>
              <div>
                <p className="text-[13px] font-medium text-gray-700 mb-1.5">
                  {t.sexLabel} <span className="text-gray-400 font-normal">{t.optionalTag}</span>
                </p>
                <div className="grid grid-cols-2 gap-2">
                  {(["male", "female"] as Sex[]).map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() => setField("sex", form.sex === v ? "" : v)}
                      className={choiceBtnClass(form.sex === v) + " text-center font-medium"}
                    >
                      {t.sexOptions[v]}
                    </button>
                  ))}
                </div>
              </div>
            </div>

            <div className="grid sm:grid-cols-2 gap-4">
              <div ref={registerField("age")}>
                <label className="block text-[13px] font-medium text-gray-700 mb-1.5">
                  {t.ageLabel} <span className="text-gray-400 font-normal">{t.optionalTag}</span>
                </label>
                <input
                  type="number"
                  min={1}
                  max={129}
                  value={form.age}
                  onChange={(e) => setField("age", e.target.value.replace(/\D/g, "").slice(0, 3))}
                  placeholder={t.agePlaceholder}
                  className={inputClass}
                />
                {fieldError?.field === "age" && (
                  <p className="mt-1.5 text-[12px] text-red-600">{fieldError.message}</p>
                )}
              </div>
              <div ref={registerField("region")}>
                <label className="block text-[13px] font-medium text-gray-700 mb-1.5">
                  {t.regionLabel} <span className="text-emerald-600">*</span>
                </label>
                <select
                  value={form.region}
                  onChange={(e) => setField("region", e.target.value)}
                  disabled={loadingRegions}
                  className={inputClass}
                >
                  <option value="">{loadingRegions ? t.regionLoading : t.regionPlaceholder}</option>
                  {regions.map((r) => (
                    <option key={r.code} value={r.name}>
                      {r.name}
                    </option>
                  ))}
                </select>
                {regionError && <p className="mt-1 text-[12px] text-red-600">{regionError}</p>}
                {fieldError?.field === "region" && (
                  <p className="mt-1.5 text-[12px] text-red-600">{fieldError.message}</p>
                )}
              </div>
            </div>

            <div ref={registerField("service")}>
              <label className="block text-[13px] font-medium text-gray-700 mb-1.5">
                {t.serviceLabel} <span className="text-emerald-600">*</span>
              </label>
              {(() => {
                const officeServices = office?.services ?? [];
                const noOffice = !office;
                const noServices = !noOffice && officeServices.length === 0;
                return (
                  <>
                    <select
                      value={form.service}
                      onChange={(e) => setField("service", e.target.value)}
                      disabled={noOffice || noServices}
                      className={inputClass}
                    >
                      <option value="">
                        {noOffice ? t.serviceNoOfficeMsg : noServices ? t.serviceNoneMsg : t.servicePlaceholder}
                      </option>
                      {officeServices.map((s) => (
                        <option key={s} value={s}>
                          {s}
                        </option>
                      ))}
                    </select>
                    {noServices && <p className="mt-1 text-[12px] text-gray-400">{t.serviceNoneMsg}</p>}
                  </>
                );
              })()}
              {fieldError?.field === "service" && (
                <p className="mt-1.5 text-[12px] text-red-600">{fieldError.message}</p>
              )}
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="space-y-6">
            <p className="text-[12.5px] text-gray-500 leading-relaxed">{t.ccIntro}</p>

            <RadioGroup
              title={t.cc1Title}
              required
              fieldRef={registerField("cc1")}
              errorText={fieldError?.field === "cc1" ? fieldError.message : undefined}
              options={t.cc1Options.map((label, i) => ({ value: i + 1, label }))}
              value={form.cc1}
              onChange={(v) => setField("cc1", v)}
            />

            <RadioGroup
              title={t.cc2Title}
              required
              disabled={cc1IsNotAware}
              helperText={cc1IsNotAware ? t.naNote : undefined}
              fieldRef={registerField("cc2")}
              errorText={fieldError?.field === "cc2" ? fieldError.message : undefined}
              options={t.cc2Options.map((label, i) => ({ value: i + 1, label }))}
              value={form.cc2}
              onChange={(v) => setField("cc2", v)}
            />

            <RadioGroup
              title={t.cc3Title}
              required
              disabled={cc1IsNotAware}
              helperText={cc1IsNotAware ? t.naNote : undefined}
              fieldRef={registerField("cc3")}
              errorText={fieldError?.field === "cc3" ? fieldError.message : undefined}
              options={t.cc3Options.map((label, i) => ({ value: i + 1, label }))}
              value={form.cc3}
              onChange={(v) => setField("cc3", v)}
            />
          </div>
        )}

        {step === 2 && (
          <div className="space-y-6">
            <p className="text-[12.5px] text-gray-500 leading-relaxed">{t.sqdIntro}</p>
            {(["sqd0", "sqd1", "sqd2", "sqd3", "sqd4", "sqd5", "sqd6", "sqd7", "sqd8"] as const).map((key, idx) => (
              <RadioGroup
                key={key}
                title={`SQD${idx}. ${t.sqdItems[idx]}`}
                required
                compact
                fieldRef={registerField(key)}
                errorText={fieldError?.field === key ? fieldError.message : undefined}
                options={orderSqdOptions(
  t.sqdOptions.map((label, i) => ({
    value: i,
    label,
    icon: SQD_ICONS[i].icon,
    iconTone: SQD_ICONS[i].tone,
  }))
)}
                value={sqdDisplayIndex(form[key])}
                onChange={(displayIndex) => setSqd(key, displayIndex)}
              />
            ))}
          </div>
        )}

        {step === 3 && (
          <div className="space-y-5">
            <div>
              <label className="block text-[13px] font-medium text-gray-700 mb-1.5">
                {t.commentsLabel} <span className="text-gray-400 font-normal">{t.optionalTag}</span>
              </label>
              <textarea
                rows={5}
                value={form.comments}
                onChange={(e) => setField("comments", e.target.value.slice(0, 1000))}
                placeholder={t.commentsPlaceholder}
                className={`${inputClass} resize-none`}
              />
              <p className="mt-1 text-[12px] text-gray-400">{form.comments.length}/1000</p>
            </div>

            <div ref={registerField("emailAddress")}>
              <label className="block text-[13px] font-medium text-gray-700 mb-1.5">
                {t.emailLabel} <span className="text-gray-400 font-normal">{t.optionalTag}</span>
              </label>
              <input
                type="email"
                value={form.emailAddress}
                onChange={(e) => setField("emailAddress", e.target.value)}
                maxLength={100}
                placeholder={t.emailPlaceholder}
                className={inputClass}
              />
              {fieldError?.field === "emailAddress" && (
                <p className="mt-1.5 text-[12px] text-red-600">{fieldError.message}</p>
              )}
            </div>
          </div>
        )}

        {/* Status message */}
        {status === "error" && errorMsg && (
          <div className="mt-5 flex items-start gap-2.5 rounded-lg bg-red-50 border border-red-100 px-4 py-3">
            <AlertCircle className="h-4.5 w-4.5 text-red-500 shrink-0 mt-0.5" />
            <p className="text-[13.5px] text-red-700">{errorMsg}</p>
          </div>
        )}

        {/* Navigation */}
        <div className="mt-7 flex items-center justify-between gap-3">
          <button
            type="button"
            onClick={goBack}
            disabled={step === 0 || status === "submitting"}
            className="inline-flex items-center gap-1.5 px-4 py-2.5 text-[13.5px] font-medium text-gray-600 rounded-lg border border-gray-200 hover:bg-gray-50 hover:text-gray-900 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <ChevronLeft className="h-3.5 w-3.5" />
            {t.backBtn}
          </button>

          {step < t.steps.length - 1 ? (
            <button
              type="button"
              onClick={goNext}
              className="inline-flex items-center gap-1.5 px-5 py-2.5 text-[13.5px] font-semibold text-white rounded-lg bg-emerald-700 hover:bg-emerald-800 transition-colors shadow-sm"
            >
              {t.nextBtn}
              <ChevronRight className="h-3.5 w-3.5" />
            </button>
          ) : (
            <button
              type="button"
              onClick={handleSubmit}
              disabled={status === "submitting"}
              className="inline-flex items-center gap-1.5 px-5 py-2.5 text-[13.5px] font-semibold text-white rounded-lg bg-emerald-700 hover:bg-emerald-800 transition-colors shadow-sm disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {status === "submitting" ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  {t.sendingBtn}
                </>
              ) : (
                <>
                  <Send className="h-3.5 w-3.5" />
                  {t.submitBtn}
                </>
              )}
            </button>
          )}
        </div>
    </motion.div>
  );
}

export default CSMBody;