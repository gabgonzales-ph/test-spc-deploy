// ---------------------------------------------------------------------
// Shared types for the CSM (Client Satisfaction Measurement) form
// ---------------------------------------------------------------------

export interface PsgcOption {
  code: string;
  name: string;
}

export interface Office {
  id: string;
  name: string;
  slug: string;
  sector?: string | null;
  services?: string[] | null;
}

export interface CSMFormProps {
  // Set when rendered from /arta/client-feedback/[officeSlug]. When absent
  // (base /arta/client-feedback route), the splash still renders but shows
  // an "unavailable" message instead of the office selector / language
  // buttons — there is no dropdown picker anymore.
  officeSlug?: string;
}

export type ClientType = "citizen" | "business" | "government";
export type Sex = "male" | "female";
export type Lang = "en" | "tl";
export type SubmitStatus = "idle" | "submitting" | "success" | "error";

export interface FormState {
  clientType: ClientType | "";
  transactionDate: string; // yyyy-mm-dd
  sex: Sex | "";
  age: string;
  region: string; // region NAME is what's stored, per spec
  service: string;
  clientName: string;
contactNo: string;

  cc1: number | null;
  cc2: number | null;
  cc3: number | null;

  sqd0: string | null;
  sqd1: string | null;
  sqd2: string | null;
  sqd3: string | null;
  sqd4: string | null;
  sqd5: string | null;
  sqd6: string | null;
  sqd7: string | null;
  sqd8: string | null;

  comments: string;
  emailAddress: string;
}

export interface FieldError {
  field: string;
  message: string;
}
