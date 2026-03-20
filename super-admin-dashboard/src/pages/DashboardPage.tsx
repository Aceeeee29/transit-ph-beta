import { useQuery } from '@tanstack/react-query'
import { BarChart, Bar, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { getDashboardStats } from '@/lib/firestoreApi'
import { Card } from '@/components/ui/card'

export function DashboardPage() {
  const { data, isLoading, error } = useQuery({ queryKey: ['dashboard-stats'], queryFn: getDashboardStats })

  if (isLoading) return <p>Loading dashboard...</p>
  if (error || !data) {
    return (
      <div className="state-banner error">
        Could not load dashboard data. {(error as Error | undefined)?.message ?? 'Check Firestore permissions and timestamp field formats.'}
      </div>
    )
  }

  return (
    <div style={{ display: 'grid', gap: '1rem' }}>
      <div className="page-head">
        <div>
          <h2 style={{ margin: 0 }}>Dashboard Home</h2>
          <div style={{ color: 'var(--text-secondary)' }}>Platform-wide live summary and growth metrics</div>
        </div>
      </div>

      <div className="grid-stats">
        <Card><strong>Total Users</strong><div style={{ fontSize: '1.5rem', marginTop: '0.5rem', fontWeight: 800 }}>{data.totalUsers}</div></Card>
        <Card><strong>Active Users</strong><div style={{ fontSize: '1.5rem', marginTop: '0.5rem', fontWeight: 800 }}>{data.activeUsers}</div></Card>
        <Card><strong>Banned Users</strong><div style={{ fontSize: '1.5rem', marginTop: '0.5rem', fontWeight: 800 }}>{data.bannedUsers}</div></Card>
        <Card><strong>Routes</strong><div style={{ marginTop: '0.5rem' }}>A:{data.routes.approved} P:{data.routes.pending} R:{data.routes.rejected}</div></Card>
        <Card><strong>Posts</strong><div style={{ marginTop: '0.5rem' }}>A:{data.posts.approved} P:{data.posts.pending} F:{data.posts.flagged}</div></Card>
      </div>

      <div style={{ display: 'grid', gap: '1rem', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))' }}>
        <Card>
          <h3 style={{ marginTop: 0 }}>User Growth Over Time</h3>
          <div style={{ width: '100%', height: 260 }}>
            <ResponsiveContainer>
              <LineChart data={data.userGrowth}>
                <CartesianGrid strokeDasharray="3 3" stroke="#dbe8fb" />
                <XAxis dataKey="label" />
                <YAxis allowDecimals={false} />
                <Tooltip />
                <Line type="monotone" dataKey="count" stroke="#2E7CF6" strokeWidth={3} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </Card>

        <Card>
          <h3 style={{ marginTop: 0 }}>Routes Contributed Per Week</h3>
          <div style={{ width: '100%', height: 260 }}>
            <ResponsiveContainer>
              <BarChart data={data.routesPerWeek}>
                <CartesianGrid strokeDasharray="3 3" stroke="#dbe8fb" />
                <XAxis dataKey="label" />
                <YAxis allowDecimals={false} />
                <Tooltip />
                <Bar dataKey="count" fill="#2E7CF6" radius={[8, 8, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>
      </div>

      <Card>
        <h3 style={{ marginTop: 0 }}>Recent Activity Feed</h3>
        <div style={{ display: 'grid', gap: '0.5rem' }}>
          {data.recentActivity.map((item) => (
            <div key={item.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '0.6rem', borderRadius: '0.75rem', background: 'var(--surface-alt)' }}>
              <span>{item.description}</span>
              <span style={{ color: 'var(--text-secondary)' }}>{item.time}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  )
}
