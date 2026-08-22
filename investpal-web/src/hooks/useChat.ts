import { useCallback, useEffect, useRef, useState } from 'react'

import { ApiError, sendMessage } from '../api/client'
import type { Message } from '../api/types'

interface Args {
  sessionId: string | null
  onMessages: (fn: (prev: Message[]) => Message[]) => void
}

/**
 * One send is one long blocking POST. There is no streaming endpoint and no
 * progress signal, so the honest thing to show is real elapsed time, which is
 * what `startedAt` is for.
 */
export function useChat({ sessionId, onMessages }: Args) {
  const [pending, setPending] = useState(false)
  const [startedAt, setStartedAt] = useState<number | null>(null)
  /** Set when a reply has just arrived, so the view can reveal it gradually. */
  const [revealing, setRevealing] = useState<string | null>(null)
  const [error, setError] = useState<ApiError | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  // Abort on unmount and whenever the session changes: a reply that lands after
  // the user has switched away belongs to a conversation they are no longer in.
  useEffect(() => {
    return () => {
      abortRef.current?.abort()
      abortRef.current = null
    }
  }, [sessionId])

  const cancel = useCallback(() => {
    abortRef.current?.abort()
    abortRef.current = null
    setPending(false)
    setStartedAt(null)
  }, [])

  const send = useCallback(
    async (text: string) => {
      const body = text.trim()
      if (!body || !sessionId || pending) return

      setError(null)
      setPending(true)
      setStartedAt(Date.now())

      // Optimistic: the message is on screen before the round trip, and the
      // API will hand back the persisted copy on the next history load.
      onMessages((prev) => [...prev, { role: 'user', content: body, created_at: null }])

      const ac = new AbortController()
      abortRef.current = ac

      try {
        const { response } = await sendMessage(sessionId, body, ac.signal)
        onMessages((prev) => [...prev, { role: 'agent', content: response, created_at: null }])
        setRevealing(response)
      } catch (err) {
        if (err instanceof ApiError) {
          if (err.kind === 'aborted') return
          setError(err)
          // Drop the optimistic bubble: the API stored nothing, so leaving it
          // would show a message that does not exist on the next reload.
          onMessages((prev) => prev.slice(0, -1))
        }
      } finally {
        if (abortRef.current === ac) {
          abortRef.current = null
          setPending(false)
          setStartedAt(null)
        }
      }
    },
    [sessionId, pending, onMessages],
  )

  return { send, cancel, pending, startedAt, error, setError, revealing, setRevealing }
}
