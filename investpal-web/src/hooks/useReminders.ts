import { useCallback, useEffect, useState } from 'react'

import { ApiError, listReminders } from '../api/client'
import type { Reminder } from '../api/types'

/** Read-only: the REST API exposes no way to create or edit a reminder. */
export function useReminders() {
  const [reminders, setReminders] = useState<Reminder[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<ApiError | null>(null)

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      setReminders(await listReminders(signal))
      setError(null)
    } catch (err) {
      if (err instanceof ApiError && err.kind !== 'aborted') setError(err)
    } finally {
      if (!signal?.aborted) setLoading(false)
    }
  }, [])

  useEffect(() => {
    const ac = new AbortController()
    // Fetch on mount. The setStates happen after an await, inside the
    // promise, not synchronously in the effect body; the rule is static and
    // cannot tell the difference.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load(ac.signal)
    return () => ac.abort()
  }, [load])

  return { reminders, loading, error, reload: () => load() }
}
