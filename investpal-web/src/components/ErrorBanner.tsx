import type { ApiError } from '../api/client'
import { Alert, Info } from './Icons'

interface Props {
  error: ApiError
  onDismiss?: () => void
}

/**
 * A missing provider key is the expected state on a default install, not a
 * fault, so that one is presented as information rather than an error.
 */
export default function ErrorBanner({ error, onDismiss }: Props) {
  const informational = error.kind === 'agent_unavailable'
  return (
    <div className={`banner${informational ? '' : ' banner--error'}`} role="alert">
      {informational ? <Info /> : <Alert />}
      <div>
        <p><strong>{error.message}</strong></p>
        {error.detail && <p className="banner-detail">{error.detail}</p>}
      </div>
      {onDismiss && (
        <button className="btn btn--ghost btn--sm" type="button" onClick={onDismiss}>
          Dismiss
        </button>
      )}
    </div>
  )
}
