import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  createWorkflow,
  deleteWorkflow,
  listWorkflowResults,
  listWorkflows,
  updateWorkflow,
} from '../api/client'
import type { CreateWorkflowBody, UpdateWorkflowBody, Workflow, WorkflowResult } from '../api/types'

export function useWorkflows() {
  const [workflows, setWorkflows] = useState<Workflow[]>([])
  const [results, setResults] = useState<WorkflowResult[]>([])
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [error, setError] = useState<ApiError | null>(null)

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      // Independent reads, so no reason to serialise them.
      const [w, r] = await Promise.all([listWorkflows(signal), listWorkflowResults(20, signal)])
      setWorkflows(w)
      setResults(r)
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

  const create = useCallback(async (body: CreateWorkflowBody) => {
    setError(null)
    try {
      const w = await createWorkflow(body)
      setWorkflows((prev) => [...prev, w])
      return true
    } catch (err) {
      if (err instanceof ApiError) setError(err)
      return false
    }
  }, [])

  const patch = useCallback(async (id: string, body: UpdateWorkflowBody) => {
    setError(null)
    setBusyId(id)
    try {
      const w = await updateWorkflow(id, body)
      setWorkflows((prev) => prev.map((x) => (x.workflow_id === id ? w : x)))
      return true
    } catch (err) {
      if (err instanceof ApiError) setError(err)
      return false
    } finally {
      setBusyId(null)
    }
  }, [])

  const remove = useCallback(async (id: string) => {
    setError(null)
    setBusyId(id)
    try {
      await deleteWorkflow(id)
      // Results outlive their workflow by design, so `results` is left alone.
      setWorkflows((prev) => prev.filter((x) => x.workflow_id !== id))
      return true
    } catch (err) {
      if (err instanceof ApiError) setError(err)
      return false
    } finally {
      setBusyId(null)
    }
  }, [])

  return { workflows, results, loading, busyId, error, setError, create, patch, remove, reload: () => load() }
}
