// The only place this app talks to InvestPal. Ten endpoints, no auth, no
// headers beyond content-type: InvestPal is single-user and unauthenticated by
// design (InvestPal/docs/rest_api.md: "No endpoint requires authentication
// headers"), and commit 50f17ac removed the last request headers it accepted.
//
// InvestPal/main.py sets CORSMiddleware(allow_origins=["*"],
// allow_credentials=false), so the browser reaches localhost:8000 directly and
// no dev proxy is needed.

import type {
  CreateWorkflowBody,
  Reminder,
  Session,
  SessionSummary,
  UpdateWorkflowBody,
  Workflow,
  WorkflowResult,
} from './types'

export const API_BASE: string =
  import.meta.env.VITE_INVESTPAL_API_URL ?? 'http://localhost:8000'

/**
 * Why a class rather than a status code: the three failures a user hits look
 * nothing alike and each needs different words on screen. Losing the
 * distinction is how the old dev UI ended up showing "Internal Server Error"
 * for a missing provider key.
 */
export type FailureKind =
  /** fetch itself rejected: nothing is listening. The backend is down. */
  | 'offline'
  /** 404. Usually a session id that no longer exists. */
  | 'not_found'
  /** 409. A session id that is already taken. */
  | 'conflict'
  /**
   * 500 from /chat. On a default install this is expected, not a bug:
   * `make setup` defaults the backend-agent question to no, so there is no
   * provider key and only /chat fails. main.py's global_exception_handler
   * returns a bare {"detail": "Internal Server Error"}, so the explanation has
   * to come from here.
   */
  | 'agent_unavailable'
  | 'server'
  | 'aborted'

export class ApiError extends Error {
  readonly kind: FailureKind
  readonly status: number | null
  /** Second paragraph: the why and the fix, when there is one worth stating. */
  readonly detail: string | null

  constructor(
    kind: FailureKind,
    message: string,
    status: number | null = null,
    detail: string | null = null,
  ) {
    super(message)
    this.name = 'ApiError'
    this.kind = kind
    this.status = status
    this.detail = detail
  }
}

interface RequestOptions {
  method?: string
  body?: unknown
  signal?: AbortSignal
  /** Marks /chat, whose 500 means "no provider key" rather than a real fault. */
  isChat?: boolean
}

async function request<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const { method = 'GET', body, signal, isChat = false } = opts

  let res: Response
  try {
    res = await fetch(`${API_BASE}${path}`, {
      method,
      signal,
      headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw new ApiError('aborted', 'Request cancelled.')
    }
    // A rejected fetch does not mean "nothing is listening". InvestPal returns
    // no CORS headers on a 5xx (only successful responses get them), so the
    // browser blocks the error response outright and this page never sees the
    // status. Down and erroring are genuinely indistinguishable from here, so
    // the message has to name both rather than guess.
    throw new ApiError(
      'offline',
      `Cannot reach InvestPal at ${API_BASE}.`,
      null,
      isChat
        ? "Either it is not running — start it with 'make start' — or it returned " +
          'an error, which the browser hides because InvestPal sends no CORS ' +
          'headers on a failure. The usual cause is a missing provider key: /chat ' +
          "runs InvestPal's own agent, so it needs ANTHROPIC_API_KEY (or the " +
          'OpenAI/Google equivalent) in .env.secrets, matching LLM_PROVIDER in ' +
          '.env. logs/investpal-api.log has the real error.'
        : "Either it is not running — start it with 'make start' — or it returned " +
          'an error, which the browser hides because InvestPal sends no CORS ' +
          'headers on a failure. logs/investpal-api.log has the real error.',
    )
  }

  if (!res.ok) {
    if (res.status === 404) {
      throw new ApiError('not_found', 'Not found.', 404)
    }
    if (res.status === 409) {
      throw new ApiError('conflict', 'That session already exists.', 409)
    }
    // Reachable only when something in front of InvestPal adds CORS headers to
    // error responses, or when this client is used outside a browser. Kept
    // because the message is the right one when the status does get through.
    if (res.status >= 500 && isChat) {
      throw new ApiError(
        'agent_unavailable',
        "InvestPal's own agent could not answer.",
        res.status,
        'The most likely cause is a missing AI provider key: add one to ' +
          '.env.secrets matching LLM_PROVIDER in .env, then restart the backend. ' +
          'logs/investpal-api.log has the real error, which the API does not ' +
          'send to clients.',
      )
    }
    throw new ApiError('server', `InvestPal returned ${res.status}.`, res.status)
  }

  // 204 No Content, which DELETE /workflows/{id} returns.
  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}

// ── Sessions ────────────────────────────────────────────────────────────────

export const createSession = (name?: string, signal?: AbortSignal) =>
  request<Session>('/session', { method: 'POST', body: { name }, signal })

export const getSession = (id: string, signal?: AbortSignal) =>
  request<Session>(`/session/${encodeURIComponent(id)}`, { signal })

export const listSessions = (signal?: AbortSignal) =>
  request<SessionSummary[]>('/sessions', { signal })

// ── Chat ────────────────────────────────────────────────────────────────────

/**
 * Blocks for the entire agent run, which is routinely minutes: it calls
 * LangChain's ainvoke, not astream, and there is no streaming endpoint. Never
 * wrap this in a timeout shorter than about ten minutes. Cancellation is the
 * caller's job, through signal.
 */
export const sendMessage = (session_id: string, message: string, signal?: AbortSignal) =>
  request<{ response: string }>('/chat', {
    method: 'POST',
    body: { session_id, message },
    signal,
    isChat: true,
  })

// ── Reminders ───────────────────────────────────────────────────────────────

export const listReminders = (signal?: AbortSignal) =>
  request<Reminder[]>('/agent_reminders', { signal })

// ── Workflows ───────────────────────────────────────────────────────────────
//
// POST /workflows/check-and-run is deliberately absent and must stay that way.
// The Claude Code cockpit is the workflow executor; calling the endpoint from
// here as well runs every due workflow twice. See CLAUDE.md, "Scheduled
// workflows", and docs/custom-ui.md.

export const listWorkflows = (signal?: AbortSignal) =>
  request<Workflow[]>('/workflows', { signal })

export const createWorkflow = (body: CreateWorkflowBody, signal?: AbortSignal) =>
  request<Workflow>('/workflows', { method: 'POST', body, signal })

export const updateWorkflow = (id: string, body: UpdateWorkflowBody, signal?: AbortSignal) =>
  request<Workflow>(`/workflows/${encodeURIComponent(id)}`, { method: 'PATCH', body, signal })

export const deleteWorkflow = (id: string, signal?: AbortSignal) =>
  request<void>(`/workflows/${encodeURIComponent(id)}`, { method: 'DELETE', signal })

export const listWorkflowResults = (limit = 20, signal?: AbortSignal) =>
  request<WorkflowResult[]>(`/workflow_results?limit=${limit}`, { signal })
