import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { doc, getDoc, serverTimestamp, setDoc } from 'firebase/firestore'
import { useState } from 'react'
import { db } from '@/lib/firebase'
import { Switch } from '@/components/ui/switch'
import { AlertTriangle, CheckCircle, ExternalLink, Settings } from 'lucide-react'

type UpdateSettings = {
  latest_version: string
  update_url: string
  force_update: boolean
  update_message: string
}

async function getUpdateConfig(): Promise<UpdateSettings> {
  const snap = await getDoc(doc(db, 'app_config', 'update_checker'))
  if (!snap.exists()) return { latest_version: '1.0.0', update_url: '', force_update: false, update_message: '' }
  const d = snap.data()
  return {
    latest_version: d.latest_version ?? '1.0.0',
    update_url: d.update_url ?? '',
    force_update: Boolean(d.force_update),
    update_message: d.update_message ?? '',
  }
}

async function saveUpdateConfig(payload: UpdateSettings) {
  await setDoc(doc(db, 'app_config', 'update_checker'), { ...payload, updatedAt: serverTimestamp() }, { merge: true })
}

export function SettingsPage() {
  const qc = useQueryClient()
  const { data, isLoading } = useQuery({ queryKey: ['update-config'], queryFn: getUpdateConfig })
  const [form, setForm] = useState<UpdateSettings | null>(null)
  const [saved, setSaved] = useState(false)

  const save = useMutation({
    mutationFn: saveUpdateConfig,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['update-config'] })
      setSaved(true)
      setTimeout(() => setSaved(false), 3000)
    },
  })

  const model = form ?? data

  if (isLoading || !model) {
    return (
      <div style={{ display: 'grid', gap: 20 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div className="skeleton" style={{ width: 140, height: 20 }} />
          <div className="skeleton" style={{ width: 240, height: 14 }} />
        </div>
        <div style={{ background: 'var(--surface)', border: '1px solid var(--border-soft)', borderRadius: 16, padding: 20 }}>
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} style={{ marginBottom: 16 }}>
              <div className="skeleton" style={{ width: 100, height: 12, marginBottom: 8 }} />
              <div className="skeleton" style={{ height: 38 }} />
            </div>
          ))}
        </div>
      </div>
    )
  }

  const isDirty = JSON.stringify(form) !== JSON.stringify(data)

  return (
    <div style={{ display: 'grid', gap: 20 }} className="stagger">
      <div className="page-head">
        <div>
          <div className="page-head-title">App Configuration</div>
          <div className="page-head-subtitle">Control update system values used by mobile app startup checks and synced to Remote Config</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div className="stat-icon" style={{ background: 'var(--accent-soft)', width: 34, height: 34, borderRadius: 9 }}>
            <Settings size={16} color="var(--accent)" />
          </div>
        </div>
      </div>

      <div style={{ display: 'grid', gap: 14, maxWidth: 680 }}>
        {/* Update Checker Config */}
        <div className="settings-section">
          <div className="settings-title">Update Checker</div>

          <div className="form-group">
            <label>Latest App Version</label>
            <input
              type="text"
              placeholder="e.g. 1.2.0"
              value={model.latest_version}
              onChange={(e) => setForm({ ...model, latest_version: e.target.value })}
            />
          </div>

          <div className="form-group">
            <label>Update URL</label>
            <div style={{ position: 'relative' }}>
              <input
                type="text"
                placeholder="https://play.google.com/store/apps/…"
                value={model.update_url}
                onChange={(e) => setForm({ ...model, update_url: e.target.value })}
                style={{ paddingRight: 38 }}
              />
              {model.update_url && (
                <a
                  href={model.update_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--accent)' }}
                >
                  <ExternalLink size={14} />
                </a>
              )}
            </div>
          </div>

          <div className="form-group">
            <label>Update Message</label>
            <textarea
              rows={3}
              placeholder="Describe what's new in this version…"
              value={model.update_message}
              onChange={(e) => setForm({ ...model, update_message: e.target.value })}
              style={{ resize: 'vertical' }}
            />
          </div>

          {/* Force update toggle */}
          <div style={{
            display: 'flex', alignItems: 'flex-start', gap: 14, padding: 14,
            background: model.force_update ? 'var(--danger-soft)' : 'var(--background)',
            border: `1px solid ${model.force_update ? 'rgba(224,92,106,0.2)' : 'var(--border-soft)'}`,
            borderRadius: 10, transition: 'all 0.2s',
          }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 700, fontSize: '0.88rem', marginBottom: 3, color: model.force_update ? 'var(--danger)' : 'var(--text-primary)' }}>
                Force Update
              </div>
              <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)' }}>
                When enabled, users must update before continuing to use the app
              </div>
            </div>
            <Switch checked={model.force_update} onCheckedChange={(checked) => setForm({ ...model, force_update: checked })} />
          </div>

          {model.force_update && (
            <div className="state-banner error" style={{ fontSize: '0.8rem' }}>
              <AlertTriangle size={14} style={{ flexShrink: 0 }} />
              Force update is active — all users below v{model.latest_version} will be blocked until they update.
            </div>
          )}

          {/* Actions */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <button
              className="btn btn-primary"
              disabled={!isDirty || save.isPending}
              onClick={() => save.mutate(model)}
            >
              {save.isPending ? 'Saving…' : 'Save Configuration'}
            </button>

            {form && isDirty && (
              <button className="btn btn-outline" onClick={() => setForm(null)}>
                Reset
              </button>
            )}

            {saved && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 5, color: 'var(--success)', fontSize: '0.82rem', fontWeight: 600 }}>
                <CheckCircle size={14} /> Saved successfully
              </div>
            )}
          </div>

          <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)' }}>
            Note: Values are written to Firestore at <strong>app_config/update_checker</strong> and synced to Firebase Remote Config by the <strong>syncUpdateCheckerToRemoteConfig</strong> Cloud Function.
          </div>
        </div>
      </div>
    </div>
  )
}