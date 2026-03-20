import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { deleteFeedback, getFeedback, getPosts, updateFeedbackStatus } from '@/lib/firestoreApi'
import { Card } from '@/components/ui/card'
import { Select } from '@/components/ui/select'
import { Table, Td, Th } from '@/components/ui/table'
import { Button } from '@/components/ui/button'

export function FeedbackPage() {
  const qc = useQueryClient()
  const { data = [], isLoading, isError, error } = useQuery({ queryKey: ['feedback'], queryFn: getFeedback })
  const { data: posts = [] } = useQuery({ queryKey: ['posts'], queryFn: getPosts })
  const [typeFilter, setTypeFilter] = useState('all')
  const [statusFilter, setStatusFilter] = useState('all')

  const list = useMemo(() => data
    .filter((f) => typeFilter === 'all' ? true : f.type === typeFilter)
    .filter((f) => statusFilter === 'all' ? true : f.status === statusFilter), [data, typeFilter, statusFilter])

  const refresh = () => qc.invalidateQueries({ queryKey: ['feedback'] })
  const resolve = useMutation({ mutationFn: (id: string) => updateFeedbackStatus(id, 'resolved'), onSuccess: refresh })
  const dismiss = useMutation({ mutationFn: (id: string) => updateFeedbackStatus(id, 'dismissed'), onSuccess: refresh })
  const remove = useMutation({ mutationFn: (id: string) => deleteFeedback(id), onSuccess: refresh })

  return (
    <div style={{ display: 'grid', gap: '1rem' }}>
      <div className="page-head">
        <div>
          <h2 style={{ margin: 0 }}>Feedback & Reports</h2>
          <div style={{ color: 'var(--text-secondary)' }}>Track user feedback, reports, and resolution progress</div>
        </div>
      </div>
      <Card style={{ display: 'grid', gap: '0.6rem' }}>
        <div className="toolbar">
          <div></div>
          <Select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)}>
            <option value="all">All Types</option>
            <option value="feedback">Feedback</option>
            <option value="report">Report</option>
          </Select>
          <Select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
            <option value="all">All Statuses</option>
            <option value="pending">Pending</option>
            <option value="resolved">Resolved</option>
            <option value="dismissed">Dismissed</option>
          </Select>
          <div style={{ alignSelf: 'center' }}>{list.length} entries</div>
        </div>

        <div className="table-wrap">
          {isLoading ? <p>Loading feedback...</p> : isError ? (
            <div className="state-banner error">Failed to load feedback. {(error as Error | undefined)?.message ?? 'Try refreshing.'}</div>
          ) : !list.length ? (
            <div className="state-banner">No feedback entries for this filter combination.</div>
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th>Type</Th>
                  <Th>Status</Th>
                  <Th>Message / Reason</Th>
                  <Th>Reported Post</Th>
                  <Th>Date</Th>
                  <Th>Actions</Th>
                </tr>
              </thead>
              <tbody>
                {list.map((f) => {
                  const post = posts.find((p) => p.id === f.postId)
                  return (
                    <tr key={f.id}>
                      <Td>{f.type}</Td>
                      <Td>{f.status}</Td>
                      <Td>{f.reason || f.message}</Td>
                      <Td>{post ? post.content.slice(0, 90) : '-'}</Td>
                      <Td>{f.createdAt?.toDate().toLocaleString() ?? '-'}</Td>
                      <Td>
                        <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap' }}>
                          <Button size="sm" onClick={() => resolve.mutate(f.id)}>Resolve</Button>
                          <Button size="sm" variant="secondary" onClick={() => dismiss.mutate(f.id)}>Dismiss</Button>
                          <Button size="sm" variant="danger" onClick={() => { if (confirm('Delete feedback entry?')) remove.mutate(f.id) }}>Delete</Button>
                        </div>
                      </Td>
                    </tr>
                  )
                })}
              </tbody>
            </Table>
          )}
        </div>
      </Card>
    </div>
  )
}
