// src/lib/download/downloadName.ts
// SERVER ONLY. Decides the filename a browser sees when it opens or saves a PDF.
//
// NOW: uses the file's own name (the random ID).
// LATER: when the `title` column exists, change ONLY getDownloadName() below.
// Tokens, URLs and cached links stay the same.

export async function getDownloadName(filePath: string): Promise<string> {
  // TODO (after the title column is added): look the title up by file_path, e.g.
  //
  //   import { supabase } from "@/backend/config/database";
  //   const { data } = await supabase
  //     .from("forms")
  //     .select("title")
  //     .eq("file_path", filePath)
  //     .maybeSingle();
  //   if (data?.title) return `${data.title}.pdf`;
  //
  return filePath.split("/").pop() || "document.pdf";
}

/**
 * Builds a safe Content-Disposition value.
 * - `filename` is an ASCII fallback (quotes, slashes and non-ASCII removed).
 * - `filename*` carries the full UTF-8 name (keeps "ñ" etc.) per RFC 5987.
 */
export function contentDisposition(name: string, type: "inline" | "attachment" = "inline"): string {
  const base = name.replace(/\.pdf$/i, "");

  const ascii =
    base
      .normalize("NFKD")
      .replace(/[̀-ͯ]/g, "") // "ñ" -> "n"
      .replace(/[^\w\-. ]+/g, "")
      .trim()
      .replace(/\s+/g, "-") || "document";

  const utf8 = encodeURIComponent(base.replace(/[\r\n"\\/]/g, "").trim() || "document");

  return `${type}; filename="${ascii}.pdf"; filename*=UTF-8''${utf8}.pdf`;
}
