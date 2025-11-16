/**
 * Admin Campaigns Page
 * Send email campaigns to waitlist segments
 */

import { getAdminLayout, getAlert } from '../shared/admin-layout';

/**
 * GET /admin/campaigns - Campaigns page
 */
export const onRequestGet: PagesFunction<Env> = async (context) => {
  const content = `
    <div x-data="campaigns()" x-init="init()">
      <!-- Campaign Builder -->
      <div class="bg-white rounded-lg shadow-sm p-6 mb-6">
        <h2 class="text-2xl font-bold text-gray-900 mb-6">📧 Send Email Campaign</h2>

        <!-- Campaign Type -->
        <div class="mb-6">
          <label class="block text-sm font-medium text-gray-700 mb-2">Campaign Type</label>
          <select
            x-model="campaign.type"
            class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >
            <option value="launch">Launch Announcement</option>
            <option value="update">Product Update</option>
            <option value="early_access">Early Access Invitation</option>
            <option value="reminder">Reminder</option>
          </select>
        </div>

        <!-- Segment Selection -->
        <div class="mb-6">
          <label class="block text-sm font-medium text-gray-700 mb-2">Target Segment</label>
          <select
            x-model="campaign.segment"
            class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >
            <option value="vip">VIP (Top 100 by score)</option>
            <option value="early_access">Early Access (Position 101-500)</option>
            <option value="verified">All Verified Users</option>
            <option value="all">All Verified + Marketing Consent</option>
          </select>
          <p class="mt-2 text-sm text-gray-500">
            <span x-show="campaign.segment === 'vip'">Send to the top 100 users ranked by score</span>
            <span x-show="campaign.segment === 'early_access'">Send to users ranked 101-500 by score</span>
            <span x-show="campaign.segment === 'verified'">Send to all users with verified email</span>
            <span x-show="campaign.segment === 'all'">Send to all verified users who opted into marketing</span>
          </p>
        </div>

        <!-- Subject Line -->
        <div class="mb-6">
          <label class="block text-sm font-medium text-gray-700 mb-2">Subject Line</label>
          <input
            type="text"
            x-model="campaign.subject"
            placeholder="🚀 TrendSight is launching - You're invited!"
            class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </div>

        <!-- Email Content -->
        <div class="mb-6">
          <label class="block text-sm font-medium text-gray-700 mb-2">Email Content (HTML)</label>
          <textarea
            x-model="campaign.html"
            rows="12"
            placeholder="Enter your email HTML here. Available variables: {{name}}, {{email}}, {{position}}, {{score}}, {{invite_code}}"
            class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent font-mono text-sm"
          ></textarea>
          <p class="mt-2 text-sm text-gray-500">
            Available variables: <code>{{name}}</code>, <code>{{email}}</code>, <code>{{position}}</code>, <code>{{score}}</code>, <code>{{invite_code}}</code>
          </p>
        </div>

        <!-- Email Template Presets -->
        <div class="mb-6">
          <label class="block text-sm font-medium text-gray-700 mb-2">Quick Templates</label>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
            <button
              @click="loadTemplate('launch')"
              class="p-3 border border-gray-300 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-all text-left"
            >
              <p class="font-semibold text-gray-900">🚀 Launch</p>
              <p class="text-xs text-gray-600">Product launch announcement</p>
            </button>
            <button
              @click="loadTemplate('early_access')"
              class="p-3 border border-gray-300 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-all text-left"
            >
              <p class="font-semibold text-gray-900">⭐ Early Access</p>
              <p class="text-xs text-gray-600">Exclusive early access invite</p>
            </button>
            <button
              @click="loadTemplate('update')"
              class="p-3 border border-gray-300 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-all text-left"
            >
              <p class="font-semibold text-gray-900">📣 Update</p>
              <p class="text-xs text-gray-600">Product update notification</p>
            </button>
          </div>
        </div>

        <!-- Action Buttons -->
        <div class="flex gap-3">
          <button
            @click="previewCampaign()"
            :disabled="!canSend || loading"
            class="px-6 py-3 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            👁️ Preview Recipients
          </button>
          <button
            @click="sendCampaign()"
            :disabled="!canSend || loading"
            class="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <span x-show="!loading">📤 Send Campaign</span>
            <span x-show="loading">Sending...</span>
          </button>
        </div>
      </div>

      <!-- Preview Results -->
      <div x-show="preview" class="bg-white rounded-lg shadow-sm p-6 mb-6 fade-in">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Preview Recipients</h3>
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-4">
          <p class="text-blue-800 font-medium">
            This campaign will be sent to <strong x-text="preview?.recipient_count">0</strong> recipients
          </p>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead class="bg-gray-50 border-b">
              <tr>
                <th class="px-4 py-2 text-left text-sm font-medium text-gray-700">Position</th>
                <th class="px-4 py-2 text-left text-sm font-medium text-gray-700">Email</th>
                <th class="px-4 py-2 text-left text-sm font-medium text-gray-700">Score</th>
                <th class="px-4 py-2 text-left text-sm font-medium text-gray-700">Invite Code</th>
              </tr>
            </thead>
            <tbody class="divide-y">
              <template x-for="recipient in preview?.preview" :key="recipient.email">
                <tr>
                  <td class="px-4 py-2 text-sm" x-text="recipient.position"></td>
                  <td class="px-4 py-2 text-sm" x-text="recipient.email"></td>
                  <td class="px-4 py-2 text-sm" x-text="recipient.score.toLocaleString()"></td>
                  <td class="px-4 py-2 text-sm font-mono text-xs" x-text="recipient.invite_code"></td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>
        <p class="text-sm text-gray-500 mt-4">Showing first 10 recipients</p>
      </div>

      <!-- Success/Error Messages -->
      <div x-show="result.success" class="bg-green-50 border border-green-200 rounded-lg p-4 mb-6 fade-in">
        <div class="flex items-start gap-3">
          <span class="text-xl">✅</span>
          <div>
            <p class="text-green-800 font-medium">Campaign sent successfully!</p>
            <p class="text-green-700 text-sm mt-1">
              Sent to <strong x-text="result.sent_count">0</strong> recipients
              <span x-show="result.failed_count > 0">
                (<strong x-text="result.failed_count"></strong> failed)
              </span>
            </p>
          </div>
        </div>
      </div>

      <div x-show="result.error" class="bg-red-50 border border-red-200 rounded-lg p-4 mb-6 fade-in">
        <div class="flex items-start gap-3">
          <span class="text-xl">❌</span>
          <p class="text-red-800 font-medium" x-text="result.error"></p>
        </div>
      </div>

      <!-- Warning -->
      <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
        <div class="flex items-start gap-3">
          <span class="text-xl">⚠️</span>
          <div>
            <p class="text-yellow-800 font-medium">Important: Email Sending</p>
            <ul class="text-yellow-700 text-sm mt-2 space-y-1 list-disc list-inside">
              <li>Always preview recipients before sending</li>
              <li>Make sure your email content is personalized and tested</li>
              <li>Rate limit: 2 emails per second (500ms delay between sends)</li>
              <li>Automatic retry for rate limit errors (429)</li>
              <li>Failed emails are logged in the response and server console</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  `;

  const scripts = `
    <script>
      function campaigns() {
        return {
          campaign: {
            type: 'launch',
            segment: 'vip',
            subject: '',
            html: ''
          },
          preview: null,
          result: {
            success: false,
            error: null,
            sent_count: 0,
            failed_count: 0
          },
          loading: false,

          get canSend() {
            return this.campaign.subject && this.campaign.html;
          },

          init() {
            // Load default template
            this.loadTemplate('launch');
          },

          loadTemplate(type) {
            const templates = {
              launch: {
                subject: '🚀 TrendSight is launching - You\\'re invited!',
                html: \`<html>
<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <h1 style="color: #1e40af;">🚀 We\\'re Launching!</h1>
  <p>Hi {{name}},</p>
  <p>Great news! TrendSight is officially launching, and you\\'re one of our first users.</p>
  <p><strong>Your position:</strong> #{{position}} out of thousands of signups!</p>
  <p><strong>Your invite code:</strong> <code>{{invite_code}}</code></p>
  <p>Get started now: <a href="https://trendsight.app/signup?code={{invite_code}}">Sign Up</a></p>
  <p>Thanks for being part of our journey!</p>
  <p>The TrendSight Team</p>
</body>
</html>\`
              },
              early_access: {
                subject: '⭐ You\\'re invited to TrendSight Early Access',
                html: \`<html>
<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <h1 style="color: #1e40af;">⭐ Exclusive Early Access</h1>
  <p>Hi {{name}},</p>
  <p>Congratulations! You\\'ve earned early access to TrendSight.</p>
  <p>With a score of <strong>{{score}}</strong>, you\\'re ranked <strong>#{{position}}</strong> on our waitlist.</p>
  <p><strong>Your exclusive invite code:</strong> <code>{{invite_code}}</code></p>
  <p>Start using TrendSight: <a href="https://trendsight.app/signup?code={{invite_code}}">Get Early Access</a></p>
  <p>Cheers,<br>The TrendSight Team</p>
</body>
</html>\`
              },
              update: {
                subject: '📣 TrendSight Update - New Features',
                html: \`<html>
<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <h1 style="color: #1e40af;">📣 Product Update</h1>
  <p>Hi {{name}},</p>
  <p>We\\'ve been hard at work building TrendSight, and we wanted to share some exciting updates with you.</p>
  <p>As one of our early supporters (ranked <strong>#{{position}}</strong>), we value your feedback.</p>
  <p>Check out what\\'s new: <a href="https://trendsight.app/updates">View Updates</a></p>
  <p>Best,<br>The TrendSight Team</p>
</body>
</html>\`
              }
            };

            const template = templates[type];
            if (template) {
              this.campaign.subject = template.subject;
              this.campaign.html = template.html;
            }
          },

          async previewCampaign() {
            this.loading = true;
            this.result = { success: false, error: null, sent_count: 0, failed_count: 0 };

            try {
              const response = await fetch('/admin/api/send-campaign', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  campaign_type: this.campaign.type,
                  segment: this.campaign.segment,
                  subject: this.campaign.subject,
                  html_content: this.campaign.html,
                  dry_run: true
                })
              });

              if (!response.ok) {
                const error = await response.json();
                throw new Error(error.error || 'Failed to preview campaign');
              }

              this.preview = await response.json();
              this.loading = false;
            } catch (err) {
              this.result.error = err.message;
              this.loading = false;
            }
          },

          async sendCampaign() {
            if (!confirm(\`Are you sure you want to send this campaign to \${this.preview?.recipient_count || 'all'} recipients? This cannot be undone.\`)) {
              return;
            }

            this.loading = true;
            this.result = { success: false, error: null, sent_count: 0, failed_count: 0 };

            try {
              const response = await fetch('/admin/api/send-campaign', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  campaign_type: this.campaign.type,
                  segment: this.campaign.segment,
                  subject: this.campaign.subject,
                  html_content: this.campaign.html,
                  dry_run: false
                })
              });

              if (!response.ok) {
                const error = await response.json();
                throw new Error(error.error || 'Failed to send campaign');
              }

              const data = await response.json();
              this.result.success = true;
              this.result.sent_count = data.sent_count;
              this.result.failed_count = data.failed_count;
              this.loading = false;
              this.preview = null;
            } catch (err) {
              this.result.error = err.message;
              this.loading = false;
            }
          }
        }
      }
    </script>
  `;

  return new Response(
    getAdminLayout({
      title: 'Campaigns',
      activePage: 'campaigns',
      content,
      scripts,
    }),
    {
      headers: { 'Content-Type': 'text/html' },
    }
  );
};
