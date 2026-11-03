//src/app/arta/client-feedback/[officeSlug]/page.tsx

import type { Metadata } from "next";
import CSMForm from "@/components/arta/client-feedback/CSMForm";

export const metadata: Metadata = {
  title: "Client Feedback | San Pablo City",
  description:
    "Client Satisfaction Measurement (CSM) — share feedback on your recently concluded transaction with the City Government of San Pablo.",
};

export default async function ClientFeedbackOfficePage({
  params,
}: {
  params: Promise<{ officeSlug: string }>;
}) {
  const { officeSlug } = await params;

  return (
    // Below sm the form is full-screen: no page padding and a white background.
    <main className="min-h-screen bg-white sm:bg-gray-50/60 sm:px-4 sm:py-12">
      <CSMForm officeSlug={officeSlug} />
    </main>
  );
}