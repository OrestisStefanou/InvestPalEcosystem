import { useState } from 'react'

import type { CreateWorkflowBody } from '../api/types'

interface Props {
  onSubmit: (body: CreateWorkflowBody) => Promise<boolean>
  onCancel: () => void
}

/**
 * InvestPal takes a raw cron expression and validates it with croniter, so the
 * field stays a text input rather than a builder that would only cover a subset.
 * The presets are the schedules people actually want.
 */
const PRESETS: { label: string; cron: string }[] = [
  { label: 'Every weekday, 9am', cron: '0 9 * * 1-5' },
  { label: 'Mondays, 9am', cron: '0 9 * * 1' },
  { label: 'First of the month', cron: '0 9 1 * *' },
  { label: 'Every quarter', cron: '0 9 1 1,4,7,10 *' },
]

export default function WorkflowForm({ onSubmit, onCancel }: Props) {
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [schedule, setSchedule] = useState('0 9 * * 1')
  const [saving, setSaving] = useState(false)

  const valid = name.trim() && description.trim() && schedule.trim()

  return (
    <form
      className="form"
      onSubmit={async (e) => {
        e.preventDefault()
        if (!valid || saving) return
        setSaving(true)
        const ok = await onSubmit({
          name: name.trim(),
          description: description.trim(),
          schedule: schedule.trim(),
        })
        setSaving(false)
        if (ok) onCancel()
      }}
    >
      <div className="field">
        <label htmlFor="wf-name">Name</label>
        <input
          id="wf-name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Weekly portfolio review"
        />
      </div>

      <div className="field">
        <label htmlFor="wf-desc">Instructions</label>
        <textarea
          id="wf-desc"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="Review my holdings against their valuation procedures and flag anything that has moved materially."
        />
        <p className="field-note">
          This is the prompt the agent runs on each occurrence. Write it as an instruction.
        </p>
      </div>

      <div className="field field--mono">
        <label htmlFor="wf-cron">Schedule</label>
        <input
          id="wf-cron"
          value={schedule}
          onChange={(e) => setSchedule(e.target.value)}
          placeholder="0 9 * * 1"
          spellCheck={false}
        />
        <div className="cron-presets">
          {PRESETS.map((p) => (
            <button key={p.cron} className="cron-preset" type="button" onClick={() => setSchedule(p.cron)}>
              {p.label}
            </button>
          ))}
        </div>
        <p className="field-note">
          A cron expression: <code>minute hour day-of-month month day-of-week</code>.
        </p>
      </div>

      <div className="btn-row">
        <button className="btn btn--primary" type="submit" disabled={!valid || saving}>
          {saving ? 'Creating' : 'Create workflow'}
        </button>
        <button className="btn btn--ghost" type="button" onClick={onCancel}>
          Cancel
        </button>
      </div>
    </form>
  )
}
