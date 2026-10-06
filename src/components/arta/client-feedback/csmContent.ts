import type { ClientType, FormState, Lang, Sex } from "./types";
import { Angry, Ban, Frown, Laugh, Meh, Smile, type LucideIcon } from "lucide-react";

export const todayIso = () => new Date().toISOString().slice(0, 10);

export const initialState: FormState = {
  clientType: "",
  transactionDate: todayIso(),
  sex: "",
  age: "",
  region: "",
  service: "",
  cc1: null,
  cc2: null,
  cc3: null,
  sqd0: null,
  sqd1: null,
  sqd2: null,
  sqd3: null,
  sqd4: null,
  sqd5: null,
  sqd6: null,
  sqd7: null,
  sqd8: null,
  comments: "",
  emailAddress: "",
};

export const PSGC_BASE = "/api/psgc";

export function extractArray<T>(json: unknown): T[] {
  if (Array.isArray(json)) return json as T[];
  if (json && typeof json === "object" && Array.isArray((json as any).data)) {
    return (json as any).data as T[];
  }
  return [];
}

export const CC2_NA_VALUE = 5;
export const CC3_NA_VALUE = 4;

// ---------------------------------------------------------------------
// Bilingual content
// ---------------------------------------------------------------------
export const CONTENT: Record<
  Lang,
  {
    orgLabel: string;
    appTitle: string;
    appDesc: string;
    steps: [string, string, string, string];
    clientTypeLabel: string;
    clientTypes: Record<ClientType, string>;
    dateLabel: string;
    sexLabel: string;
    sexOptions: Record<Sex, string>;
    optionalTag: string;
    ageLabel: string;
    agePlaceholder: string;
    regionLabel: string;
    regionPlaceholder: string;
    regionLoading: string;
    serviceLabel: string;
    servicePlaceholder: string;
    serviceNoOfficeMsg: string;
    serviceNoneMsg: string;
    ccIntro: string;
    cc1Title: string;
    cc1Options: string[];
    cc2Title: string;
    cc2Options: string[];
    cc3Title: string;
    cc3Options: string[];
    naNote: string;
    sqdIntro: string;
    sqdItems: string[];
    sqdOptions: string[];
    commentsLabel: string;
    commentsPlaceholder: string;
    emailLabel: string;
    emailPlaceholder: string;
    backBtn: string;
    nextBtn: string;
    submitBtn: string;
    sendingBtn: string;
    successTitle: string;
    successMsg: string;
    pdfFailedNote: string;
    redirectMsg: string;
    errClientType: string;
    errDate: string;
    errRegion: string;
    errService: string;
    errAge: string;
    errCc1: string;
    errCc2: string;
    errCc3: string;
    errSqd: string;
    errEmail: string;
    errGeneric: string;
  }
