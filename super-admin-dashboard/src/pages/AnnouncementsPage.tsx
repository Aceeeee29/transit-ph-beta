import { useState } from 'react'
import { Timestamp } from 'firebase/firestore'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { createAnnouncement, deleteAnnouncement, getAnnouncements, updateAnnouncement } from '@/lib/firestoreApi'
import { useAuth } from '@/hooks/useAuth'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Select } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { Table, Td, Th } from '@/components/ui/table'
import { Button } from '@/components/ui/button'

function toIsoLocalValue(date: Date) {
  const off = date.getTimezoneOffset()
  const local = new Date(date.getTime() - off * 60_000)
  return local.toISOString().slice(0, 16)
}

export function AnnouncementsPage() {
  const qc = useQueryClient()
  const { user } = useAuth()
  const { data = [], isLoading, isError, error } = useQuery({ queryKey: ['announcements'], queryFn: getAnnouncements })

  const [title, setTitle] = useState('')
  const [message, setMessage] = useState('')
  const [type, setType] = useState<'info' | 'warning' | 'critical'>('info')
  const [targetAudience, setTargetAudience] = useState<'all' | 'student' | 'employee' | 'foreigner' | 'new_to_area'>('all')
  const [isActive, setIsActive] = useState(true)
  const [scheduleMode, setScheduleMode] = useState<'now' | 'scheduled'>('now')
  const [scheduledAt, setScheduledAt] = useState(toIsoLocalValue(new Date()))
  const [expiresAt, setExpiresAt] = useState(toIsoLocalValue(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)))

  const refresh = () => qc.invalidateQueries({ queryKey: ['announcements'] })

  const create = useMutation({
    mutationFn: () => createAnnouncement({
      title,
      message,
      type,
      targetAudience,
      isActive,
      scheduledAt: scheduleMode === 'now' ? Timestamp.now() : Timestamp.fromDate(new Date(scheduledAt)),
      expiresAt: Timestamp.fromDate(new Date(expiresAt)),
      createdBy: user?.uid ?? '',
    }),
    onSuccess: () => {
      setTitle('')
      setMessage('')
      refresh()
    },
  })

  const toggleActive = useMutation({
    mutationFn: ({ id, active }: { id: string; active: boolean }) => updateAnnouncement(id, { isActive: active }),
    onSuccess: refresh,
  })

  const remove = useMutation({ mutationFn: (id: string) => deleteAnnouncement(id), onSuccess: refresh })

  return (
    <div style={{ display: 'grid', gap: '1rem' }}>
      <div className="page-head">
        <div>
          <h2 style={{ margin: 0 }}>Announcements</h2>
          <div style={{ color: 'var(--text-secondary)' }}>Create one-time modal notices for app users by audience</div>
        </div>
      </div>

      <Card style={{ display: 'grid', gap: '0.6rem' }}>
        <h3 style={{ marginTop: 0 }}>Create Announcement</h3>
        <Input placeholder="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
        <Textarea rows={4} placeholder="Message body" value={message} onChange={(e) => setMessage(e.target.value)} />

        <div style={{ display: 'grid', gap: '0.6rem', gridTemplateColumns: 'repeat(auto-fit, minmax(170px, 1fr))' }}>
          <Select value={type} onChange={(e) => setType(e.target.value as typeof type)}>
            <option value="info">Info</option>
            <option value="warning">Warning</option>
            <option value="critical">Critical</option>
          </Select>

          <Select value={targetAudience} onChange={(e) => setTargetAudience(e.target.value as typeof targetAudience)}>
            <option value="all">All</option>
            <option value="student">Student</option>
            <option value="employee">Employee</option>
            <option value="foreigner">Foreigner</option>
            <option value="new_to_area">New To Area</option>
          </Select>

          <Select value={scheduleMode} onChange={(e) => setScheduleMode(e.target.value as 'now' | 'scheduled')}>
            <option value="now">Publish Immediately</option>
            <option value="scheduled">Schedule</option>
          </Select>

          <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <Switch checked={isActive} onCheckedChange={setIsActive} /> Active
          </label>
        </div>

        {scheduleMode === 'scheduled' ? (
          <Input type="datetime-local" value={scheduledAt} onChange={(e) => setScheduledAt(e.target.value)} />
        ) : null}
        <Input type="datetime-local" value={expiresAt} onChange={(e) => setExpiresAt(e.target.value)} />

        <Button onClick={() => create.mutate()} disabled={!title || !message}>{create.isPending ? 'Creating...' : 'Create Announcement'}</Button>
      </Card>

      <Card className="table-wrap">
        {isLoading ? <p>Loading announcements...</p> : isError ? (
          <div className="state-banner error">Failed to load announcements. {(error as Error | undefined)?.message ?? 'Check Firestore permissions.'}</div>
        ) : !data.length ? (
          <div className="state-banner">No announcements yet. Create one to notify mobile users.</div>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>Title</Th>
                <Th>Type</Th>
                <Th>Audience</Th>
                <Th>Status</Th>
                <Th>Scheduled</Th>
                <Th>Expires</Th>
                <Th>Actions</Th>
              </tr>
            </thead>
            <tbody>
              {data.map((a) => (
                <tr key={a.id}>
                  <Td>{a.title}</Td>
                  <Td>{a.type}</Td>
                  <Td>{a.targetAudience}</Td>
                  <Td>{a.isActive ? 'Active' : 'Inactive'}</Td>
                  <Td>{a.scheduledAt?.toDate().toLocaleString() ?? '-'}</Td>
                  <Td>{a.expiresAt?.toDate().toLocaleString() ?? '-'}</Td>
                  <Td>
                    <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap' }}>
                      <Button size="sm" variant="secondary" onClick={() => toggleActive.mutate({ id: a.id, active: !a.isActive })}>{a.isActive ? 'Deactivate' : 'Activate'}</Button>
                      <Button size="sm" variant="danger" onClick={() => { if (confirm('Delete announcement?')) remove.mutate(a.id) }}>Delete</Button>
                    </div>
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </div>
  )
}
