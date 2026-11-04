// src/backend/routes/forms.ts

import { Elysia } from 'elysia'
import { supabase } from '@/backend/config/database'
import { errorHandler } from '@/backend/utils/error'
import { formatPaginationResponse } from '@/backend/utils/helpers'
import { downloadUrl } from '@/lib/download/fileToken'

function getProxyUrl(filePath: string): string | null {
  if (!filePath) return null
  return downloadUrl(filePath)
}

function enrichDocument(doc: Record<string, unknown>) {
  const { file_url, ...rest } = doc
  return {
    ...rest,
    year: rest.date_issued
      ? new Date(rest.date_issued as string).getFullYear()
      : null,
    pdf_url: file_url ? getProxyUrl(file_url as string) : null,
  }
}

export const formsRoutes = new Elysia({ prefix: '/forms' })
  .use(errorHandler)

  .get('/public', async ({ query }) => {
    const page     = parseInt(query.page     as string) || 1
    const limit    = parseInt(query.limit    as string) || 200
    const category = query.category as string | undefined
    const year     = query.year     as string | undefined
    const search   = query.search   as string | undefined

    let countQuery = supabase
      .from('forms')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'active')

    if (category) countQuery = countQuery.eq('category', category)
    if (year)     countQuery = countQuery
      .gte('date_issued', `${year}-01-01`)
      .lte('date_issued', `${year}-12-31`)
    if (search)   countQuery = countQuery.ilike('title', `%${search}%`)

    const { count, error: countError } = await countQuery
    if (countError) throw new Error('Failed to fetch forms count')

    const from = (page - 1) * limit
    const to   = page * limit - 1

    let dataQuery = supabase
      .from('forms')
      .select('id, category, title, date_issued, file_url, status, created_at')
      .eq('status', 'active')
      .order('date_issued', { ascending: false })
      .range(from, to)

    if (category) dataQuery = dataQuery.eq('category', category)
    if (year)     dataQuery = dataQuery
      .gte('date_issued', `${year}-01-01`)
      .lte('date_issued', `${year}-12-31`)
    if (search)   dataQuery = dataQuery.ilike('title', `%${search}%`)

    const { data, error } = await dataQuery
    if (error) throw new Error('Failed to fetch forms')

    return formatPaginationResponse({
      data: (data || []).map(enrichDocument) as unknown[],
      page,
      limit,
      total: count || 0,
    })
  })