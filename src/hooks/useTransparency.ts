//src/hooks/useTransparency.ts

import { useCallback } from 'react';
import { useApi, apiRequest } from './useCore';

export type TransparencyCategory =
  | 'city-ordinance-&-resolution'
  | 'executive-order'
  | 'bids-awards'
  | 'financial-aid'
  | 'full-disclosure'

export interface TransparencyDocument {
  document_id:   number
  category:      TransparencyCategory
  title:         string
  date_passed:   string | null
  year:          number | null
  pdf_url:       string | null
  status:        'active' | 'repealed'
  created_at:    string
}

export function useGetPublicTransparency() {
  const apiFunction = useCallback(async (params?: {
    page?:     number
    limit?:    number
    category?: TransparencyCategory
    year?:     string
    search?:   string
  }) => {
    const q = new URLSearchParams()
    if (params?.page)     q.append('page',     String(params.page))
    if (params?.limit)    q.append('limit',    String(params.limit))
    if (params?.category) q.append('category', params.category)
    if (params?.year)     q.append('year',     params.year)
    if (params?.search)   q.append('search',   params.search)
    return apiRequest(`/transparency/public?${q.toString()}`)
  }, [])
  return useApi(apiFunction)
}