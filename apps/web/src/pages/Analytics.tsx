export function Analytics() {
  return (
    <div className="min-h-screen bg-gray-50">
      {/* Navigation */}
      <nav className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between h-16">
            <div className="flex items-center">
              <div className="flex-shrink-0 flex items-center">
                <div className="w-10 h-10 bg-gradient-to-br from-primary-500 to-primary-600 rounded-xl flex items-center justify-center shadow-md">
                  <span className="text-xl">📊</span>
                </div>
                <h1 className="ml-3 text-xl font-bold bg-gradient-to-r from-primary-600 to-primary-700 bg-clip-text text-transparent">
                  Trendy
                </h1>
              </div>
              <div className="hidden sm:ml-8 sm:flex sm:space-x-1">
                <a
                  href="/"
                  className="text-gray-600 hover:text-gray-900 hover:bg-gray-100 px-4 py-2 rounded-lg text-sm font-medium transition duration-200"
                >
                  Dashboard
                </a>
                <a
                  href="/events"
                  className="text-gray-600 hover:text-gray-900 hover:bg-gray-100 px-4 py-2 rounded-lg text-sm font-medium transition duration-200"
                >
                  Events
                </a>
                <a
                  href="/analytics"
                  className="bg-primary-50 text-primary-700 px-4 py-2 rounded-lg text-sm font-semibold transition duration-200"
                >
                  Analytics
                </a>
                <a
                  href="/settings"
                  className="text-gray-600 hover:text-gray-900 hover:bg-gray-100 px-4 py-2 rounded-lg text-sm font-medium transition duration-200"
                >
                  Settings
                </a>
              </div>
            </div>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
        <div className="mb-8">
          <h2 className="text-3xl font-bold text-gray-900">Analytics</h2>
          <p className="mt-2 text-gray-600">Visualize trends and patterns in your event data</p>
        </div>

        {/* Time Period Selector */}
        <div className="mb-6 flex gap-2">
          <button className="px-4 py-2 bg-primary-600 text-white rounded-lg text-sm font-medium shadow-sm">
            Week
          </button>
          <button className="px-4 py-2 bg-white text-gray-700 border border-gray-300 rounded-lg text-sm font-medium hover:bg-gray-50">
            Month
          </button>
          <button className="px-4 py-2 bg-white text-gray-700 border border-gray-300 rounded-lg text-sm font-medium hover:bg-gray-50">
            Year
          </button>
        </div>

        {/* Analytics Cards */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Chart Placeholder */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-200 p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Event Frequency</h3>
            <div className="h-64 flex items-center justify-center bg-gray-50 rounded-lg">
              <div className="text-center">
                <span className="text-5xl mb-2 block">📈</span>
                <p className="text-gray-500 text-sm">Chart will appear here</p>
              </div>
            </div>
          </div>

          {/* Trends Placeholder */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-200 p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Trending Events</h3>
            <div className="h-64 flex items-center justify-center bg-gray-50 rounded-lg">
              <div className="text-center">
                <span className="text-5xl mb-2 block">📊</span>
                <p className="text-gray-500 text-sm">Trends will appear here</p>
              </div>
            </div>
          </div>
        </div>

        {/* Insights */}
        <div className="mt-6 bg-white rounded-2xl shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Insights</h3>
          <div className="text-center py-8">
            <div className="inline-flex items-center justify-center w-16 h-16 bg-gray-100 rounded-full mb-4">
              <span className="text-3xl">💡</span>
            </div>
            <p className="text-gray-500 text-sm">No insights available yet</p>
            <p className="text-gray-400 text-xs mt-1">Track more events to generate insights</p>
          </div>
        </div>
      </main>
    </div>
  )
}
