export type DisclosureCategory =
  | 'city-ordinance'
  | 'city-resolution'
  | 'executive-order'
  | 'bids-awards'
  | 'financial-aid'

export interface DisclosureDocument {
  document_id:   number
  category:      DisclosureCategory
  title:         string
  date_passed:   string | null
  year:          number | null
  pdf_url:       string | null
  status:        'active' | 'repealed'
  created_at:    string
}