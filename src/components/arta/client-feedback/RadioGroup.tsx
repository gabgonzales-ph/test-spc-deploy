import type { LucideIcon } from "lucide-react";
import { choiceBtnClass } from "./csmContent";

// ---------------------------------------------------------------------
// RadioGroup — shared control for CC/SQD single-choice questions
// ---------------------------------------------------------------------
export function RadioGroup({
  title,
  options,
  value,
  onChange,
  required,
  disabled,
  compact,
  helperText,
  fieldRef,
  errorText,
}: {
  title: string;
options: { value: number; label: string; icon?: LucideIcon; iconTone?: string }[];
  value: number | null;
  onChange: (value: number) => void;
  required?: boolean;
  disabled?: boolean;
  compact?: boolean;
  helperText?: string;
  fieldRef?: (el: HTMLDivElement | null) => void;
  errorText?: string;
}) {
  return (
    <div ref={fieldRef} className={disabled ? "opacity-50" : ""}>
      <p className="text-[13px] font-medium text-gray-700 mb-2 leading-relaxed">
        {title} {required && <span className="text-emerald-600">*</span>}
      </p>
      {helperText && <p className="mb-2 text-[12px] text-gray-400">{helperText}</p>}
      <div className={`grid gap-2 ${compact ? "grid-cols-2 sm:grid-cols-3" : "grid-cols-1"}`}>
{options.map((opt) => {
  const selected = value === opt.value;
  const Icon = opt.icon;
  return (
    <button
      key={opt.value}
      type="button"
      disabled={disabled}
      onClick={() => onChange(opt.value)}
      className={choiceBtnClass(selected, disabled)}
    >
      {Icon ? (
        <span className="flex w-full flex-col items-center gap-1.5 text-center">
          <Icon
            aria-hidden="true"
            className={`h-6 w-6 transition-colors duration-150 ${
              selected ? opt.iconTone ?? "text-emerald-600" : "text-gray-400"
            }`}
          />
          {opt.label}
        </span>
      ) : (
        opt.label
      )}
    </button>
  );
})}
      </div>
      {errorText && <p className="mt-1.5 text-[12px] text-red-600">{errorText}</p>}
    </div>
  );
}

export default RadioGroup;
