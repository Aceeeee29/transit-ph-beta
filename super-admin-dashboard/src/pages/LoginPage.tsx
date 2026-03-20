import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'

export function LoginPage() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    try {
      await login(email, password)
      navigate('/')
    } catch {
      setError('Login failed. Ensure your account has superadmin role in Firestore users collection.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: '1rem' }}>
      <Card style={{ width: 'min(430px, 100%)', padding: '1.5rem' }}>
        <h1 style={{ marginTop: 0 }}>TransitPH Super Admin</h1>
        <p style={{ color: 'var(--text-secondary)' }}>Sign in with your Firebase email and password</p>
        <form onSubmit={onSubmit} style={{ display: 'grid', gap: '0.75rem' }}>
          <Input type="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} required />
          <Input type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          {error ? <div style={{ color: 'var(--danger)', fontSize: '0.9rem' }}>{error}</div> : null}
          <Button type="submit" disabled={loading}>{loading ? 'Signing in...' : 'Sign in'}</Button>
        </form>
      </Card>
    </div>
  )
}
