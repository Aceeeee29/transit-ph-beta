import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { doc, getDoc, serverTimestamp, setDoc } from 'firebase/firestore'
import { useState } from 'react'
import { db } from '@/lib/firebase'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { Textarea } from '@/components/ui/textarea'

type UpdateSettings = {
  latest_version: string
  update_url: string
  force_update: boolean
  update_message: string
}

async function getUpdateConfig(): Promise<UpdateSettings> {
  const snap = await getDoc(doc(db, 'app_config', 'update_checker'))
  if (!snap.exists()) {
    return {
      latest_version: '1.0.0',
      update_url: '',
      force_update: false,
      update_message: '',
    }
  }
  const data = snap.data()
  return {
    latest_version: data.latest_version ?? '1.0.0',
    update_url: data.update_url ?? '',
    force_update: Boolean(data.force_update),
    update_message: data.update_message ?? '',
  }
}

async function saveUpdateConfig(payload: UpdateSettings) {
  await setDoc(doc(db, 'app_config', 'update_checker'), {
    ...payload,
    updatedAt: serverTimestamp(),
  }, { merge: true })
}

export function SettingsPage() {
  const qc = useQueryClient()
  const { data, isLoading } = useQuery({ queryKey: ['update-config'], queryFn: getUpdateConfig })
  const [form, setForm] = useState<UpdateSettings | null>(null)

  const save = useMutation({
    mutationFn: saveUpdateConfig,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['update-config'] }),
  })

  const model = form ?? data

  if (isLoading || !model) return <p>Loading app configuration...</p>

  return (
    <div style={{ display: 'grid', gap: '1rem' }}>
      <div className="page-head">
        <div>
          <h2 style={{ margin: 0 }}>App Configuration</h2>
          <div style={{ color: 'var(--text-secondary)' }}>Control update system values used by mobile startup checks</div>
        </div>
      </div>

      <Card style={{ display: 'grid', gap: '0.7rem', maxWidth: 760 }}>
        <label>Latest Version</label>
        <Input value={model.latest_version} onChange={(e) => setForm({ ...model, latest_version: e.target.value })} />

        <label>Update URL</label>
        <Input value={model.update_url} onChange={(e) => setForm({ ...model, update_url: e.target.value })} />

        <label>Update Message</label>
        <Textarea rows={4} value={model.update_message} onChange={(e) => setForm({ ...model, update_message: e.target.value })} />

        <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <Switch checked={model.force_update} onCheckedChange={(checked) => setForm({ ...model, force_update: checked })} />
          Force Update
        </label>

        <Button onClick={() => save.mutate(model)}>{save.isPending ? 'Saving...' : 'Save Configuration'}</Button>
      </Card>

      <Card>
        <h3 style={{ marginTop: 0 }}>Platform Stats Summary</h3>
        <p style={{ marginBottom: 0, color: 'var(--text-secondary)' }}>
          This page stores update settings in app_config/update_checker. If your Flutter app currently reads Firebase Remote Config directly,
          add a sync worker or Cloud Function to mirror these values into Remote Config.
        </p>
      </Card>
    </div>
  )
}
