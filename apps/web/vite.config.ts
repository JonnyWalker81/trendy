import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  // Load env file based on `mode` in the current working directory.
  const env = loadEnv(mode, process.cwd(), '')

  // Log environment variables during build for debugging
  console.log('🔧 Vite Build Config:', {
    mode,
    VITE_API_BASE_URL: env.VITE_API_BASE_URL || '(not set - will use /api/v1)',
    NODE_ENV: process.env.NODE_ENV,
  })

  return {
    plugins: [react()],
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
