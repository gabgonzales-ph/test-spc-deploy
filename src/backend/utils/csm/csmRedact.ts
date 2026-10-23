// Masks emails and phone numbers in free text. Pure, no dependencies.
// Names and other identifiers are NOT detected (known limitation in the plan).
// Errs toward masking: a wrongly masked number costs readability, a missed one costs privacy.

export const EMAIL_PLACEHOLDER = "[email]";
export const PHONE_PLACEHOLDER = "[phone]";

const EMAIL_RE =
  /[A-Z0-9._%+-]+@[A-Z0-9-]+(?:\.[A-Z0-9-]+)*\.[A-Z]{2,}/gi;

// Runs of digits with common separators: 09171234567, 0917 123 4567,
// +63 917 123 4567, (049) 561-1234, 561-1234.
const PHONE_CANDIDATE_RE = /(?<!\w)\+?\(?\d[\d\s().-]{5,}\d(?!\w)/g;

// Number-like text that is not a phone number.
const SAFE_NUMBER_RES = [
  /^\d{4}-\d{2}-\d{1,3}-\d{3,}$/,        // control numbers (YYYY-MM-OO-NNN)
  /^\d{4}-\d{2}-\d{2}$/,                 // ISO dates
  /^\d{1,2}[-.]\d{1,2}[-.]\d{2,4}$/,     // 10-23-2026
  /^\d{4}\s*-\s*\d{4}$/,                 // year ranges (2026-2027)
];

const MIN_PHONE_DIGITS = 7; // shortest local landline

export function redactContactDetails(
  input: string | null | undefined,
): string | null {
  if (input == null) return null;
  return input
    .replace(EMAIL_RE, EMAIL_PLACEHOLDER)
    .replace(PHONE_CANDIDATE_RE, (match) => {
      if (SAFE_NUMBER_RES.some((re) => re.test(match))) return match;
      const digits = match.replace(/\D/g, "").length;
      return digits >= MIN_PHONE_DIGITS ? PHONE_PLACEHOLDER : match;
    });
}