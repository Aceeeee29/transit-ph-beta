import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { getModeratorStats, updateUserRole } from '@/lib/firestoreApi'
import { Table, Td, Th } from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'

export function ModeratorsPage() {
  const qc = useQueryClient()
  const { data = [], isLoading, isError, error } = useQuery({ queryKey: ['moderators'], queryFn: getModeratorStats })

  const demote = useMutation({
    mutationFn: (id: string) => updateUserRole(id, 'user'),
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: ['moderators'] })
      await qc.invalidateQueries({ queryKey: ['users'] })
    },
  })

  return (
    <div style={{ display: 'grid', gap: '1rem' }}>
      <div className="page-head">
        <div>
          <h2 style={{ margin: 0 }}>Moderator Management</h2>
          <div style={{ color: 'var(--text-secondary)' }}>Superadmin-only controls for moderator roles and activity</div>
        </div>
      </div>

      <Card className="table-wrap">
        {isLoading ? <p>Loading moderators...</p> : isError ? (
          <div className="state-banner error">Failed to load moderators. {(error as Error | undefined)?.message ?? 'Try again.'}</div>
        ) : !data.length ? (
          <div className="state-banner">No moderators found.</div>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>Name</Th>
                <Th>Email</Th>
                <Th>Routes Approved</Th>
                <Th>Posts Moderated</Th>
                <Th>Action</Th>
              </tr>
            </thead>
            <tbody>
              {data.map((m) => (
                <tr key={m.id}>
                  <Td>{m.name}</Td>
                  <Td>{m.email}</Td>
                  <Td>{m.routesApproved}</Td>
                  <Td>{m.postsModerated}</Td>
                  <Td>
                    <Button variant="danger" size="sm" onClick={() => demote.mutate(m.id)}>Remove Moderator</Button>
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
