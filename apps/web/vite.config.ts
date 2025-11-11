import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  // Load env file based on `mode` in the current working directory.
  const env = loadEnv(mode, process.cwd(), '')

  // Cloudflare Pages provides env vars as process.env, fallback to .env files
  const apiBaseUrl = process.env.VITE_API_BASE_URL || env.VITE_API_BASE_URL || '/api/v1'
  const supabaseUrl = process.env.VITE_SUPABASE_URL || env.VITE_SUPABASE_URL || ''
  const supabaseAnonKey = process.env.VITE_SUPABASE_ANON_KEY || env.VITE_SUPABASE_ANON_KEY || ''

  // Log environment variables during build for debugging
  console.log('🔧 Vite Build Config:', {
    mode,
    VITE_API_BASE_URL: apiBaseUrl,
    VITE_SUPABASE_URL: supabaseUrl ? '***' : '(not set)',
    NODE_ENV: process.env.NODE_ENV,
  })

  return {
    plugins: [react()],

    // Explicitly define environment variables for build-time embedding
    // This is REQUIRED for Cloudflare Pages to work correctly
    define: {
      'import.meta.env.VITE_API_BASE_URL': JSON.stringify(apiBaseUrl),
      'import.meta.env.VITE_SUPABASE_URL': JSON.stringify(supabaseUrl),
      'import.meta.env.VITE_SUPABASE_ANON_KEY': JSON.stringify(supabaseAnonKey),
    },

    resolve: {
      alias: {
        '@': path.resolve(__dirname, './src'),
      },
    },
    server: {
      port: 3000,
      proxy: {
        '/api': {
          target: 'http://localhost:8888',
          changeOrigin: true,
        },
      },
    },
  }
})
