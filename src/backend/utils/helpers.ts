//src/backend/utils/helpers.ts

import { PaginationResponse } from '@/backend/types/PaginationResponse';

export function formatPaginationResponse<T>({
  data,
  page,
  limit,
  total,
}: {
  data: T[];
  page: number;
  limit: number;
  total: number;
}): PaginationResponse<T> {
  const totalPages = Math.ceil(total / limit);
  const hasNext = page < totalPages;
  const hasPrevious = page > 1;

  return {
    success: true,
    data,
    pagination: {
      page,
      limit,
      total,
      totalPages,
      hasNext,
      hasPrevious,
    },
  };
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

/**
 * Converts a relative Storage path (e.g. "media/articles/foo.webp")
 * into a full public URL against the currently configured Supabase project.
 * If the value is already a full URL (legacy data, or non-Supabase source),
 * it's returned unchanged so old rows don't break before they're normalized.
 */
export function getPublicMediaUrl(filePath: string | null | undefined): string | null {
  if (!filePath) return null;
  if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
    return filePath; // already a full URL, leave as-is
  }
  if (!SUPABASE_URL) {
    console.error('NEXT_PUBLIC_SUPABASE_URL is not set — media URLs cannot be built');
    return null;
  }
  return `${SUPABASE_URL}/storage/v1/object/public/${filePath}`;
}