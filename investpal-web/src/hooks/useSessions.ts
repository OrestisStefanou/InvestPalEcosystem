import { useCallback, useEffect, useMemo, useState } from 'react'

import { ApiError, createSession, getSession, listSessions } from '../api/client'
import type { Message, SessionSummary } from '../api/types'

/**
 * History is held as {id, messages} together rather than as a bare message
 * array. Keeping the id alongside the payload means switching session derives
 * an empty transcript immediately, instead of clearing it in an effect and
 * rendering one frame of the previous conversation's messages under the new
 * session's name.
 */
interface Loaded {
  id: string
  messages: Message[]
}

export function useSessions() {
  const [sessions, setSessions] = useState<SessionSummary[]>([])
  const [activeId, setActiveId] = useState<string | null>(null)
  const [loaded, setLoaded] = useState<Loaded | null>(null)
  const [loadingList, setLoadingList] = useState(true)
  const [error, setError] = useState<ApiError | null>(null)

  const fresh = loaded !== null && loaded.id === activeId
  const messages = useMemo(() => (fresh ? loaded.messages : []), [fresh, loaded])
  const loadingHistory = activeId !== null && !fresh && error === null

  const refreshList = useCallback(async (signal?: AbortSignal) => {
    try {
      const list = await listSessions(signal)
      setSessions(list)
      return list
    } catch (err) {
      if (err instanceof ApiError && err.kind !== 'aborted') setError(err)
      return null
    } finally {
      setLoadingList(false)
    }
  }, [])

  // On first load, adopt the most recent session rather than opening a new one.
  // GET /sessions returns newest first, so that is the head of the list.
  useEffect(() => {
    const ac = new AbortController()
    void (async () => {
      const list = await refreshList(ac.signal)
      if (list && list.length > 0) setActiveId(list[0].session_id)
    })()
    return () => ac.abort()
  }, [refreshList])

  useEffect(() => {
    if (!activeId) return
    const ac = new AbortController()
    void (async () => {
      try {
        const s = await getSession(activeId, ac.signal)
        if (ac.signal.aborted) return
        setLoaded({ id: s.session_id, messages: s.messages })
        setError(null)
      } catch (err) {
        if (err instanceof ApiError && err.kind !== 'aborted') setError(err)
      }
    })()
    return () => ac.abort()
  }, [activeId])

  /** Mutates the active transcript only, so a late reply cannot land in the
      wrong conversation after the user has switched away. */
  const setMessages = useCallback(
    (fn: (prev: Message[]) => Message[]) => {
      setLoaded((prev) => (prev === null ? prev : { ...prev, messages: fn(prev.messages) }))
    },
    [],
  )

  const startSession = useCallback(async () => {
    setError(null)
    try {
      // No session_id: let InvestPal generate one. Supplying our own is what
      // risks the 409, and there is nothing to gain from choosing it here.
      const s = await createSession(
        `Session ${new Date().toLocaleString(undefined, {
          day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
        })}`,
      )
      setSessions((prev) => [
        { session_id: s.session_id, name: s.name, created_at: s.created_at },
        ...prev,
      ])
      setLoaded({ id: s.session_id, messages: [] })
      setActiveId(s.session_id)
      return s.session_id
    } catch (err) {
      if (err instanceof ApiError) setError(err)
      return null
    }
  }, [])

  return {
    sessions, activeId, setActiveId, messages, setMessages,
    loadingList, loadingHistory, error, setError,
    startSession, refreshList,
  }
}
