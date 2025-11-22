/**
 * Admin Export API
 * Export waitlist data as CSV
 */

interface ExportContact {
  id: number;
  email: string;
  name: string | null;
  email_status: string;
  tier: string;
  score: number;
  referrals_count: number;
  invite_code: string;
  referral_code: string | null;
  referral_source: string | null;
  verified_at: string | null;
  created_at: string;
  position?: number;
}

/**
 * Convert data to CSV format
 */
function convertToCSV(data: ExportContact[]): string {
  // CSV Headers
  const headers = [
    'Position',
    'Email',
    'Name',
    'Status',
    'Tier',
    'Score',
    'Referrals',
    'Invite Code',
    'Referral Code Used',
    'Referral Source',
    'Verified At',
    'Signed Up At',
  ];

  // Build CSV rows
  const rows = data.map((contact) => [
    contact.position || '',
    contact.email,
    contact.name || '',
    contact.email_status,
    contact.tier,
    contact.score,
    contact.referrals_count,
    contact.invite_code,
    contact.referral_code || '',
    contact.referral_source || '',
    contact.verified_at || '',
    contact.created_at,
  ]);

  // Combine headers and rows
  const csvContent = [
    headers.join(','),
    ...rows.map((row) =>
      row
        .map((cell) => {
          // Escape commas and quotes in cell values
          const cellStr = String(cell);
          if (cellStr.includes(',') || cellStr.includes('"') || cellStr.includes('\n')) {
            return `"${cellStr.replace(/"/g, '""')}"`;
          }
          return cellStr;
        })
        .join(',')
    ),
  ].join('\n');

  return csvContent;
}

/**
 * GET /admin/api/export - Export contacts as CSV
 */
export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { request, env } = context;
  const url = new URL(request.url);

  // Parse query parameters
  const format = url.searchParams.get('format') || 'csv';
  const status = url.searchParams.get('status') || '';
  const tier = url.searchParams.get('tier') || '';

  // Validate format
  if (format !== 'csv') {
    return Response.json({ error: 'Only CSV format is supported' }, { status: 400 });
  }

  try {
    // Build query with filters
    const conditions: string[] = [];
    const bindings: any[] = [];

    if (status) {
      conditions.push('email_status = ?');
      bindings.push(status);
    }

    if (tier) {
      conditions.push('tier = ?');
      bindings.push(tier);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    // Fetch all contacts matching criteria
    const query = `
      SELECT
        id,
        email,
        name,
        email_status,
        tier,
        score,
        referrals_count,
        invite_code,
        referral_code,
        referral_source,
        verified_at,
        created_at
      FROM waitlist
      ${whereClause}
      ORDER BY score DESC, created_at ASC
    `;

    const result = await env.WAITLIST_DB.prepare(query)
      .bind(...bindings)
      .all<ExportContact>();

    const contacts = result.results || [];

    // Calculate positions for verified contacts
    let position = 1;
    for (const contact of contacts) {
      if (contact.email_status === 'verified') {
        contact.position = position++;
      }
    }

    // Convert to CSV
    const csvContent = convertToCSV(contacts);

    // Generate filename with timestamp
    const timestamp = new Date().toISOString().split('T')[0];
    const filename = `trendsight-waitlist-${timestamp}.csv`;

    // Return CSV file
    return new Response(csvContent, {
      headers: {
        'Content-Type': 'text/csv',
        'Content-Disposition': `attachment; filename="${filename}"`,
      },
    });
  } catch (error) {
    console.error('Export error:', error);
    return Response.json(
      { error: 'Failed to export contacts' },
      { status: 500 }
    );
  }
};
