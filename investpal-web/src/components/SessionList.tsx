import type { SessionSummary } from '../api/types'
import { relative } from '../util/format'
import { Plus } from './Icons'

interface Props {
  sessions: SessionSummary[]
  activeId: string | null
  loading: boolean
  onSelect: (id: string) => void
  onNew: () => void
}

export default function SessionList({ sessions, activeId, loading, onSelect, onNew }: Props) {
  return (
    <aside className="sessions">
      <div className="sessions-head">
        <p className="eyebrow">Sessions</p>
        <button className="icon-btn" type="button" onClick={onNew} aria-label="New session" title="New session">
          <Plus />
        </button>
      </div>
      {loading ? (
        <p className="loading">Loading</p>
      ) : (
        <div className="sessions-list">
          {sessions.map((s) => (
            <button
              key={s.session_id}
              className="session"
              type="button"
              aria-current={s.session_id === activeId}
              onClick={() => onSelect(s.session_id)}
            >
              <span className="session-name">{s.name}</span>
              <span className="session-when">{relative(s.created_at)}</span>
            </button>
          ))}
        </div>
      )}
    </aside>
  )
}
