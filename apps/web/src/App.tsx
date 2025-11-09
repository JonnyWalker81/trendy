import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClientProvider } from '@tanstack/react-query'
import { ReactQueryDevtools } from '@tanstack/react-query-devtools'
import { Dashboard } from './pages/Dashboard'
import { Login } from './pages/Login'
import { EventList } from './pages/EventList'
import { Analytics } from './pages/Analytics'
import { Settings } from './pages/Settings'
import { useAuth } from './lib/useAuth'
import { queryClient } from './lib/queryClient'

function App() {
  const { session, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-lg">Loading...</div>
      </div>
    )
  }

  return (
    <QueryClientProvider client={queryClient}>
      <Router>
        <Routes>
          <Route path="/login" element={session ? <Navigate to="/" /> : <Login />} />
          <Route path="/" element={session ? <Dashboard /> : <Navigate to="/login" />} />
          <Route path="/events" element={session ? <EventList /> : <Navigate to="/login" />} />
          <Route path="/analytics" element={session ? <Analytics /> : <Navigate to="/login" />} />
          <Route path="/settings" element={session ? <Settings /> : <Navigate to="/login" />} />
        </Routes>
      </Router>
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  )
}

export default App
