// scripts/test-csm-pdf.ts
//
// Standalone coordinate-tuning harness. Two modes:
//
//   npx tsx scripts/test-csm-pdf.ts             -> realistic single submission
//   npx tsx scripts/test-csm-pdf.ts --calibrate  -> EVERY checkbox checked at once
//
// Calibrate mode ignores real-world constraints (e.g. only one client type is
// ever actually selected) and stamps a checkmark on all 54 checkbox
// coordinates simultaneously, so you can eyeball every position in one PDF
// instead of one option at a time. Use this while trial-and-error tuning
// csmPdfCoordinates.ts.
//
// No form submission, no DB insert — calls the PDF service directly.
//
// (npx tsx works without adding a permanent dependency; swap for
// `bun run scripts/test-csm-pdf.ts` if you'd rather match the app's runtime.)

import { writeFileSync } from "fs";
import {
  generateCsmPdf,
  generateCalibrationPdf,
  type CsmResponseForPdf,
} from "../src/backend/utils/csm/csmPdfService";

const mockResponse: CsmResponseForPdf = {
  control_no: "2026-08-0123",
  client_type: "citizen",
  transaction_date: "2026-08-07",
  sex: "female",
  age: 28,
  region: "Region IV-A (CALABARZON)",
  service: "Preventive Maintenance of Computer Hardware",
  office_name: "Office of the Sangguniang Panlungsod, Library",
  cc1: 1,
  cc2: 1,
  cc3: 1,
  sqd0: "Strongly Agree",
  sqd1: "Agree",
  sqd2: "Strongly Agree",
  sqd3: "Neither Agree nor Disagree",
  sqd4: "Disagree",
  sqd5: "Not Applicable",
  sqd6: "Strongly Agree",
  sqd7: "Agree",
  sqd8: "Strongly Agree",
  comments:
    "This is a long sample comment used to check word-wrapping and dynamic font shrinking inside the suggestions box on the template. Adjust this string to test edge cases like the full 1000-character limit.",
  email_address: "test.user@example.com",
};

async function main() {
  const calibrate = process.argv.includes("--calibrate");
  const pdfBytes = calibrate ? await generateCalibrationPdf() : await generateCsmPdf(mockResponse);
  const outPath = calibrate ? "csm-calibration-output.pdf" : "csm-test-output.pdf";
  writeFileSync(outPath, pdfBytes);
  console.log(`Wrote ${outPath} (${pdfBytes.length} bytes)${calibrate ? " [calibration: all checkboxes marked]" : ""}`);
}

main().catch((err) => {
  console.error("PDF generation failed:", err);
  process.exit(1);
});