> = {
  en: {
    orgLabel: "City Government of San Pablo",
    appTitle: "Help Us Serve You Better!",
    appDesc:
      "This Client Satisfaction Measurement (CSM) tracks the customer experience of government offices. Your feedback on your recently concluded transaction will help this office provide a better service. Personal information shared will be kept confidential and you always have the option to not answer this form.",
    steps: ["Respondent Info", "Citizen's Charter", "Service Quality", "Feedback"],
    clientTypeLabel: "Client type",
    clientTypes: { citizen: "Citizen", business: "Business", government: "Government" },
    dateLabel: "Date",
    sexLabel: "Sex",
    sexOptions: { male: "Male", female: "Female" },
    optionalTag: "(optional)",
    ageLabel: "Age",
    agePlaceholder: "e.g. 34",
    regionLabel: "Region of Residence",
    regionPlaceholder: "Select region",
    regionLoading: "Loading regions...",
    serviceLabel: "Service Availed",
    servicePlaceholder: "Select a service",
    serviceNoOfficeMsg: "Select an office first",
    serviceNoneMsg: "No services listed for this office",
    ccIntro:
      "Please select the answer that corresponds to your experience with this office's Citizen's Charter (CC) — an official document reflecting the office's services, requirements, fees, and processing times.",
    cc1Title: "CC1. Which of the following best describes your awareness of a CC?",
    cc1Options: [
      "I know what a CC is and I saw this office's CC.",
      "I know what a CC is but I did NOT see this office's CC.",
      "I learned of the CC only when I saw this office's CC.",
      "I do not know what a CC is and I did not see one in this office.",
    ],
    cc2Title: "CC2. If aware of CC, would you say that the CC of this office was...?",
    cc2Options: ["Easy to see", "Somewhat easy to see", "Difficult to see", "Not visible at all", "Not Applicable"],
    cc3Title: "CC3. If aware of CC, how much did the CC help you in your transaction?",
    cc3Options: ["Helped very much", "Somewhat helped", "Did not help", "Not Applicable"],
    naNote: "Not applicable — marked automatically.",
    sqdIntro: "For SQD0–8, please select the rating that best corresponds to your answer.",
    sqdItems: [
      "I am satisfied with the service that I availed.",
      "I spent a reasonable amount of time for my transaction.",
      "The office followed the transaction's requirements and steps based on the information provided.",
      "The steps (including payment) I needed to do for my transaction were easy and simple.",
      "I easily found information about my transaction from the office or its website.",
      "I paid a reasonable amount of fees for my transaction. (If service was free, mark the 'N/A' column)",
      "I feel the office was fair to everyone, or \u201Cwalang palakasan\u201D, during my transaction.",
      "I was treated courteously by the staff, and (if asked for help) the staff was helpful.",
      "I got what I needed from the government office, or (if denied) denial of request was sufficiently explained to me.",
    ],
    sqdOptions: ["Strongly Disagree", "Disagree", "Neither Agree nor Disagree", "Agree", "Strongly Agree", "Not Applicable"],
    commentsLabel: "Suggestions on how we can further improve our services",
    commentsPlaceholder: "Tell us how we can do better...",
    emailLabel: "Email address",
    emailPlaceholder: "juan@email.com",
    backBtn: "Back",
    nextBtn: "Next",
    submitBtn: "Submit and Download Form",
    sendingBtn: "Sending...",
    successTitle: "Feedback sent successfully",
    successMsg: "Thank you for helping us serve you better.",
    pdfFailedNote:
      "Your feedback was saved, but we couldn't generate your copy of the form. No action is needed on your part.",
    redirectMsg: "You can leave this page now.",
    errClientType: "Please select a client type.",
    errDate: "Please select the transaction date.",
    errRegion: "Please select your region of residence.",
    errService: "Please select the service you availed.",
    errAge: "Please enter a valid age.",
    errCc1: "Please answer CC1.",
    errCc2: "Please answer CC2.",
    errCc3: "Please answer CC3.",
    errSqd: "Please rate all service quality statements.",
    errEmail: "Please enter a valid email address.",
    errGeneric: "Something went wrong. Please try again.",
  },
  tl: {
    orgLabel: "Pamahalaan ng Lungsod ng San Pablo",
    appTitle: "Tulungan Kami na Paglingkuran Kayo nang Mas Mabuti!",
    appDesc:
      "Sinusubaybayan ng Client Satisfaction Measurement (CSM) na ito ang karanasan ng mga mamamayan sa mga tanggapan ng pamahalaan. Ang inyong puna sa transaksyong kaka-tapos lamang ay makakatulong sa tanggapang ito upang magbigay ng mas mahusay na serbisyo. Ang personal na impormasyong ibinahagi ay mananatiling kumpidensyal at may karapatan kayo na hindi sagutin ang bahaging ito.",
    steps: ["Impormasyon", "Citizen's Charter", "Kalidad ng Serbisyo", "Puna"],
    clientTypeLabel: "Uri ng kliyente",
    clientTypes: { citizen: "Mamamayan", business: "Negosyo", government: "Pamahalaan" },
    dateLabel: "Petsa",
    sexLabel: "Kasarian",
    sexOptions: { male: "Lalaki", female: "Babae" },
    optionalTag: "(opsyonal)",
    ageLabel: "Edad",
    agePlaceholder: "hal. 34",
    regionLabel: "Rehiyon ng paninirahan",
    regionPlaceholder: "Pumili ng rehiyon",
    regionLoading: "Ikinakarga ang mga rehiyon...",
    serviceLabel: "Serbisyong natanggap",
    servicePlaceholder: "Pumili ng serbisyo",
    serviceNoOfficeMsg: "Pumili muna ng tanggapan",
    serviceNoneMsg: "Walang nakalistang serbisyo para sa tanggapang ito",
    ccIntro:
      "Piliin ang sagot na tumutugma sa inyong karanasan sa Citizen's Charter (CC) ng tanggapang ito — isang opisyal na dokumento na naglalaman ng mga serbisyo, kinakailangan, bayad, at oras ng pagproseso ng tanggapan.",
    cc1Title: "CC1. Alin sa mga sumusunod ang naglalarawan sa inyong kaalaman tungkol sa CC?",
    cc1Options: [
      "Alam ko kung ano ang CC at nakita ko ang CC ng tanggapang ito.",
      "Alam ko kung ano ang CC ngunit HINDI ko nakita ang CC ng tanggapang ito.",
      "Nalaman ko lamang ang tungkol sa CC nang makita ko ang CC ng tanggapang ito.",
      "Hindi ko alam kung ano ang CC at wala akong nakita nito sa tanggapang ito.",
    ],
    cc2Title: "CC2. Kung alam ninyo ang CC, masasabi ba ninyong ang CC ng tanggapang ito ay...?",
    cc2Options: ["Madaling makita", "Medyo madaling makita", "Mahirap makita", "Hindi talaga makita", "Hindi Aplikable"],
    cc3Title: "CC3. Kung alam ninyo ang CC, gaano ito nakatulong sa inyong transaksyon?",
    cc3Options: ["Malaking tulong", "May kaunting tulong", "Hindi nakatulong", "Hindi Aplikable"],
    naNote: "Hindi aplikable — awtomatikong minarkahan.",
    sqdIntro: "Para sa SQD0–8, piliin ang sagot na pinakatumutugma sa inyong karanasan.",
    sqdItems: [
      "Nasisiyahan ako sa serbisyong aking natanggap.",
      "Naglaan ako ng makatwirang oras para sa aking transaksyon.",
      "Sinunod ng tanggapan ang mga kinakailangan at hakbang ng transaksyon batay sa ibinigay na impormasyon.",
      "Ang mga hakbang (kasama ang pagbabayad) na kailangan ko para sa aking transaksyon ay madali at simple.",
      "Madali kong nahanap ang impormasyon tungkol sa aking transaksyon mula sa tanggapan o sa kanilang website.",
      "Nagbayad ako ng makatwirang halaga ng bayad para sa aking transaksyon. (Kung libre ang serbisyo, markahan ang 'N/A')",
      "Naramdaman kong patas ang tanggapan sa lahat, o \u201Cwalang palakasan\u201D, sa aking transaksyon.",
      "Magalang akong pinakitunguhan ng kawani, at (kung humingi ng tulong) ang kawani ay nakatulong.",
      "Natanggap ko ang aking kailangan mula sa tanggapan ng pamahalaan, o (kung tinanggihan) sapat na ipinaliwanag ang dahilan ng pagtanggi.",
    ],
    sqdOptions: [
      "Lubos na Hindi Sumasang-ayon",
      "Hindi Sumasang-ayon",
      "Hindi Sumasang-ayon o Sumasang-ayon",
      "Sumasang-ayon",
      "Lubos na Sumasang-ayon",
      "Hindi Aplikable",
    ],
    commentsLabel: "Mungkahi kung paano pa namin mapapahusay ang aming serbisyo",
    commentsPlaceholder: "Sabihin sa amin kung paano kami makakapagpabuti...",
    emailLabel: "Email address",
    emailPlaceholder: "juan@email.com",
    backBtn: "Bumalik",
    nextBtn: "Susunod",
    submitBtn: "Ipasa at I-download ang Form",
    sendingBtn: "Ipinapadala...",
    successTitle: "Matagumpay na naipadala ang puna",
    successMsg: "Salamat sa pagtulong sa amin na maglingkod nang mas mabuti.",
    pdfFailedNote:
      "Naisave ang inyong puna, ngunit hindi namin nagawang buuin ang kopya ng form. Walang kailangan pang gawin sa inyong panig.",
    redirectMsg: "Maaari ka nang umalis sa page na ito.",
    errClientType: "Piliin ang uri ng kliyente.",
    errDate: "Piliin ang petsa ng transaksyon.",
    errRegion: "Piliin ang rehiyon ng inyong paninirahan.",
    errService: "Piliin ang serbisyong inyong natanggap.",
    errAge: "Maglagay ng tamang edad.",
    errCc1: "Sagutan ang CC1.",
    errCc2: "Sagutan ang CC2.",
    errCc3: "Sagutan ang CC3.",
    errSqd: "Markahan lahat ng SQD statements.",
    errEmail: "Maglagay ng wastong email address.",
    errGeneric: "May naganap na error. Subukan muli.",
  },
};

