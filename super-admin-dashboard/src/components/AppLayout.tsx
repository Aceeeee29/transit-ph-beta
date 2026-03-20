import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import {
  Bell,
  ChartNoAxesCombined,
  CircleUserRound,
  Megaphone,
  MessageSquareWarning,
  Route,
  Settings,
  Shield,
  Users,
} from 'lucide-react'
import { useAuth } from '@/hooks/useAuth'
import { Button } from '@/components/ui/button'

const links = [
  { to: '/', label: 'Dashboard', icon: ChartNoAxesCombined },
  { to: '/users', label: 'User Management', icon: Users },
  { to: '/moderators', label: 'Moderator Management', icon: Shield },
  { to: '/routes', label: 'Route Management', icon: Route },
  { to: '/posts', label: 'Post Moderation', icon: MessageSquareWarning },
  { to: '/announcements', label: 'Announcements', icon: Megaphone },
  { to: '/feedback', label: 'Feedback & Reports', icon: Bell },
  { to: '/settings', label: 'App Configuration', icon: Settings },
]

export function AppLayout() {
  const { user, role, logout } = useAuth()
  const navigate = useNavigate()

  const onLogout = async () => {
    await logout()
    navigate('/login')
  }

  return (
    <div className="layout">
      <aside className="sidebar">
        <div style={{ marginBottom: '1rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
            <div className="brand-badge">TPH</div>
            <div>
              <div style={{ fontSize: '1.3rem', fontWeight: 800, letterSpacing: '-0.02em', lineHeight: 1.05 }}>TransitPH</div>
              <div style={{ color: 'var(--text-secondary)', fontSize: '0.83rem' }}>Super Admin Console</div>
            </div>
          </div>
        </div>

        <div className="profile-card" style={{ marginBottom: '1rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.65rem' }}>
            <CircleUserRound size={34} color="var(--accent)" />
            <div>
              <div style={{ fontWeight: 700 }}>{user?.displayName ?? user?.email ?? 'Admin'}</div>
              <div style={{ color: 'var(--text-secondary)', textTransform: 'capitalize', fontSize: '0.85rem' }}>{role ?? 'superadmin'}</div>
            </div>
          </div>
        </div>

        <nav style={{ display: 'grid', gap: '0.35rem' }}>
          {links.map((item) => {
            const Icon = item.icon
            return (
              <NavLink key={item.to} to={item.to} end={item.to === '/'} className={({ isActive }: { isActive: boolean }) => `nav-link ${isActive ? 'active' : ''}`}>
                <Icon size={17} />
                <span>{item.label}</span>
              </NavLink>
            )
          })}
        </nav>

        <Button variant="outline" style={{ marginTop: '1rem', width: '100%' }} onClick={onLogout}>
          Log out
        </Button>
      </aside>

      <main className="main">
        <div className="page-shell">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
