/**
 * Shared Admin Layout Helper
 * Provides reusable functions for generating consistent HTML layouts across admin pages
 */

interface AdminLayoutOptions {
  title: string;
  activePage: 'dashboard' | 'contacts' | 'campaigns';
  content: string;
  scripts?: string;
}

/**
 * Generate complete admin page HTML with navigation and layout
 */
export function getAdminLayout(options: AdminLayoutOptions): string {
  const { title, activePage, content, scripts = '' } = options;

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title} - TrendSight Admin</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
  <style>
    /* Custom scrollbar */
    ::-webkit-scrollbar {
      width: 8px;
      height: 8px;
    }
    ::-webkit-scrollbar-track {
      background: #f1f5f9;
    }
    ::-webkit-scrollbar-thumb {
      background: #cbd5e1;
      border-radius: 4px;
    }
    ::-webkit-scrollbar-thumb:hover {
      background: #94a3b8;
    }

    /* Animations */
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(10px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .fade-in {
      animation: fadeIn 0.3s ease-out;
    }

    /* Loading spinner */
    .spinner {
      border: 3px solid #f3f4f6;
      border-top: 3px solid #2563eb;
      border-radius: 50%;
      width: 40px;
      height: 40px;
      animation: spin 1s linear infinite;
    }
    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }

    /* Custom gradient */
    .gradient-bg {
      background: linear-gradient(135deg, #1e40af 0%, #3730a3 100%);
    }
  </style>
</head>
<body class="bg-gray-50">
  <!-- Navigation Sidebar -->
  <div class="fixed inset-y-0 left-0 w-64 gradient-bg text-white z-50">
    <div class="flex flex-col h-full">
      <!-- Logo -->
      <div class="p-6 border-b border-white/20">
        <h1 class="text-2xl font-bold">TrendSight</h1>
        <p class="text-sm text-blue-200 mt-1">Admin Console</p>
      </div>

      <!-- Navigation -->
      <nav class="flex-1 p-4 space-y-2">
        ${getNavItem('dashboard', '📊', 'Dashboard', activePage)}
        ${getNavItem('contacts', '👥', 'Contacts', activePage)}
        ${getNavItem('campaigns', '📧', 'Campaigns', activePage)}
      </nav>

      <!-- Logout -->
      <div class="p-4 border-t border-white/20">
        <form method="POST" action="/admin/logout">
          <button type="submit" class="w-full flex items-center gap-2 px-4 py-2 rounded-lg hover:bg-white/10 transition-colors text-left">
            <span>🚪</span>
            <span>Logout</span>
          </button>
        </form>
      </div>
    </div>
  </div>

  <!-- Main Content -->
  <div class="ml-64 min-h-screen">
    <!-- Header -->
    <header class="bg-white border-b border-gray-200 sticky top-0 z-40">
      <div class="px-8 py-4">
        <h2 class="text-2xl font-bold text-gray-900">${title}</h2>
      </div>
    </header>

    <!-- Page Content -->
    <main class="p-8">
      ${content}
    </main>
  </div>

  ${scripts}
</body>
</html>
  `;
}

/**
 * Generate navigation item
 */
function getNavItem(page: string, icon: string, label: string, activePage: string): string {
  const isActive = page === activePage;
  const activeClass = isActive
    ? 'bg-white/20 font-semibold'
    : 'hover:bg-white/10';

  return `
    <a href="/admin/${page === 'dashboard' ? '' : page}" class="${activeClass} flex items-center gap-2 px-4 py-3 rounded-lg transition-colors">
      <span>${icon}</span>
      <span>${label}</span>
    </a>
  `;
}

/**
 * Generate stat card HTML
 */
export function getStatCard(options: {
  label: string;
  value: string | number;
  icon: string;
  change?: string;
  changeType?: 'positive' | 'negative' | 'neutral';
}): string {
  const { label, value, icon, change, changeType = 'neutral' } = options;

  const changeColor = {
    positive: 'text-green-600',
    negative: 'text-red-600',
    neutral: 'text-gray-600',
  }[changeType];

  return `
    <div class="bg-white rounded-lg shadow-sm p-6 fade-in">
      <div class="flex items-center justify-between mb-2">
        <span class="text-3xl">${icon}</span>
        ${change ? `<span class="text-sm ${changeColor} font-medium">${change}</span>` : ''}
      </div>
      <h3 class="text-gray-500 text-sm font-medium">${label}</h3>
      <p class="text-3xl font-bold text-gray-900 mt-2">${value}</p>
    </div>
  `;
}

/**
 * Generate alert/notification
 */
export function getAlert(options: {
  type: 'success' | 'error' | 'warning' | 'info';
  message: string;
}): string {
  const { type, message } = options;

  const config = {
    success: { bg: 'bg-green-50', border: 'border-green-200', text: 'text-green-800', icon: '✅' },
    error: { bg: 'bg-red-50', border: 'border-red-200', text: 'text-red-800', icon: '❌' },
    warning: { bg: 'bg-yellow-50', border: 'border-yellow-200', text: 'text-yellow-800', icon: '⚠️' },
    info: { bg: 'bg-blue-50', border: 'border-blue-200', text: 'text-blue-800', icon: 'ℹ️' },
  }[type];

  return `
    <div class="${config.bg} border ${config.border} rounded-lg p-4 mb-6 fade-in">
      <div class="flex items-start gap-3">
        <span class="text-xl">${config.icon}</span>
        <p class="${config.text} font-medium">${message}</p>
      </div>
    </div>
  `;
}

/**
 * Generate loading spinner
 */
export function getLoadingSpinner(message: string = 'Loading...'): string {
  return `
    <div class="flex flex-col items-center justify-center py-12">
      <div class="spinner"></div>
      <p class="mt-4 text-gray-600">${message}</p>
    </div>
  `;
}

/**
 * Generate empty state
 */
export function getEmptyState(options: {
  icon: string;
  title: string;
  description: string;
  actionLabel?: string;
  actionHref?: string;
}): string {
  const { icon, title, description, actionLabel, actionHref } = options;

  return `
    <div class="text-center py-12">
      <div class="text-6xl mb-4">${icon}</div>
      <h3 class="text-xl font-semibold text-gray-900 mb-2">${title}</h3>
      <p class="text-gray-600 mb-6">${description}</p>
      ${actionLabel && actionHref ? `
        <a href="${actionHref}" class="inline-block bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 transition-colors">
          ${actionLabel}
        </a>
      ` : ''}
    </div>
  `;
}

/**
 * Parse cookies from Cookie header
 */
export function parseCookies(cookieHeader: string): Record<string, string> {
  const cookies: Record<string, string> = {};

  if (!cookieHeader) return cookies;

  cookieHeader.split(';').forEach(cookie => {
    const [name, ...rest] = cookie.split('=');
    if (name && rest.length > 0) {
      cookies[name.trim()] = rest.join('=').trim();
    }
  });

  return cookies;
}

/**
 * Format number with commas
 */
export function formatNumber(num: number): string {
  return num.toLocaleString('en-US');
}

/**
 * Format date
 */
export function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}

/**
 * Format relative time (e.g., "2 hours ago")
 */
export function formatRelativeTime(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 30) return `${diffDays}d ago`;
  return formatDate(dateString);
}
