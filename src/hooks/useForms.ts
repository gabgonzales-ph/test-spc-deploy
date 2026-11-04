//spc-website\src\hooks\useForms.ts

import { useCallback } from 'react'
import { useApi, apiRequest } from './useCore'

export type FormCategory =
  | 'business-permits-licensing'
  | 'city-planning-development'
  | 'building-official'
  | 'civil-society-organizations'
  | 'senior-citizens-affairs'

export interface FormDocument {
  id:            number
  category:      FormCategory
  title:         string
  date_issued:   string | null
  year:          number | null
  pdf_url:       string | null
  status:        'active' | 'archived'
  created_at:    string
}
export function useGetPublicForms() {
  const apiFunction = useCallback(async (params?: {
    page?:     number
    limit?:    number
    category?: FormCategory
    year?:     string
    search?:   string
  }) => {
    const q = new URLSearchParams()
    if (params?.page)     q.append('page',     String(params.page))
    if (params?.limit)    q.append('limit',    String(params.limit))
    if (params?.category) q.append('category', params.category)
    if (params?.year)     q.append('year',     params.year)
    if (params?.search)   q.append('search',   params.search)
    return apiRequest(`/forms/public?${q.toString()}`)
  }, [])
  return useApi(apiFunction)
}