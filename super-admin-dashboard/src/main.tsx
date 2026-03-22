import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter } from 'react-router-dom'
import { AuthProvider } from '@/hooks/useAuth'
import { AppRouter } from '@/App'
import { GlobalButtonConfirmation } from '@/components/GlobalButtonConfirmation'
import '@/styles.css'

const queryClient = new QueryClient()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <GlobalButtonConfirmation>
          <BrowserRouter>
            <AppRouter />
          </BrowserRouter>
        </GlobalButtonConfirmation>
      </AuthProvider>
    </QueryClientProvider>
  </StrictMode>,
)
