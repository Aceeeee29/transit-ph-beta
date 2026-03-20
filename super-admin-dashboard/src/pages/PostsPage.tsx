import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { deletePost, getFeedback, getPosts, updateFeedbackStatus, updatePostStatus } from '@/lib/firestoreApi'
import { useAuth } from '@/hooks/useAuth'
import { Card } from '@/components/ui/card'
import { Select } from '@/components/ui/select'
import { Table, Td, Th } from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import type { PostItem } from '@/types/models'

export function PostsPage() {
  const qc = useQueryClient()
  const { user } = useAuth()
  const { data: posts = [], isLoading, isError, error } = useQuery({ queryKey: ['posts'], queryFn: getPosts })
  const { data: feedback = [] } = useQuery({ queryKey: ['feedback'], queryFn: getFeedback })
  const [statusFilter, setStatusFilter] = useState('all')
  const [preview, setPreview] = useState<PostItem | null>(null)

  const list = useMemo(() => posts.filter((p) => statusFilter === 'all' ? true : p.moderationStatus === statusFilter), [posts, statusFilter])

  const reportsByPost = useMemo(() => {
    const map = new Map<string, string[]>()
    feedback.filter((f) => f.type === 'report' && f.postId).forEach((f) => {
      const entry = map.get(f.postId!) ?? []
      entry.push(f.reason ?? f.message)
      map.set(f.postId!, entry)
    })
    return map
  }, [feedback])

  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ['posts'] })
    await qc.invalidateQueries({ queryKey: ['feedback'] })
  }

  const updateStatus = useMutation({
    mutationFn: ({ id, status }: { id: string; status: 'approved' | 'rejected' | 'flagged' }) => updatePostStatus(id, status, user?.uid ?? ''),
    onSuccess: refresh,
  })

  const remove = useMutation({ mutationFn: (id: string) => deletePost(id), onSuccess: refresh })
  const dismissReport = useMutation({ mutationFn: (id: string) => updateFeedbackStatus(id, 'dismissed'), onSuccess: refresh })

  return (
    <div style={{ display: 'grid', gap: '1rem' }}>
      <div className="page-head">
        <div>
          <h2 style={{ margin: 0 }}>Post & Content Moderation</h2>
          <div style={{ color: 'var(--text-secondary)' }}>Moderate community posts, reports, and visibility</div>
        </div>
      </div>
      <Card style={{ display: 'grid', gap: '0.7rem' }}>
        <Select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} style={{ maxWidth: 240 }}>
          <option value="all">All statuses</option>
          <option value="pending">Pending</option>
          <option value="approved">Approved</option>
          <option value="flagged">Flagged</option>
          <option value="rejected">Rejected</option>
        </Select>

        <div className="table-wrap">
          {isLoading ? <p>Loading posts...</p> : isError ? (
            <div className="state-banner error">Failed to load posts. {(error as Error | undefined)?.message ?? 'Check permissions and retry.'}</div>
          ) : !list.length ? (
            <div className="state-banner">No posts found for this status filter.</div>
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th>Author</Th>
                  <Th>Category</Th>
                  <Th>Content</Th>
                  <Th>Status</Th>
                  <Th>Reports</Th>
                  <Th>Actions</Th>
                </tr>
              </thead>
              <tbody>
                {list.map((p) => {
                  const reasons = reportsByPost.get(p.id) ?? []
                  return (
                    <tr key={p.id}>
                      <Td>{p.userName || p.userEmail || 'Anonymous'}</Td>
                      <Td>{p.category}</Td>
                      <Td>{p.content.slice(0, 80)}{p.content.length > 80 ? '...' : ''}</Td>
                      <Td>{p.moderationStatus}</Td>
                      <Td>{reasons.length ? reasons.join('; ') : '-'}</Td>
                      <Td>
                        <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap' }}>
                          <Button size="sm" onClick={() => updateStatus.mutate({ id: p.id, status: 'approved' })}>Approve</Button>
                          <Button size="sm" variant="danger" onClick={() => updateStatus.mutate({ id: p.id, status: 'rejected' })}>Remove</Button>
                          <Button size="sm" variant="secondary" onClick={() => updateStatus.mutate({ id: p.id, status: 'flagged' })}>Flag</Button>
                          <Button size="sm" variant="outline" onClick={() => setPreview(p)}>View</Button>
                          {feedback.filter((f) => f.postId === p.id && f.status === 'pending').map((f) => (
                            <Button key={f.id} size="sm" variant="outline" onClick={() => dismissReport.mutate(f.id)}>Dismiss Report</Button>
                          ))}
                          <Button size="sm" variant="danger" onClick={() => { if (confirm('Delete post?')) remove.mutate(p.id) }}>Delete</Button>
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

      <Dialog open={Boolean(preview)} onOpenChange={(open) => !open && setPreview(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Post Details</DialogTitle></DialogHeader>
          {preview ? (
            <div style={{ display: 'grid', gap: '0.45rem' }}>
              <div><strong>Author:</strong> {preview.userName || preview.userEmail || 'Anonymous'}</div>
              <div><strong>Category:</strong> {preview.category}</div>
              <div><strong>Content:</strong> {preview.content}</div>
              <div><strong>Images:</strong> {(preview.images ?? []).join(', ') || 'No images'}</div>
            </div>
          ) : null}
        </DialogContent>
      </Dialog>
    </div>
  )
}
