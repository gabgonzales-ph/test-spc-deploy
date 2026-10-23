import { Elysia } from 'elysia'
import { supabase } from '@/backend/config/database'
import { errorHandler, throwValidationError } from '@/backend/utils/error'
import { CsmResponseSchema } from '@/backend/schemas/csm'
import {
  generateCsmPdf,
  type CsmResponseForPdf,
} from '@/backend/utils/csm/csmPdfService'
import { redactContactDetails } from '@/backend/utils/csm/csmRedact'

// Shape returned by the insert_csm_response() Postgres function.
type CsmResponseRow = {
  id: number
  control_no: string
  office_name: string | null
}

export const csmRoutes = new Elysia({ prefix: '/csm-response' })
  .use(errorHandler)

  .post('/', async ({ body, set }) => {
    const parsed = CsmResponseSchema.safeParse(body)

    if (!parsed.success) {
      throwValidationError(
        'Invalid CSM submission',
        parsed.error.flatten(),
      )
    }

    // Narrow for TypeScript.
    if (!parsed.success) throw new Error('unreachable')

    const input = parsed.data

    // Mask emails and phone numbers; slice after redaction because placeholders can add a character.
    const comments =
      redactContactDetails(input.comments)?.trim().slice(0, 1000) || null

    // Insert + control_no assignment happens atomically in a single Postgres function.
    const { data: inserted, error: insertError } = await supabase
      .rpc('insert_csm_response', {
        p_office_id: input.officeId,
        p_client_type: input.clientType,
        p_transaction_date: input.transactionDate,
        p_sex: input.sex ?? null,
        p_age: input.age ?? null,
        p_region: input.region,
        p_service: input.service,
        p_cc1: input.cc1,
        p_cc2: input.cc2,
        p_cc3: input.cc3,
        p_sqd0: input.sqd0,
        p_sqd1: input.sqd1,
        p_sqd2: input.sqd2,
        p_sqd3: input.sqd3,
        p_sqd4: input.sqd4,
        p_sqd5: input.sqd5,
        p_sqd6: input.sqd6,
        p_sqd7: input.sqd7,
        p_sqd8: input.sqd8,
        p_comments: comments,
        p_email_address: input.emailAddress || null,
      })
      .single()

    if (insertError || !inserted) {
      console.error('[csm-response] insert error:', insertError)

      if (
        insertError?.code === 'P0002' ||
        insertError?.code === '23503'
      ) {
        throwValidationError(
          'Selected office was not found. Please reload and try again.',
        )
      }

      throw new Error('Failed to save your response')
    }

    const row = inserted as CsmResponseRow
    const controlNo = row.control_no

    // Build the PDF data using the same redacted comments stored in the database.
    const pdfRow: CsmResponseForPdf = {
      control_no: controlNo,
      client_type: input.clientType,
      transaction_date: input.transactionDate,
      sex: input.sex ?? null,
      age: input.age ?? null,
      region: input.region,
      service: input.service,
      cc1: input.cc1,
      cc2: input.cc2,
      cc3: input.cc3,
      sqd0: input.sqd0,
      sqd1: input.sqd1,
      sqd2: input.sqd2,
      sqd3: input.sqd3,
      sqd4: input.sqd4,
      sqd5: input.sqd5,
      sqd6: input.sqd6,
      sqd7: input.sqd7,
      sqd8: input.sqd8,
      comments: comments,
      email_address: input.emailAddress || null,
      office_name: row.office_name ?? null,
    }

    try {
      const pdfBytes = await generateCsmPdf(pdfRow)
      const pdfBuffer = Buffer.from(pdfBytes)

      set.headers['Content-Type'] = 'application/pdf'
      set.headers['Content-Disposition'] =
        `attachment; filename="CSM-${controlNo}.pdf"`

      return new Response(pdfBuffer, {
        headers: {
          'Content-Type': 'application/pdf',
          'Content-Disposition':
            `attachment; filename="CSM-${controlNo}.pdf"`,
        },
      })
    } catch (pdfError) {
      // The response is already saved. PDF failure must not invalidate submission.
      console.error('[csm-response] PDF generation error:', pdfError)

      return {
        success: true,
        data: { id: row.id, controlNo },
        message: 'Thank you for your feedback.',
        pdfError: true,
      }
    }
  })