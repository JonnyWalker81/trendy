import { useState, useEffect } from 'react'
import { useNavigate, useSearchParams, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'

interface InviteCodeVerification {
  valid: boolean
  email?: string
  name?: string
  tier?: string
  already_used?: boolean
  error?: string
}

// Landing page URL (where waitlist API lives)
const LANDING_URL = import.meta.env.VITE_LANDING_URL || 'https://trendsight.app'

export function Signup() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const inviteCode = searchParams.get('code')

  const [email, setEmail] = useState('')
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [verifying, setVerifying] = useState(false)
  const [error, setError] = useState('')
  const [inviteData, setInviteData] = useState<InviteCodeVerification | null>(null)

  // Verify invite code on mount if present
  useEffect(() => {
    if (inviteCode) {
      verifyInviteCode()
    }
  }, [inviteCode])

  const verifyInviteCode = async () => {
    if (!inviteCode) return

    setVerifying(true)
    setError('')

    try {
      const response = await fetch(
        `${LANDING_URL}/api/waitlist/verify-code?code=${encodeURIComponent(inviteCode)}`
      )
      const data: InviteCodeVerification = await response.json()

      if (response.ok && data.valid) {
        setInviteData(data)
        if (data.email) setEmail(data.email)
        if (data.name) setName(data.name)
      } else {
        setError(data.error || 'Invalid invite code')
        setInviteData({ valid: false, error: data.error })
      }
    } catch (err) {
      setError('Failed to verify invite code. Please try again.')
      console.error('Invite code verification error:', err)
    } finally {
      setVerifying(false)
    }
  }

  const linkInviteCode = async (userId: string) => {
    if (!inviteCode) return

    try {
      const response = await fetch(`${LANDING_URL}/api/waitlist/link`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          invite_code: inviteCode,
          supabase_user_id: userId,
        }),
      })

      if (!response.ok) {
        const data = await response.json()
        console.error('Failed to link invite code:', data.error)
        // Don't block signup if linking fails - we can link later
      }
    } catch (err) {
      console.error('Error linking invite code:', err)
      // Don't block signup if linking fails
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')

    try {
      // Create Supabase account
      const { data: authData, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            name: name || undefined,
          },
        },
      })

      if (signUpError) throw signUpError

      // Link invite code if present
      if (inviteCode && authData.user) {
        await linkInviteCode(authData.user.id)
      }

      // Redirect to dashboard
      navigate('/')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred during signup')
    } finally {
      setLoading(false)
    }
  }

  // Show error if invite code is invalid
  if (inviteCode && inviteData && !inviteData.valid) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background px-4">
        <div className="max-w-md w-full">
          <div className="text-center mb-8">
            <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-br from-primary to-primary/80 rounded-2xl mb-4 shadow-lg">
              <span className="text-3xl">📊</span>
            </div>
            <h2 className="text-4xl font-bold bg-gradient-to-r from-primary to-primary/80 bg-clip-text text-transparent">
              TrendSight
            </h2>
          </div>

          <div className="bg-card rounded-2xl shadow-xl border border-border p-8">
            <div className="text-center">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-destructive/10 rounded-full mb-4">
                <svg className="w-8 h-8 text-destructive" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </div>
              <h3 className="text-xl font-bold text-foreground mb-2">Invalid Invite Code</h3>
              <p className="text-muted-foreground mb-6">
                {error || 'This invite code is not valid or has already been used.'}
              </p>
              <Link
                to="/login"
                className="inline-block px-6 py-3 bg-primary text-primary-foreground rounded-lg font-semibold hover:bg-primary/90 transition duration-200"
              >
                Go to Login
              </Link>
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <div className="max-w-md w-full">
        {/* Logo/Header */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-br from-primary to-primary/80 rounded-2xl mb-4 shadow-lg">
            <span className="text-3xl">📊</span>
          </div>
          <h2 className="text-4xl font-bold bg-gradient-to-r from-primary to-primary/80 bg-clip-text text-transparent">
            TrendSight
          </h2>
          <p className="mt-2 text-muted-foreground text-lg">
            Create your account
          </p>
          {inviteCode && inviteData?.valid && inviteData.tier && (
            <div className="mt-3 inline-block bg-primary/10 border border-primary/30 text-primary px-4 py-2 rounded-lg text-sm font-semibold">
              {inviteData.tier === 'vip' && '✨ VIP Early Access'}
              {inviteData.tier === 'early_access' && '🚀 Early Access'}
              {inviteData.tier === 'beta_tester' && '🧪 Beta Tester'}
              {!['vip', 'early_access', 'beta_tester'].includes(inviteData.tier) && '🎉 Special Invite'}
            </div>
          )}
        </div>

        {/* Card */}
        <div className="bg-card rounded-2xl shadow-xl border border-border p-8">
          {verifying ? (
            <div className="text-center py-8">
              <svg className="animate-spin mx-auto h-10 w-10 text-primary mb-4" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
              <p className="text-muted-foreground">Verifying invite code...</p>
            </div>
          ) : (
            <form className="space-y-6" onSubmit={handleSubmit}>
              {error && (
                <div className="bg-destructive/10 border border-destructive/50 text-destructive px-4 py-3 rounded-lg flex items-start">
                  <svg className="w-5 h-5 mr-2 flex-shrink-0 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
                    <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
                  </svg>
                  <span className="text-sm">{error}</span>
                </div>
              )}

              <div>
                <label htmlFor="name" className="block text-sm font-semibold text-foreground mb-2">
                  Name {!name && <span className="text-muted-foreground font-normal">(optional)</span>}
                </label>
                <input
                  id="name"
                  name="name"
                  type="text"
                  className="w-full px-4 py-3 bg-background border border-border rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent transition duration-200 placeholder-muted-foreground text-foreground"
                  placeholder="Your name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              </div>

              <div>
                <label htmlFor="email" className="block text-sm font-semibold text-foreground mb-2">
                  Email Address
                  {inviteCode && inviteData?.valid && (
                    <span className="ml-2 text-xs text-muted-foreground font-normal">(from invite)</span>
                  )}
                </label>
                <input
                  id="email"
                  name="email"
                  type="email"
                  required
                  className="w-full px-4 py-3 bg-background border border-border rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent transition duration-200 placeholder-muted-foreground text-foreground"
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
                {inviteCode && inviteData?.valid && (
                  <p className="mt-2 text-xs text-muted-foreground">
                    You can change this email if needed
                  </p>
                )}
              </div>

              <div>
                <label htmlFor="password" className="block text-sm font-semibold text-foreground mb-2">
                  Password
                </label>
                <input
                  id="password"
                  name="password"
                  type="password"
                  required
                  minLength={6}
                  className="w-full px-4 py-3 bg-background border border-border rounded-lg shadow-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent transition duration-200 placeholder-muted-foreground text-foreground"
                  placeholder="••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                />
                <p className="mt-2 text-xs text-muted-foreground">
                  Must be at least 6 characters
                </p>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full flex justify-center items-center py-3 px-4 border border-transparent rounded-lg shadow-sm text-sm font-semibold text-primary-foreground bg-primary hover:bg-primary/90 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary disabled:opacity-50 disabled:cursor-not-allowed transition duration-200"
              >
                {loading ? (
                  <>
                    <svg className="animate-spin -ml-1 mr-3 h-5 w-5" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                    </svg>
                    Creating Account...
                  </>
                ) : (
                  'Create Account'
                )}
              </button>

              <div className="text-center pt-4">
                <Link
                  to="/login"
                  className="text-sm text-primary hover:text-primary/80 font-medium transition duration-200"
                >
                  Already have an account? Sign in
                </Link>
              </div>
            </form>
          )}
        </div>

        {/* Footer */}
        <p className="mt-8 text-center text-sm text-muted-foreground">
          {inviteCode
            ? 'Join TrendSight with your exclusive invite'
            : 'Track your events and visualize patterns'}
        </p>
      </div>
    </div>
  )
}
