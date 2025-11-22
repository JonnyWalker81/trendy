/**
 * Admin Console Dashboard
 * Main admin page with analytics and stats
 */

import { getAdminLayout, getStatCard } from '../shared/admin-layout';

/**
 * GET /admin - Dashboard page
 */
export const onRequestGet: PagesFunction<Env> = async (context) => {
  const content = `
    <div x-data="dashboard()" x-init="init()">
      <!-- Loading State -->
      <div x-show="loading" class="flex items-center justify-center py-12">
        <div class="spinner"></div>
        <p class="ml-4 text-gray-600">Loading analytics...</p>
      </div>

      <!-- Error State -->
      <div x-show="error && !loading" class="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
        <div class="flex items-start gap-3">
          <span class="text-xl">❌</span>
          <p class="text-red-800 font-medium" x-text="error"></p>
        </div>
      </div>

      <!-- Dashboard Content -->
      <div x-show="!loading && !error">
        <!-- Overview Stats -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <div class="flex items-center justify-between mb-2">
              <span class="text-3xl">📊</span>
            </div>
            <h3 class="text-gray-500 text-sm font-medium">Total Signups</h3>
            <p class="text-3xl font-bold text-gray-900 mt-2" x-text="data.overview.total_signups">0</p>
          </div>

          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <div class="flex items-center justify-between mb-2">
              <span class="text-3xl">✅</span>
              <span class="text-sm text-green-600 font-medium" x-text="verificationRate + '%'">0%</span>
            </div>
            <h3 class="text-gray-500 text-sm font-medium">Verified</h3>
            <p class="text-3xl font-bold text-gray-900 mt-2" x-text="data.overview.verified_signups">0</p>
          </div>

          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <div class="flex items-center justify-between mb-2">
              <span class="text-3xl">⏳</span>
            </div>
            <h3 class="text-gray-500 text-sm font-medium">Pending Verification</h3>
            <p class="text-3xl font-bold text-gray-900 mt-2" x-text="data.overview.pending_verifications">0</p>
          </div>

          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <div class="flex items-center justify-between mb-2">
              <span class="text-3xl">🔗</span>
            </div>
            <h3 class="text-gray-500 text-sm font-medium">Total Referrals</h3>
            <p class="text-3xl font-bold text-gray-900 mt-2" x-text="data.referral_stats.total_referrals">0</p>
          </div>
        </div>

        <!-- Charts Row -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <!-- Signup Trend Chart -->
          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Signup Trend (Last 30 Days)</h3>
            <canvas id="signupTrendChart"></canvas>
          </div>

          <!-- Status Distribution Chart -->
          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Email Status Distribution</h3>
            <canvas id="statusChart"></canvas>
          </div>
        </div>

        <!-- Secondary Stats -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
          <!-- Email Engagement -->
          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">📧 Email Engagement</h3>
            <div class="space-y-3">
              <div>
                <div class="flex justify-between text-sm mb-1">
                  <span class="text-gray-600">Open Rate</span>
                  <span class="font-semibold" x-text="data.email_engagement.open_rate + '%'">0%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2">
                  <div class="bg-blue-600 h-2 rounded-full" :style="'width: ' + data.email_engagement.open_rate + '%'"></div>
                </div>
              </div>
              <div>
                <div class="flex justify-between text-sm mb-1">
                  <span class="text-gray-600">Click Rate</span>
                  <span class="font-semibold" x-text="data.email_engagement.click_rate + '%'">0%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2">
                  <div class="bg-green-600 h-2 rounded-full" :style="'width: ' + data.email_engagement.click_rate + '%'"></div>
                </div>
              </div>
              <div class="pt-2 border-t">
                <p class="text-sm text-gray-600">
                  <span class="font-semibold" x-text="data.email_engagement.total_sent">0</span> sent,
                  <span class="font-semibold" x-text="data.email_engagement.total_opened">0</span> opened,
                  <span class="font-semibold" x-text="data.email_engagement.total_clicked">0</span> clicked
                </p>
              </div>
            </div>
          </div>

          <!-- Top Referrers -->
          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">🏆 Top Referrers</h3>
            <div class="space-y-2">
              <template x-for="(referrer, index) in data.referral_stats.top_referrers.slice(0, 5)" :key="referrer.email">
                <div class="flex items-center justify-between py-2 border-b last:border-0">
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-gray-900 truncate" x-text="referrer.email"></p>
                  </div>
                  <span class="ml-2 px-2 py-1 bg-blue-100 text-blue-800 text-xs font-semibold rounded" x-text="referrer.referrals_count"></span>
                </div>
              </template>
              <div x-show="data.referral_stats.top_referrers.length === 0" class="text-sm text-gray-500 text-center py-4">
                No referrals yet
              </div>
            </div>
          </div>

          <!-- Top Sources -->
          <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">🌐 Top Sources</h3>
            <div class="space-y-2">
              <template x-for="source in data.sources.slice(0, 5)" :key="source.referral_source">
                <div class="flex items-center justify-between py-2 border-b last:border-0">
                  <p class="text-sm font-medium text-gray-900" x-text="source.referral_source"></p>
                  <span class="ml-2 text-sm text-gray-600" x-text="source.count"></span>
                </div>
              </template>
              <div x-show="data.sources.length === 0" class="text-sm text-gray-500 text-center py-4">
                No source data yet
              </div>
            </div>
          </div>
        </div>

        <!-- Quick Actions -->
        <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
          <h3 class="text-lg font-semibold text-gray-900 mb-4">⚡ Quick Actions</h3>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <a href="/admin/contacts" class="flex items-center gap-3 p-4 border border-gray-200 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-all">
              <span class="text-2xl">👥</span>
              <div>
                <p class="font-semibold text-gray-900">View Contacts</p>
                <p class="text-sm text-gray-600">Browse waitlist signups</p>
              </div>
            </a>
            <a href="/admin/campaigns" class="flex items-center gap-3 p-4 border border-gray-200 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-all">
              <span class="text-2xl">📧</span>
              <div>
                <p class="font-semibold text-gray-900">Send Campaign</p>
                <p class="text-sm text-gray-600">Launch email campaigns</p>
              </div>
            </a>
            <a href="/admin/api/export?format=csv" class="flex items-center gap-3 p-4 border border-gray-200 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-all">
              <span class="text-2xl">📥</span>
              <div>
                <p class="font-semibold text-gray-900">Export Data</p>
                <p class="text-sm text-gray-600">Download CSV export</p>
              </div>
            </a>
          </div>
        </div>
      </div>
    </div>
  `;

  const scripts = `
    <script>
      function dashboard() {
        return {
          data: {
            overview: {},
            signups_by_status: [],
            recent_signups: [],
            referral_stats: { top_referrers: [] },
            email_engagement: {},
            sources: []
          },
          loading: true,
          error: null,
          signupTrendChart: null,
          statusChart: null,

          get verificationRate() {
            const total = this.data.overview.total_signups || 0;
            if (total === 0) return 0;
            const verified = this.data.overview.verified_signups || 0;
            return Math.round((verified / total) * 100);
          },

          async init() {
            await this.fetchAnalytics();
            if (!this.error) {
              this.$nextTick(() => {
                this.initCharts();
              });
            }
          },

          async fetchAnalytics() {
            try {
              const response = await fetch('/admin/api/analytics');
              if (!response.ok) throw new Error('Failed to fetch analytics');
              this.data = await response.json();
              this.loading = false;
            } catch (err) {
              this.error = err.message;
              this.loading = false;
            }
          },

          initCharts() {
            // Signup Trend Chart
            const trendCtx = document.getElementById('signupTrendChart');
            if (trendCtx && this.data.recent_signups) {
              this.signupTrendChart = new Chart(trendCtx, {
                type: 'line',
                data: {
                  labels: this.data.recent_signups.map(d => d.date),
                  datasets: [{
                    label: 'Signups',
                    data: this.data.recent_signups.map(d => d.count),
                    borderColor: 'rgb(37, 99, 235)',
                    backgroundColor: 'rgba(37, 99, 235, 0.1)',
                    tension: 0.4,
                    fill: true
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: true,
                  plugins: {
                    legend: { display: false }
                  },
                  scales: {
                    y: { beginAtZero: true }
                  }
                }
              });
            }

            // Status Distribution Chart
            const statusCtx = document.getElementById('statusChart');
            if (statusCtx && this.data.signups_by_status) {
              const colors = {
                'verified': '#10b981',
                'pending': '#f59e0b',
                'bounced': '#ef4444',
                'unsubscribed': '#6b7280',
                'invalid': '#dc2626'
              };

              this.statusChart = new Chart(statusCtx, {
                type: 'doughnut',
                data: {
                  labels: this.data.signups_by_status.map(s => s.email_status),
                  datasets: [{
                    data: this.data.signups_by_status.map(s => s.count),
                    backgroundColor: this.data.signups_by_status.map(s => colors[s.email_status] || '#9ca3af')
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: true,
                  plugins: {
                    legend: {
                      position: 'bottom'
                    }
                  }
                }
              });
            }
          }
        }
      }
    </script>
  `;

  return new Response(
    getAdminLayout({
      title: 'Dashboard',
      activePage: 'dashboard',
      content,
      scripts,
    }),
    {
      headers: { 'Content-Type': 'text/html' },
    }
  );
};
