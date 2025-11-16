/**
 * Admin Contacts Page
 * Browse and filter waitlist contacts
 */

import { getAdminLayout, formatDate, formatRelativeTime } from '../shared/admin-layout';

/**
 * GET /admin/contacts - Contacts list page
 */
export const onRequestGet: PagesFunction<Env> = async (context) => {
  const content = `
    <div x-data="contacts()" x-init="init()">
      <!-- Filters and Search -->
      <div class="bg-white rounded-lg shadow-sm p-6 mb-6">
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
          <!-- Search -->
          <div class="md:col-span-2">
            <label class="block text-sm font-medium text-gray-700 mb-2">Search</label>
            <input
              type="text"
              x-model="filters.search"
              @keyup.enter="applyFilters()"
              placeholder="Search email or name..."
              class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <!-- Status Filter -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Status</label>
            <select
              x-model="filters.status"
              @change="applyFilters()"
              class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="">All Statuses</option>
              <option value="verified">Verified</option>
              <option value="pending">Pending</option>
              <option value="bounced">Bounced</option>
              <option value="unsubscribed">Unsubscribed</option>
            </select>
          </div>

          <!-- Tier Filter -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Tier</label>
            <select
              x-model="filters.tier"
              @change="applyFilters()"
              class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="">All Tiers</option>
              <option value="standard">Standard</option>
              <option value="early_access">Early Access</option>
              <option value="vip">VIP</option>
              <option value="beta_tester">Beta Tester</option>
            </select>
          </div>
        </div>

        <!-- Action Buttons -->
        <div class="flex gap-3 mt-4">
          <button
            @click="applyFilters()"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            Apply Filters
          </button>
          <button
            @click="resetFilters()"
            class="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors"
          >
            Reset
          </button>
          <a
            href="/admin/api/export?format=csv"
            class="ml-auto px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
          >
            📥 Export CSV
          </a>
        </div>
      </div>

      <!-- Loading State -->
      <div x-show="loading" class="flex items-center justify-center py-12">
        <div class="spinner"></div>
        <p class="ml-4 text-gray-600">Loading contacts...</p>
      </div>

      <!-- Error State -->
      <div x-show="error && !loading" class="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
        <div class="flex items-start gap-3">
          <span class="text-xl">❌</span>
          <p class="text-red-800 font-medium" x-text="error"></p>
        </div>
      </div>

      <!-- Contacts Table -->
      <div x-show="!loading && !error" class="bg-white rounded-lg shadow-sm overflow-hidden">
        <!-- Table Header -->
        <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
          <h3 class="text-lg font-semibold text-gray-900">
            Contacts (<span x-text="pagination.total">0</span>)
          </h3>
          <p class="text-sm text-gray-600">
            Page <span x-text="pagination.page"></span> of <span x-text="pagination.total_pages"></span>
          </p>
        </div>

        <!-- Table -->
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead class="bg-gray-50 border-b border-gray-200">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">#</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Email</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Score</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Referrals</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Tier</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Joined</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <template x-for="(contact, index) in contacts" :key="contact.id">
                <tr class="hover:bg-gray-50 transition-colors">
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500" x-text="contact.position || '-'"></td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <p class="text-sm font-medium text-gray-900" x-text="contact.email"></p>
                    <p class="text-xs text-gray-500" x-text="contact.referral_source || 'Direct'"></p>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900" x-text="contact.name || '-'"></td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span
                      class="px-2 py-1 text-xs font-semibold rounded-full"
                      :class="{
                        'bg-green-100 text-green-800': contact.email_status === 'verified',
                        'bg-yellow-100 text-yellow-800': contact.email_status === 'pending',
                        'bg-red-100 text-red-800': contact.email_status === 'bounced',
                        'bg-gray-100 text-gray-800': contact.email_status === 'unsubscribed'
                      }"
                      x-text="contact.email_status"
                    ></span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900" x-text="contact.score.toLocaleString()"></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <span class="px-2 py-1 bg-blue-100 text-blue-800 rounded-full text-xs font-semibold" x-text="contact.referrals_count"></span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900" x-text="contact.tier || 'standard'"></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500" x-text="formatRelativeTime(contact.created_at)"></td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm">
                    <button
                      @click="copyInviteCode(contact.invite_code)"
                      class="text-blue-600 hover:text-blue-800 font-medium"
                      title="Copy invite code"
                    >
                      Copy Invite
                    </button>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>

          <!-- Empty State -->
          <div x-show="contacts.length === 0" class="text-center py-12">
            <div class="text-6xl mb-4">🔍</div>
            <h3 class="text-xl font-semibold text-gray-900 mb-2">No contacts found</h3>
            <p class="text-gray-600">Try adjusting your filters</p>
          </div>
        </div>

        <!-- Pagination -->
        <div x-show="pagination.total_pages > 1" class="px-6 py-4 border-t border-gray-200 flex items-center justify-between">
          <button
            @click="previousPage()"
            :disabled="pagination.page === 1"
            class="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            ← Previous
          </button>
          <div class="flex gap-2">
            <template x-for="page in visiblePages" :key="page">
              <button
                @click="goToPage(page)"
                :class="page === pagination.page ? 'bg-blue-600 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'"
                class="px-3 py-1 rounded transition-colors"
                x-text="page"
              ></button>
            </template>
          </div>
          <button
            @click="nextPage()"
            :disabled="pagination.page === pagination.total_pages"
            class="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Next →
          </button>
        </div>
      </div>

      <!-- Toast Notification -->
      <div
        x-show="toast.show"
        x-transition
        class="fixed bottom-4 right-4 bg-gray-900 text-white px-6 py-3 rounded-lg shadow-lg"
      >
        <p x-text="toast.message"></p>
      </div>
    </div>
  `;

  const scripts = `
    <script>
      function contacts() {
        return {
          contacts: [],
          filters: {
            search: '',
            status: '',
            tier: '',
            page: 1,
            limit: 50
          },
          pagination: {
            page: 1,
            limit: 50,
            total: 0,
            total_pages: 0
          },
          loading: true,
          error: null,
          toast: {
            show: false,
            message: ''
          },

          get visiblePages() {
            const pages = [];
            const current = this.pagination.page;
            const total = this.pagination.total_pages;
            const range = 2;

            for (let i = Math.max(1, current - range); i <= Math.min(total, current + range); i++) {
              pages.push(i);
            }
            return pages;
          },

          async init() {
            await this.fetchContacts();
          },

          async fetchContacts() {
            this.loading = true;
            this.error = null;

            try {
              const params = new URLSearchParams();
              params.set('page', this.filters.page.toString());
              params.set('limit', this.filters.limit.toString());
              if (this.filters.search) params.set('search', this.filters.search);
              if (this.filters.status) params.set('status', this.filters.status);
              if (this.filters.tier) params.set('tier', this.filters.tier);

              const response = await fetch('/admin/api/contacts?' + params.toString());
              if (!response.ok) throw new Error('Failed to fetch contacts');

              const data = await response.json();
              this.contacts = data.contacts;
              this.pagination = data.pagination;
              this.loading = false;
            } catch (err) {
              this.error = err.message;
              this.loading = false;
            }
          },

          applyFilters() {
            this.filters.page = 1;
            this.fetchContacts();
          },

          resetFilters() {
            this.filters = {
              search: '',
              status: '',
              tier: '',
              page: 1,
              limit: 50
            };
            this.fetchContacts();
          },

          previousPage() {
            if (this.pagination.page > 1) {
              this.filters.page = this.pagination.page - 1;
              this.fetchContacts();
            }
          },

          nextPage() {
            if (this.pagination.page < this.pagination.total_pages) {
              this.filters.page = this.pagination.page + 1;
              this.fetchContacts();
            }
          },

          goToPage(page) {
            this.filters.page = page;
            this.fetchContacts();
          },

          async copyInviteCode(code) {
            try {
              await navigator.clipboard.writeText(code);
              this.showToast('Invite code copied to clipboard!');
            } catch (err) {
              this.showToast('Failed to copy invite code');
            }
          },

          formatRelativeTime(dateString) {
            const date = new Date(dateString);
            const now = new Date();
            const diffMs = now - date;
            const diffMins = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);
            const diffDays = Math.floor(diffMs / 86400000);

            if (diffMins < 1) return 'just now';
            if (diffMins < 60) return diffMins + 'm ago';
            if (diffHours < 24) return diffHours + 'h ago';
            if (diffDays < 30) return diffDays + 'd ago';
            return date.toLocaleDateString();
          },

          showToast(message) {
            this.toast.message = message;
            this.toast.show = true;
            setTimeout(() => {
              this.toast.show = false;
            }, 3000);
          }
        }
      }
    </script>
  `;

  return new Response(
    getAdminLayout({
      title: 'Contacts',
      activePage: 'contacts',
      content,
      scripts,
    }),
    {
      headers: { 'Content-Type': 'text/html' },
    }
  );
};
