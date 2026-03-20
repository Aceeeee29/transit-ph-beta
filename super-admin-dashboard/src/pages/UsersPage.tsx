import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { deleteUser, getUsers, setUserBanStatus, updateUserRole } from '@/lib/firestoreApi'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Table, Td, Th } from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import type { AppUser } from '@/types/models'

const PAGE_SIZE = 12

export function UsersPage() {
  const qc = useQueryClient()
  const { data = [], isLoading, isError, error } = useQuery({ queryKey: ['users'], queryFn: getUsers })

  const [search, setSearch] = useState('')
  const [roleFilter, setRoleFilter] = useState('all')
  const [statusFilter, setStatusFilter] = useState('all')
  const [sortBy, setSortBy] = useState<keyof AppUser>('name')
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc')
  const [page, setPage] = useState(1)
  const [selectedUser, setSelectedUser] = useState<AppUser | null>(null)
  const [banConfirmId, setBanConfirmId] = useState<string | null>(null)
  const [banTypedText, setBanTypedText] = useState('')

  const list = useMemo(() => {
    const filtered = data
      .filter((u) => (roleFilter === 'all' ? true : u.role === roleFilter))
      .filter((u) => (statusFilter === 'all' ? true : u.status === statusFilter))
      .filter((u) => `${u.name} ${u.email}`.toLowerCase().includes(search.toLowerCase()))
      .sort((a, b) => {
        const av = String(a[sortBy] ?? '')
        const bv = String(b[sortBy] ?? '')
        return sortDir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av)
      })

    return filtered
  }, [data, roleFilter, search, sortBy, sortDir, statusFilter])

  const totalPages = Math.max(1, Math.ceil(list.length / PAGE_SIZE))
  const paginated = list.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const invalidate = async () => {
    await qc.invalidateQueries({ queryKey: ['users'] })
    await qc.invalidateQueries({ queryKey: ['moderators'] })
  }

  const promote = useMutation({ mutationFn: (id: string) => updateUserRole(id, 'moderator'), onSuccess: invalidate })
  const demote = useMutation({ mutationFn: (id: string) => updateUserRole(id, 'user'), onSuccess: invalidate })
  const ban = useMutation({ mutationFn: (id: string) => setUserBanStatus(id, true), onSuccess: invalidate })
  const unban = useMutation({ mutationFn: (id: string) => setUserBanStatus(id, false), onSuccess: invalidate })
  const remove = useMutation({ mutationFn: (id: string) => deleteUser(id), onSuccess: invalidate })

  const toggleSort = (field: keyof AppUser) => {
    if (field === sortBy) {
      setSortDir((p) => (p === 'asc' ? 'desc' : 'asc'))
      return
    }
    setSortBy(field)
    setSortDir('asc')
  }

  return (
    <div style={{ display: 'grid', gap: '1rem' }}>
      <div className="page-head">
        <div>
          <h2 style={{ margin: 0 }}>User Management</h2>
          <div style={{ color: 'var(--text-secondary)' }}>Manage account roles, status, and profile insights</div>
        </div>
      </div>

      <Card style={{ display: 'grid', gap: '0.6rem' }}>
        <div className="toolbar">
          <Input placeholder="Search by name or email" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} />
          <Select value={roleFilter} onChange={(e) => { setRoleFilter(e.target.value); setPage(1) }}>
            <option value="all">All Roles</option>
            <option value="user">User</option>
            <option value="moderator">Moderator</option>
            <option value="superadmin">Superadmin</option>
          </Select>
          <Select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="all">All Statuses</option>
            <option value="active">Active</option>
            <option value="banned">Banned</option>
          </Select>
          <div style={{ display: 'grid', placeItems: 'center start', color: 'var(--text-secondary)' }}>{list.length} users</div>
        </div>

        <div className="table-wrap">
          {isLoading ? <p>Loading users...</p> : isError ? (
            <div className="state-banner error">
              Failed to load users. {(error as Error | undefined)?.message ?? 'Check Firestore rules and role permissions.'}
            </div>
          ) : !paginated.length ? (
            <div className="state-banner">No users found for the current filters.</div>
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th onClick={() => toggleSort('name')}>Name</Th>
                  <Th onClick={() => toggleSort('email')}>Email</Th>
                  <Th onClick={() => toggleSort('role')}>Role</Th>
                  <Th>Status</Th>
                  <Th onClick={() => toggleSort('createdAt')}>Date Joined</Th>
                  <Th>Routes Contributed</Th>
                  <Th>Actions</Th>
                </tr>
              </thead>
              <tbody>
                {paginated.map((u) => (
                  <tr key={u.id}>
                    <Td><button style={{ border: 0, background: 'none', color: 'var(--accent)', cursor: 'pointer' }} onClick={() => setSelectedUser(u)}>{u.name}</button></Td>
                    <Td>{u.email}</Td>
                    <Td><Badge>{u.role}</Badge></Td>
                    <Td><Badge className={u.status === 'banned' ? 'bg-[#ffe7eb]' : 'bg-[#eafff2]'}>{u.status}</Badge></Td>
                    <Td>{u.createdAt?.toDate().toLocaleDateString() ?? 'Unknown'}</Td>
                    <Td>{u.routesContributed}</Td>
                    <Td>
                      <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap' }}>
                        {u.role !== 'moderator' ? <Button size="sm" onClick={() => promote.mutate(u.id)}>Promote</Button> : <Button size="sm" variant="outline" onClick={() => demote.mutate(u.id)}>Demote</Button>}
                        {u.status === 'banned' ? <Button size="sm" variant="secondary" onClick={() => unban.mutate(u.id)}>Unban</Button> : <Button size="sm" variant="danger" onClick={() => setBanConfirmId(u.id)}>Ban</Button>}
                        <Button size="sm" variant="danger" onClick={() => { if (confirm('Delete account permanently?')) remove.mutate(u.id) }}>Delete</Button>
                      </div>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
        </div>

        {!isLoading && !isError && paginated.length > 0 ? (
          <div className="mobile-cards">
            {paginated.map((u) => (
              <div key={`card-${u.id}`} className="mobile-user-card">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <button style={{ border: 0, background: 'none', color: 'var(--accent)', cursor: 'pointer', fontWeight: 700, padding: 0 }} onClick={() => setSelectedUser(u)}>{u.name}</button>
                  <Badge>{u.role}</Badge>
                </div>
                <div style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>{u.email || 'No email'}</div>
                <div style={{ display: 'flex', gap: '0.4rem', flexWrap: 'wrap' }}>
                  <Badge className={u.status === 'banned' ? 'bg-[#ffe7eb]' : 'bg-[#eafff2]'}>{u.status}</Badge>
                  <Badge>{u.routesContributed} routes</Badge>
                </div>
                <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap' }}>
                  {u.role !== 'moderator' ? <Button size="sm" onClick={() => promote.mutate(u.id)}>Promote</Button> : <Button size="sm" variant="outline" onClick={() => demote.mutate(u.id)}>Demote</Button>}
                  {u.status === 'banned' ? <Button size="sm" variant="secondary" onClick={() => unban.mutate(u.id)}>Unban</Button> : <Button size="sm" variant="danger" onClick={() => setBanConfirmId(u.id)}>Ban</Button>}
                </div>
              </div>
            ))}
          </div>
        ) : null}

        <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'flex-end' }}>
          <Button variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Prev</Button>
          <div style={{ alignSelf: 'center' }}>Page {page} / {totalPages}</div>
          <Button variant="outline" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>Next</Button>
        </div>
      </Card>

      <Dialog open={Boolean(selectedUser)} onOpenChange={(open) => !open && setSelectedUser(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>User Profile Details</DialogTitle></DialogHeader>
          {selectedUser ? (
            <div style={{ display: 'grid', gap: '0.45rem' }}>
              <div><strong>Name:</strong> {selectedUser.name}</div>
              <div><strong>Email:</strong> {selectedUser.email}</div>
              <div><strong>Role:</strong> {selectedUser.role}</div>
              <div><strong>Badges:</strong> {(selectedUser.badges ?? []).join(', ') || 'None'}</div>
              <div><strong>Achievements:</strong> {(selectedUser.achievements ?? []).join(', ') || 'None'}</div>
              <div><strong>Streak Days:</strong> {selectedUser.streakDays ?? 0}</div>
              <div><strong>Contribution Count:</strong> {selectedUser.contributionCount ?? 0}</div>
            </div>
          ) : null}
        </DialogContent>
      </Dialog>

      <Dialog open={Boolean(banConfirmId)} onOpenChange={(open) => { if (!open) { setBanConfirmId(null); setBanTypedText('') } }}>
        <DialogContent>
          <DialogHeader><DialogTitle>Confirm Ban</DialogTitle></DialogHeader>
          <p style={{ color: 'var(--text-secondary)' }}>Type BAN to proceed. This matches the in-app safety pattern.</p>
          <Input value={banTypedText} onChange={(e) => setBanTypedText(e.target.value)} placeholder="BAN" />
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.5rem' }}>
            <Button variant="outline" onClick={() => { setBanConfirmId(null); setBanTypedText('') }}>Cancel</Button>
            <Button variant="danger" disabled={banTypedText !== 'BAN'} onClick={() => {
              if (banConfirmId) ban.mutate(banConfirmId)
              setBanConfirmId(null)
              setBanTypedText('')
            }}>Ban User</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
