import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { isLoading, user, isSuperAdmin } = useAuth()

  if (isLoading) {
    return <div style={{ padding: '2rem', color: 'var(--text-secondary)' }}>Checking access...</div>
  }

  if (!user || !isSuperAdmin) {
    return <Navigate to="/login" replace />
  }

  return <>{children}</>
}
