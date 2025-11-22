/**
 * Admin Analytics API
 * Provides dashboard statistics and metrics
 */

interface AnalyticsResponse {
  overview: {
    total_signups: number;
    verified_signups: number;
    pending_verifications: number;
    unsubscribed: number;
    bounced: number;
  };
  signups_by_status: Array<{
    email_status: string;
    count: number;
  }>;
  signups_by_tier: Array<{
    tier: string;
    count: number;
  }>;
  recent_signups: Array<{
    date: string;
    count: number;
  }>;
  referral_stats: {
    total_referrals: number;
    top_referrers: Array<{
      email: string;
      referrals_count: number;
      score: number;
    }>;
  };
  email_engagement: {
    total_sent: number;
    total_opened: number;
    total_clicked: number;
    open_rate: number;
    click_rate: number;
  };
  sources: Array<{
    referral_source: string;
    count: number;
  }>;
}

/**
 * GET /admin/api/analytics - Get dashboard analytics
 */
export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { env } = context;

  try {
    // Overview stats
    const overview = await env.WAITLIST_DB.prepare(`
      SELECT
        COUNT(*) as total_signups,
        SUM(CASE WHEN email_status = 'verified' THEN 1 ELSE 0 END) as verified_signups,
        SUM(CASE WHEN email_status = 'pending' THEN 1 ELSE 0 END) as pending_verifications,
        SUM(CASE WHEN email_status = 'unsubscribed' THEN 1 ELSE 0 END) as unsubscribed,
        SUM(CASE WHEN email_status = 'bounced' THEN 1 ELSE 0 END) as bounced
      FROM waitlist
    `).first<{
      total_signups: number;
      verified_signups: number;
      pending_verifications: number;
      unsubscribed: number;
      bounced: number;
    }>();

    // Signups by status
    const signupsByStatus = await env.WAITLIST_DB.prepare(`
      SELECT email_status, COUNT(*) as count
      FROM waitlist
      GROUP BY email_status
      ORDER BY count DESC
    `).all<{ email_status: string; count: number }>();

    // Signups by tier
    const signupsByTier = await env.WAITLIST_DB.prepare(`
      SELECT tier, COUNT(*) as count
      FROM waitlist
      WHERE tier IS NOT NULL
      GROUP BY tier
      ORDER BY count DESC
    `).all<{ tier: string; count: number }>();

    // Recent signups (last 30 days, grouped by day)
    const recentSignups = await env.WAITLIST_DB.prepare(`
      SELECT
        DATE(created_at) as date,
        COUNT(*) as count
      FROM waitlist
      WHERE created_at >= date('now', '-30 days')
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    `).all<{ date: string; count: number }>();

    // Referral stats
    const referralStats = await env.WAITLIST_DB.prepare(`
      SELECT
        SUM(referrals_count) as total_referrals
      FROM waitlist
    `).first<{ total_referrals: number }>();

    const topReferrers = await env.WAITLIST_DB.prepare(`
      SELECT email, referrals_count, score
      FROM waitlist
      WHERE referrals_count > 0
      ORDER BY referrals_count DESC
      LIMIT 10
    `).all<{ email: string; referrals_count: number; score: number }>();

    // Email engagement stats
    const emailEngagement = await env.WAITLIST_DB.prepare(`
      SELECT
        SUM(total_emails_sent) as total_sent,
        SUM(total_emails_opened) as total_opened,
        SUM(total_emails_clicked) as total_clicked
      FROM waitlist
    `).first<{
      total_sent: number;
      total_opened: number;
      total_clicked: number;
    }>();

    // Calculate rates
    const openRate = emailEngagement?.total_sent
      ? ((emailEngagement.total_opened || 0) / emailEngagement.total_sent) * 100
      : 0;
    const clickRate = emailEngagement?.total_sent
      ? ((emailEngagement.total_clicked || 0) / emailEngagement.total_sent) * 100
      : 0;

    // Referral sources
    const sources = await env.WAITLIST_DB.prepare(`
      SELECT referral_source, COUNT(*) as count
      FROM waitlist
      WHERE referral_source IS NOT NULL AND referral_source != ''
      GROUP BY referral_source
      ORDER BY count DESC
      LIMIT 10
    `).all<{ referral_source: string; count: number }>();

    // Build response
    const response: AnalyticsResponse = {
      overview: {
        total_signups: overview?.total_signups || 0,
        verified_signups: overview?.verified_signups || 0,
        pending_verifications: overview?.pending_verifications || 0,
        unsubscribed: overview?.unsubscribed || 0,
        bounced: overview?.bounced || 0,
      },
      signups_by_status: signupsByStatus.results || [],
      signups_by_tier: signupsByTier.results || [],
      recent_signups: recentSignups.results || [],
      referral_stats: {
        total_referrals: referralStats?.total_referrals || 0,
        top_referrers: topReferrers.results || [],
      },
      email_engagement: {
        total_sent: emailEngagement?.total_sent || 0,
        total_opened: emailEngagement?.total_opened || 0,
        total_clicked: emailEngagement?.total_clicked || 0,
        open_rate: Math.round(openRate * 100) / 100,
        click_rate: Math.round(clickRate * 100) / 100,
      },
      sources: sources.results || [],
    };

    return Response.json(response);
  } catch (error) {
    console.error('Analytics error:', error);
    return Response.json(
      { error: 'Failed to fetch analytics' },
      { status: 500 }
    );
  }
};
