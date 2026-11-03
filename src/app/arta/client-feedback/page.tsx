//src/app/arta/client-feedback/[officeSlug]/page.tsx

import type { Metadata } from "next";
import CSMForm from "@/components/arta/client-feedback/CSMForm";

export const metadata: Metadata = {
  title: "Client Feedback | San Pablo City",
  description:
    "Client Satisfaction Measurement (CSM) — share feedback on your recently concluded transaction with the City Government of San Pablo.",
};

export default function ClientFeedbackPage() {
  return (
    <main className="min-h-screen bg-gray-50/60 px-4 py-8 sm:py-12">

      <CSMForm />
    </main>
  );
}