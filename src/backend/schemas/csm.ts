
import { isValidContactNo } from '@/lib/csm/csmContact'
import { z } from 'zod'

// SQD0-SQD8 ratings, stored as the literal phrase (not a numeric code).
const sqdRating = z.enum([
  'Strongly Disagree',
  'Disagree',
  'Neither Agree nor Disagree',
  'Agree',
  'Strongly Agree',
  'Not Applicable',
])

export const CsmResponseSchema = z.object({
  language: z.enum(['en', 'tl']).optional(),
  officeId:         z.string().uuid({ message: 'An office must be selected' }),
  clientType:       z.enum(['citizen', 'business', 'government']),
  transactionDate:  z.string().min(1, 'Date is required'), // ISO date string, e.g. 2026-08-04
  sex:              z.enum(['male', 'female']).optional(),
  age:              z.number().int().min(1).max(129).optional(),
  region:           z.string().min(1, 'Region is required'),
  service:          z.string().min(1, 'Service availed is required').max(255),

  // CC1 is always 1-4. CC2 is 1-5 (5 = N/A), CC3 is 1-4 (4 = N/A) — the
  // client auto-sets both to their N/A code when CC1 = 4; the server just
  // validates the ranges.
  cc1: z.number().int().min(1).max(4),
  cc2: z.number().int().min(1).max(5),
  cc3: z.number().int().min(1).max(4),

  sqd0: sqdRating,
  sqd1: sqdRating,
  sqd2: sqdRating,
  sqd3: sqdRating,
  sqd4: sqdRating,
  sqd5: sqdRating,
  sqd6: sqdRating,
  sqd7: sqdRating,
  sqd8: sqdRating,

  comments:     z.string().max(1000).optional().or(z.literal('')),
  emailAddress: z.string().email().max(100).optional().or(z.literal('')),
  clientName: z.string().max(200).optional(),
contactNo:  z
  .string()
  .max(50)
  .refine((v) => v.trim() === '' || isValidContactNo(v.trim()), 'Invalid contact number')
  .optional(),
})

export type CsmResponseInput = z.infer<typeof CsmResponseSchema>