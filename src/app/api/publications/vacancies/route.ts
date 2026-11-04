// src/app/api/publications/vacancies/route.ts

import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { downloadUrl } from "@/lib/download/fileToken";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

export async function GET() {
  const { data, error } = await supabase
    .from("publications")
    .select("publication_id, filename, file_path, created_at")
    .eq("is_archived", false)
    .order("created_at", { ascending: false })
    .limit(500);

  if (error) {
    console.error("Failed to load vacancies:", error.message);
    return NextResponse.json({ error: "Failed to load vacancies" }, { status: 500 });
  }

  const items = (data ?? []).map(({ file_path, ...rest }) => ({
    ...rest,
    pdf_url: file_path ? downloadUrl(file_path) : null,
  }));

  return NextResponse.json(items);
}