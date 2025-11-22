/**
 * Admin Contacts API
 * List, filter, and search waitlist contacts
 */

interface ContactsQuery {
  page?: number;
  limit?: number;
  status?: string;
  tier?: string;
  search?: string;
  sort?: 'score' | 'created_at' | 'email';
  order?: 'asc' | 'desc';
}

interface Contact {
  id: number;
  email: string;
  name: string | null;
  email_status: string;
  tier: string;
  score: number;
  referrals_count: number;
  invite_code: string;
  referral_source: string | null;
  verified_at: string | null;
  created_at: string;
  position?: number;
}

interface ContactsResponse {
  contacts: Contact[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    total_pages: number;
  };
}

/**
 * GET /admin/api/contacts - List contacts with filters
 */
export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { request, env } = context;
  const url = new URL(request.url);

  // Parse query parameters
  const query: ContactsQuery = {
    page: parseInt(url.searchParams.get('page') || '1'),
    limit: parseInt(url.searchParams.get('limit') || '50'),
    status: url.searchParams.get('status') || '',
    tier: url.searchParams.get('tier') || '',
    search: url.searchParams.get('search') || '',
    sort: (url.searchParams.get('sort') as 'score' | 'created_at' | 'email') || 'score',
    order: (url.searchParams.get('order') as 'asc' | 'desc') || 'desc',
  };

  // Validate pagination
  query.page = Math.max(1, query.page || 1);
  query.limit = Math.min(100, Math.max(1, query.limit || 50));

  try {
    // Build WHERE clause
    const conditions: string[] = [];
    const bindings: any[] = [];

    if (query.status) {
      conditions.push('email_status = ?');
      bindings.push(query.status);
    }

    if (query.tier) {
      conditions.push('tier = ?');
      bindings.push(query.tier);
    }

    if (query.search) {
      conditions.push('(email LIKE ? OR name LIKE ?)');
      const searchTerm = `%${query.search}%`;
      bindings.push(searchTerm, searchTerm);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    // Get total count
    const countQuery = `SELECT COUNT(*) as total FROM waitlist ${whereClause}`;
    const countResult = await env.WAITLIST_DB.prepare(countQuery)
      .bind(...bindings)
      .first<{ total: number }>();

    const total = countResult?.total || 0;
    const totalPages = Math.ceil(total / query.limit);
    const offset = (query.page - 1) * query.limit;

    // Build ORDER BY clause
    const validSortColumns = ['score', 'created_at', 'email'];
    const sortColumn = validSortColumns.includes(query.sort) ? query.sort : 'score';
    const sortOrder = query.order === 'asc' ? 'ASC' : 'DESC';
    const orderBy = `ORDER BY ${sortColumn} ${sortOrder}`;

    // Get contacts with pagination
    const contactsQuery = `
      SELECT
        id,
        email,
        name,
        email_status,
        tier,
        score,
        referrals_count,
        invite_code,
        referral_source,
        verified_at,
        created_at
      FROM waitlist
      ${whereClause}
      ${orderBy}
      LIMIT ? OFFSET ?
    `;

    const contactsResult = await env.WAITLIST_DB.prepare(contactsQuery)
      .bind(...bindings, query.limit, offset)
      .all<Contact>();

    // Calculate positions for contacts (only for verified contacts sorted by score)
    const contacts = contactsResult.results || [];

    // If sorted by score desc and filtering verified, calculate positions
    if (query.sort === 'score' && query.order === 'desc' && query.status === 'verified') {
      for (let i = 0; i < contacts.length; i++) {
        contacts[i].position = offset + i + 1;
      }
    }

    const response: ContactsResponse = {
      contacts,
      pagination: {
        page: query.page,
        limit: query.limit,
        total,
        total_pages: totalPages,
      },
    };

    return Response.json(response);
  } catch (error) {
    console.error('Contacts API error:', error);
    return Response.json(
      { error: 'Failed to fetch contacts' },
      { status: 500 }
    );
  }
};
