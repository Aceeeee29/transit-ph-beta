import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { deleteRoute, getRoutes, updateRouteStatus } from '@/lib/firestoreApi'
import { useAuth } from '@/hooks/useAuth'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { CheckCircle, MapPin, Route, Search, ThumbsDown, ThumbsUp, Trash2, XCircle } from 'lucide-react'
import type { RouteItem } from '@/types/models'

const PAGE_SIZE = 12

function StatusBadge({ status }: { status?: string }) {
  if (status === 'approved') return <span className="badge badge-approved"><span className="badge-dot" />Approved</span>
  if (status === 'rejected') return <span className="badge badge-rejected"><span className="badge-dot" />Rejected</span>
  return <span className="badge badge-pending"><span className="badge-dot" />Pending</span>
}

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
    .filter((r) => statusFilter === 'all' || r.status === statusFilter)
    .filter((r) => `${r.startLocation ?? ''} ${r.endLocation ?? ''}`.toLowerCase().includes(search.toLowerCase())),
    [data, statusFilter, search])

  const totalPages = Math.max(1, Math.ceil(list.length / PAGE_SIZE))
  const paginated = list.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const refresh = () => qc.invalidateQueries({ queryKey: ['routes'] })
  const approve = useMutation({ mutationFn: (id: string) => updateRouteStatus(id, 'approved', user?.uid ?? ''), onSuccess: refresh })
  const reject = useMutation({ mutationFn: (id: string) => deleteRoute(id), onSuccess: refresh })
  const remove = useMutation({ mutationFn: (id: string) => deleteRoute(id), onSuccess: refresh })

  const bulkUpdate = async (status: 'approved' | 'rejected') => {
    if (status === 'approved') {
      await Promise.all(selectedIds.map((id) => updateRouteStatus(id, status, user?.uid ?? '')))
    } else {
      await Promise.all(selectedIds.map((id) => deleteRoute(id)))
    }
    setSelectedIds([])
    refresh()
  }

  const toggleAll = (checked: boolean) => {
    setSelectedIds(checked ? paginated.map((r) => r.id) : [])
  }

  const allChecked = paginated.length > 0 && paginated.every((r) => selectedIds.includes(r.id))

  return (
    <div style={{ display: 'grid', gap: 20 }} className="stagger">
      <div className="page-head">
        <div>
          <div className="page-head-title">Route Management</div>
          <div className="page-head-subtitle">Review and moderate user-submitted transit routes</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div className="stat-icon" style={{ background: 'var(--accent-soft)', width: 34, height: 34, borderRadius: 9 }}>
            <Route size={16} color="var(--accent)" />
          </div>
          <span style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--text-secondary)' }}>
            {list.length} routes
          </span>
        </div>
      </div>

      <div className="toolbar">
        <div className="toolbar-search" style={{ position: 'relative' }}>
          <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
          <input
            type="text"
            placeholder="Search origin or destination..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            style={{ paddingLeft: 32 }}
          />
        </div>
        <div className="toolbar-filters">
          <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1) }} style={{ width: 'auto' }}>
            <option value="all">All statuses</option>
            <option value="pending">Pending</option>
            <option value="approved">Approved</option>
            <option value="rejected">Rejected</option>
          </select>
        </div>
        <div className="toolbar-actions">
          <button className="btn btn-sm btn-success" disabled={!selectedIds.length} onClick={() => bulkUpdate('approved')}>
            <CheckCircle size={13} /> Bulk Approve ({selectedIds.length})
          </button>
          <button className="btn btn-sm btn-danger" disabled={!selectedIds.length} onClick={() => bulkUpdate('rejected')}>
            <XCircle size={13} /> Bulk Reject
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="table-wrap">
          <table>
            <thead><tr><th /><th>Start</th><th>End</th><th>Contributor</th><th>Date</th><th>Status</th><th>Views</th><th>Votes</th><th>Actions</th></tr></thead>
            <tbody>
              {Array.from({ length: 5 }).map((_, i) => (
                <tr key={i}>{Array.from({ length: 9 }).map((_, j) => <td key={j}><div className="skeleton" /></td>)}</tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : isError ? (
        <div className="state-banner error">
          Failed to load routes. {(error as Error | undefined)?.message ?? 'Try refreshing.'}
        </div>
      ) : !paginated.length ? (
        <div className="table-wrap">
          <div className="empty-state">
            <div className="empty-icon"><Route size={22} /></div>
            <div className="empty-title">No routes found</div>
            <div className="empty-sub">Adjust your filters or wait for users to submit new routes</div>
          </div>
        </div>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th style={{ width: 40 }}>
                  <input
                    type="checkbox"
                    checked={allChecked}
                    onChange={(e) => toggleAll(e.target.checked)}
                  />
                </th>
                <th>Origin</th>
                <th>Destination</th>
                <th>Contributor</th>
                <th>Submitted</th>
                <th>Status</th>
                <th>Views</th>
                <th>Votes</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {paginated.map((r) => (
                <tr key={r.id}>
                  <td>
                    <input
                      type="checkbox"
                      checked={selectedIds.includes(r.id)}
                      onChange={(e) => setSelectedIds((prev) =>
                        e.target.checked ? [...prev, r.id] : prev.filter((id) => id !== r.id)
                      )}
                    />
                  </td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <MapPin size={13} color="var(--accent)" style={{ flexShrink: 0 }} />
                      <span style={{ fontWeight: 600 }}>{r.startLocation}</span>
                    </div>
                  </td>
                  <td style={{ color: 'var(--text-secondary)' }}>{r.endLocation}</td>
                  <td style={{ fontSize: '0.81rem', color: 'var(--text-secondary)' }}>
                    {r.contributorName?.trim() || r.contributorEmail?.trim() || '-'}
                  </td>
                  <td style={{ fontSize: '0.81rem', color: 'var(--text-secondary)' }}>
                    {r.createdAt?.toDate().toLocaleDateString() ?? '-'}
                  </td>
                  <td><StatusBadge status={r.status} /></td>
                  <td style={{ fontWeight: 600 }}>{r.views ?? 0}</td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ display: 'flex', alignItems: 'center', gap: 3, fontSize: '0.8rem', color: 'var(--success)', fontWeight: 600 }}>
                        <ThumbsUp size={11} />{r.upvotes ?? 0}
                      </span>
                      <span style={{ display: 'flex', alignItems: 'center', gap: 3, fontSize: '0.8rem', color: 'var(--danger)', fontWeight: 600 }}>
                        <ThumbsDown size={11} />{r.downvotes ?? 0}
                      </span>
                    </div>
                  </td>
                  <td>
                    <div className="action-group">
                      {r.status !== 'approved' ? (
                        <>
                          <button className="btn btn-sm btn-success" onClick={() => approve.mutate(r.id)}>Approve</button>
                          <button className="btn btn-sm btn-danger" onClick={() => reject.mutate(r.id)}>Reject</button>
                        </>
                      ) : null}
                      <button className="btn btn-sm btn-outline" data-confirm-skip="true" onClick={() => setPreview(r)}>Preview</button>
                      {r.status === 'approved' ? (
                        <button
                          className="btn btn-sm btn-danger btn-icon"
                          title="Delete route"
                          onClick={() => { if (confirm('Delete this route?')) remove.mutate(r.id) }}
                        >
                          <Trash2 size={13} />
                        </button>
                      ) : null}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {!isLoading && !isError && (
        <div className="pagination">
          <span className="pagination-info">Showing {((page - 1) * PAGE_SIZE) + 1}-{Math.min(page * PAGE_SIZE, list.length)} of {list.length}</span>
          <div className="pagination-controls">
            <button className="page-btn" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>{'<'}</button>
            <span className="page-indicator">Page {page} / {totalPages}</span>
            <button className="page-btn" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>{'>'}</button>
          </div>
        </div>
      )}

      <Dialog open={Boolean(preview)} onOpenChange={(open) => !open && setPreview(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Route Preview</DialogTitle></DialogHeader>
          {preview && (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 0 16px', borderBottom: '1px solid var(--border-soft)', marginBottom: 4 }}>
                <div style={{ flex: 1 }}>
                  <span style={{ fontWeight: 700 }}>{preview.startLocation}</span>
                  <span style={{ color: 'var(--text-muted)', margin: '0 8px' }}>{'->'}</span>
                  <span style={{ fontWeight: 700 }}>{preview.endLocation}</span>
                </div>
                <StatusBadge status={preview.status} />
              </div>
              {[
                ['Steps', (preview.steps ?? []).join(' -> ') || 'No step data'],
                ['Transport Modes', (preview.transportModes ?? []).join(', ') || 'N/A'],
                ['ETA', `${preview.etaMinutes ?? 'N/A'} mins`],
                ['Fare Estimate', preview.fareEstimate ?? 'N/A'],
                ['Distance', `${preview.distanceKm ?? 'N/A'} km`],
              ].map(([label, value]) => (
                <div key={String(label)} className="dialog-field">
                  <span className="dialog-field-label">{label}</span>
                  <span className="dialog-field-value">{value}</span>
                </div>
              ))}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
