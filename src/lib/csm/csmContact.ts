const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_CHARS_RE = /^[0-9+\-()\s]+$/;

// Returns the trimmed value, or null when blank.
export const cleanOptional = (v: string | undefined | null) => {
  const s = (v ?? "").trim();
  return s === "" ? null : s;
};

export const isValidEmail = (v: string) => v.length <= 254 && EMAIL_RE.test(v);

export const isValidContactNo = (v: string) => {
  if (!PHONE_CHARS_RE.test(v)) return false;
  const digits = v.replace(/\D/g, "").length;
  return digits >= 7 && digits <= 12 && v.length <= 50;
};

export const MAX_CONTACT_DIGITS = 12;

// Keeps only allowed characters and stops accepting digits after the cap.
export const sanitizeContactNo = (v: string) => {
  let digits = 0;
  let out = "";
  for (const ch of v.replace(/[^0-9+\-()\s]/g, "")) {
    if (/\d/.test(ch)) {
      if (digits >= MAX_CONTACT_DIGITS) continue;
      digits++;
    }
    out += ch;
  }
  return out.slice(0, 50);
};