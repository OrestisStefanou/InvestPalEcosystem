import { useState } from 'react'

import { useWorkflows } from '../hooks/useWorkflows'
import { absolute, relative, until } from '../util/format'
import EmptyState from './EmptyState'
import ErrorBanner from './ErrorBanner'
import { Info, Plus } from './Icons'
import WorkflowForm from './WorkflowForm'

export default function WorkflowsView() {
  const wf = useWorkflows()
  const [adding, setAdding] = useState(false)

  return (
    <div className="panel">
      <div className="panel-inner">
        <header className="panel-head">
          <p className="eyebrow">Scheduled work</p>
          <h2 className="h2">Reviews that run without you.</h2>
          <p className="deck">
            A workflow is an instruction plus a schedule. InvestPal keeps the schedule; the
            Claude Code cockpit runs each occurrence when it comes due and files the report here.
          </p>
          <div className="panel-actions">
            <button className="btn btn--primary" type="button" onClick={() => setAdding((v) => !v)}>
              <Plus /> New workflow
            </button>
          </div>
        </header>

        {wf.error && <ErrorBanner error={wf.error} onDismiss={() => wf.setError(null)} />}

        {adding && <WorkflowForm onSubmit={wf.create} onCancel={() => setAdding(false)} />}

        {wf.loading ? (
          <p className="loading">Loading workflows</p>
        ) : wf.workflows.length === 0 ? (
          <EmptyState title="No workflows yet">
            Schedule a recurring review and it runs whether or not you are at the machine. A
            weekly pass over your holdings is the usual starting point.
          </EmptyState>
        ) : (
          <div className="card-grid">
            {wf.workflows.map((w) => {
              const busy = wf.busyId === w.workflow_id
              return (
                <article className="card" key={w.workflow_id}>
                  <div className="card-top">
                    <h3>{w.name}</h3>
                    <span className={`pill pill--${w.status}`}>{w.status}</span>
                  </div>
                  <p className="card-desc">{w.description}</p>
                  <div className="card-meta">
                    <span>schedule <b>{w.schedule}</b></span>
                    <span>
                      next{' '}
                      <b>{w.status === 'active' ? until(w.next_run_at) : 'paused'}</b>
                      {w.status === 'active' && w.next_run_at && ` (${absolute(w.next_run_at)})`}
                    </span>
                    <span>last run <b>{w.last_run_at ? relative(w.last_run_at) : 'never'}</b></span>
                  </div>
                  <div className="card-actions">
                    {w.status === 'running' ? (
                      // A workflow stuck in `running` is a crashed run whose lock
                      // was never released. It will never come up as due again,
                      // so offer the reset rather than hiding the state.
                      <button
                        className="btn btn--ghost btn--sm"
                        type="button"
                        disabled={busy}
                        onClick={() => void wf.patch(w.workflow_id, { status: 'active' })}
                      >
                        Clear stuck run
                      </button>
                    ) : (
                      <button
                        className="btn btn--ghost btn--sm"
                        type="button"
                        disabled={busy}
                        onClick={() =>
                          void wf.patch(w.workflow_id, {
                            status: w.status === 'active' ? 'paused' : 'active',
                          })
                        }
                      >
                        {w.status === 'active' ? 'Pause' : 'Resume'}
                      </button>
                    )}
                    <button
                      className="btn btn--danger btn--sm"
                      type="button"
                      disabled={busy}
                      onClick={() => {
                        if (window.confirm(`Delete "${w.name}"? Past reports are kept.`)) {
                          void wf.remove(w.workflow_id)
                        }
                      }}
                    >
                      Delete
                    </button>
                  </div>
                </article>
              )
            })}
          </div>
        )}

        <header className="panel-head" style={{ marginTop: 'clamp(2.5rem, 5vw, 3.5rem)' }}>
          <p className="eyebrow">Past runs</p>
          <h2 className="h2">What came back.</h2>
        </header>

        {wf.results.length === 0 ? (
          <div className="banner">
            <Info />
            <p>
              No reports yet. A workflow files one each time the cockpit runs it, and reports
              are kept even after the workflow itself is deleted.
            </p>
          </div>
        ) : (
          <div className="card-grid">
            {wf.results.map((r) => (
              <article className="result" key={r.result_id}>
                <div className="card-top">
                  <h3>{r.workflow_name}</h3>
                  <span className="card-meta" style={{ marginTop: 0 }}>{absolute(r.ran_at)}</span>
                </div>
                <div className="result-output">{r.output}</div>
              </article>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
