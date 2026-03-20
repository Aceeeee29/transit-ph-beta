import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { deleteRoute, getRoutes, updateRouteStatus } from '@/lib/firestoreApi'
import { useAuth } from '@/hooks/useAuth'
import { Card } from '@/components/ui/card'
import { Select } from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import { Table, Td, Th } from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import type { RouteItem } from '@/types/models'

const PAGE_SIZE = 12

export function RoutesPage() {
  const qc = useQueryClient()
  const { user } = useAuth()
  const { data = [], isLoading, isError, error } = useQuery({ queryKey: ['routes'], queryFn: getRoutes })
  const [statusFilter, setStatusFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [selectedIds, setSelectedIds] = useState<string[]>([])
  const [preview, setPreview] = useState<RouteItem | null>(null)
  const [page, setPage] = useState(1)

  const list = useMemo(() => data
    .filter((r) => (statusFilter === 'all' ? true : r.status === statusFilter))
    .filter((r) => `${r.startLocation} ${r.endLocation}`.toLowerCase().includes(search.toLowerCase())), [data, statusFilter, search])

  const totalPages = Math.max(1, Math.ceil(list.length / PAGE_SIZE))
  const paginated = list.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const refresh = () => qc.invalidateQueries({ queryKey: ['routes'] })

  const approve = useMutation({ mutationFn: (id: string) => updateRouteStatus(id, 'approved', user?.uid ?? ''), onSuccess: refresh })
  const reject = useMutation({ mutationFn: (id: string) => updateRouteStatus(id, 'rejected', user?.uid ?? ''), onSuccess: refresh })
  const remove = useMutation({ mutationFn: (id: string) => deleteRoute(id), onSuccess: refresh })

  const bulkUpdate = async (status: 'approved' | 'rejected') => {
    await Promise.all(selectedIds.map((id) => updateRouteStatus(id, status, user?.uid ?? '')))
    setSelectedIds([])
    refresh()
  }

  return (
    <div style={{ display: 'grid', gap: '1rem' }}>
      <div className="page-head">
        <div>
          <h2 style={{ margin: 0 }}>Route Management</h2>
          <div style={{ color: 'var(--text-secondary)' }}>Review submitted routes and moderate approval status</div>
        </div>
      </div>
      <Card style={{ display: 'grid', gap: '0.6rem' }}>
        <div className="toolbar">
          <Input placeholder="Search origin or destination" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} />
          <Select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="all">All statuses</option>
            <option value="pending">Pending</option>
            <option value="approved">Approved</option>
            <option value="rejected">Rejected</option>
          </Select>
          <Button onClick={() => bulkUpdate('approved')} disabled={!selectedIds.length}>Bulk Approve</Button>
          <Button variant="danger" onClick={() => bulkUpdate('rejected')} disabled={!selectedIds.length}>Bulk Reject</Button>
        </div>

        <div className="table-wrap">
          {isLoading ? <p>Loading routes...</p> : isError ? (
            <div className="state-banner error">Failed to load routes. {(error as Error | undefined)?.message ?? 'Try refreshing.'}</div>
          ) : !paginated.length ? (
            <div className="state-banner">No routes found for the selected filters.</div>
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th></Th>
                  <Th>Start</Th>
                  <Th>End</Th>
                  <Th>Contributor</Th>
                  <Th>Date Submitted</Th>
                  <Th>Status</Th>
                  <Th>Views</Th>
                  <Th>Upvotes</Th>
                  <Th>Downvotes</Th>
                  <Th>Actions</Th>
                </tr>
              </thead>
              <tbody>
                {paginated.map((r) => (
                  <tr key={r.id}>
                    <Td><input type="checkbox" checked={selectedIds.includes(r.id)} onChange={(e) => setSelectedIds((prev) => e.target.checked ? [...prev, r.id] : prev.filter((id) => id !== r.id))} /></Td>
                    <Td>{r.startLocation}</Td>
                    <Td>{r.endLocation}</Td>
                    <Td>{r.contributorName ?? r.contributorId}</Td>
                    <Td>{r.createdAt?.toDate().toLocaleDateString() ?? 'Unknown'}</Td>
                    <Td>{r.status}</Td>
                    <Td>{r.views}</Td>
                    <Td>{r.upvotes}</Td>
                    <Td>{r.downvotes}</Td>
                    <Td>
                      <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap' }}>
                        <Button size="sm" onClick={() => approve.mutate(r.id)}>Approve</Button>
                        <Button size="sm" variant="danger" onClick={() => reject.mutate(r.id)}>Reject</Button>
                        <Button size="sm" variant="outline" onClick={() => setPreview(r)}>Preview</Button>
                        <Button size="sm" variant="danger" onClick={() => { if (confirm('Delete route?')) remove.mutate(r.id) }}>Delete</Button>
                      </div>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
        </div>

        <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'flex-end' }}>
          <Button variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Prev</Button>
          <div style={{ alignSelf: 'center' }}>Page {page} / {totalPages}</div>
          <Button variant="outline" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>Next</Button>
        </div>
      </Card>

      <Dialog open={Boolean(preview)} onOpenChange={(open) => !open && setPreview(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Route Preview</DialogTitle></DialogHeader>
          {preview ? (
            <div style={{ display: 'grid', gap: '0.45rem' }}>
              <div><strong>Path:</strong> {preview.startLocation} to {preview.endLocation}</div>
              <div><strong>Steps:</strong> {(preview.steps ?? []).join(' -> ') || 'No step data'}</div>
              <div><strong>Transport Modes:</strong> {(preview.transportModes ?? []).join(', ') || 'N/A'}</div>
              <div><strong>ETA:</strong> {preview.etaMinutes ?? 'N/A'} mins</div>
              <div><strong>Fare Estimate:</strong> {preview.fareEstimate ?? 'N/A'}</div>
              <div><strong>Distance:</strong> {preview.distanceKm ?? 'N/A'} km</div>
            </div>
          ) : null}
        </DialogContent>
      </Dialog>
    </div>
  )
}