// The literal phrases stored on submit are always the English canonical
// values (matches the DB CHECK constraint / Zod enum), regardless of the
// language the respondent answered in. sqdOptions above is display-only;
// SQD_CANONICAL maps a display index back to its English phrase.
export const SQD_CANONICAL = [
  "Strongly Disagree",
  "Disagree",
  "Neither Agree nor Disagree",
  "Agree",
  "Strongly Agree",
  "Not Applicable",
] as const;

// Display order for SQD choices: Strongly Agree → Strongly Disagree, with
// "Not Applicable" kept last. Rendering only; each option keeps its original
// value, so stored answers and the PDF mapping are unchanged.
export const orderSqdOptions = <T>(options: T[]): T[] => [
  ...options.slice(0, 5).reverse(),
  ...options.slice(5),
];

// Icon + selected-state color per SQD option, keyed by the ORIGINAL option
// index (0 = Strongly Disagree ... 5 = Not Applicable). Keyed by index so it
// stays correct after reordering and in both languages.
export const SQD_ICONS: { icon: LucideIcon; tone: string }[] = [
  { icon: Angry, tone: "text-red-500" },      // 0 Strongly Disagree
  { icon: Frown, tone: "text-orange-500" },   // 1 Disagree
  { icon: Meh,   tone: "text-amber-500" },    // 2 Neither
  { icon: Smile, tone: "text-lime-600" },     // 3 Agree
  { icon: Laugh, tone: "text-emerald-600" },  // 4 Strongly Agree
  { icon: Ban,   tone: "text-gray-500" },     // 5 Not Applicable
];

export const fadeInUp = {
  hidden: { opacity: 0, y: 24 },
  visible: { opacity: 1, y: 0 },
};

export const staggerContainer = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.12 } },
};

export const inputClass =
  "w-full rounded-lg border border-gray-200 px-3.5 py-2.5 text-[14px] text-gray-900 placeholder:text-gray-400 outline-none transition-colors focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 disabled:bg-gray-50 disabled:text-gray-400 disabled:cursor-not-allowed";

// Shared hover/selection treatment for all choice buttons — subtle lift +
// tint on hover, stronger emerald fill when selected.
export const choiceBtnClass = (selected: boolean, disabled?: boolean) =>
  `text-left rounded-sm border px-3 py-4 text-[12.5px] leading-snug transition-all duration-150 ease-out disabled:cursor-not-allowed disabled:hover:translate-y-0 disabled:hover:shadow-none ${
    selected
      ? "border-emerald-600 bg-emerald-50 text-emerald-800 font-medium shadow-sm"
      : "border-gray-200 text-gray-600 hover:border-emerald-300 hover:bg-emerald-50/60 hover:text-emerald-800 hover:-translate-y-0.5 hover:shadow-sm"
  } ${disabled ? "opacity-50" : ""}`;