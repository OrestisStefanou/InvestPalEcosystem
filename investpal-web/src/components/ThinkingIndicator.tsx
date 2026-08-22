import { useEffect, useState } from 'react'

import { elapsed } from '../util/format'
import { Stop } from './Icons'

interface Props {
  startedAt: number
  onCancel: () => void
}

/**
 * POST /chat blocks for the whole agent run, which is routinely minutes, and
 * the API sends nothing until it is finished. So this shows the one thing that
 * is actually true: how long it has been waiting. It deliberately does not draw
 * a progress bar or a fake token stream.
 */
export default function ThinkingIndicator({ startedAt, onCancel }: Props) {
  // Seeded from the prop rather than Date.now(): reading the clock during
  // render is impure, and the interval below corrects it within a second.
  const [now, setNow] = useState(startedAt)

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

  const ms = Math.max(0, now - startedAt)
  const long = ms > 45_000

  return (
    <div className="thinking">
      <div className="thinking-bar">
        <span>working</span>
        <span className="thinking-elapsed">{elapsed(ms)}</span>
      </div>
      <div className="thinking-body">
        <span className="caret">&gt;</span> pulling data and running the procedure
        <span className="dots"><span>.</span><span>.</span><span>.</span></span>
        <p className="thinking-note">
          {long
            ? 'Still going. Research runs that pull filings and walk a valuation procedure take several minutes.'
            : 'The reply arrives all at once. There is no progress to report until it does.'}
        </p>
        <div className="btn-row" style={{ marginTop: '.9rem' }}>
          {/* "Stop waiting", not "cancel": aborting the fetch releases this
              tab, but the agent run carries on server-side and its reply is
              still written to the session. Reload to see it. */}
          <button
            className="btn btn--ghost btn--sm"
            type="button"
            onClick={onCancel}
            title="Stops waiting here. The agent keeps running and its reply is still saved to this session."
          >
            <Stop /> Stop waiting
          </button>
        </div>
      </div>
    </div>
  )
}
