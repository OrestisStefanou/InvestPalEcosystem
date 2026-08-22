import { useReminders } from '../hooks/useReminders'
import { dueLabel, relative } from '../util/format'
import EmptyState from './EmptyState'
import ErrorBanner from './ErrorBanner'
import { Info } from './Icons'

export default function RemindersView() {
  const { reminders, loading, error } = useReminders()

  return (
    <div className="panel">
      <div className="panel-inner">
        <header className="panel-head">
          <p className="eyebrow">Reminders</p>
          <h2 className="h2">What it is holding on to for you.</h2>
          <p className="deck">
            Things the agent decided were worth coming back to, from your conversations.
          </p>
        </header>

        {error && <ErrorBanner error={error} />}

        {/* Read-only on purpose, not an omission: the REST API has no
            POST /agent_reminders. Reminders are created by the agent through the
            MCP server while you are talking to it. */}
        <div className="banner">
          <Info />
          <p>
            Reminders are created in conversation, not here. Ask InvestPal to remind you about
            something and it will appear in this list.
          </p>
        </div>

        {loading ? (
          <p className="loading">Loading reminders</p>
        ) : reminders.length === 0 ? (
          <EmptyState title="Nothing outstanding">
            When you ask InvestPal to keep track of something, or it decides a holding is worth
            revisiting, it lands here.
          </EmptyState>
        ) : (
          <div className="card-grid">
            {reminders.map((r) => (
              <article className="card" key={r.id}>
                <div className="card-top">
                  <h3 style={{ fontWeight: 500 }}>{r.description}</h3>
                </div>
                <div className="card-meta">
                  <span><b>{dueLabel(r.due_date)}</b></span>
                  <span>noted {relative(r.created_at)}</span>
                </div>
              </article>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
