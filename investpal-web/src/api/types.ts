// Mirrors InvestPal/apps/rest_api/*.py exactly. Every timestamp is an ISO 8601
// UTC string, never a number: InvestPal serialises them as strings on purpose
// (commit 6b9e4e6, "Use string for datetime response").

export type Role = 'user' | 'agent'

export interface Message {
  role: Role
  content: string
  created_at: string | null
}

/** GET /session/{id}, POST /session */
export interface Session {
  session_id: string
  messages: Message[]
  name: string
  created_at: string
}

/** GET /sessions. No messages: the list endpoint returns summaries only. */
export interface SessionSummary {
  session_id: string
  name: string
  created_at: string
}

/**
 * GET /agent_reminders. Read-only by design: there is no POST. The agent
 * creates reminders through the MCP server, not the REST API.
 */
export interface Reminder {
  id: string
  description: string
  created_at: string
  /** YYYY-MM-DD, not a full timestamp. */
  due_date: string | null
}

export type WorkflowStatus = 'active' | 'paused' | 'running'

export interface Workflow {
  workflow_id: string
  name: string
  description: string
  /** Cron expression, e.g. "0 9 * * 1". */
  schedule: string
  status: WorkflowStatus
  created_at: string
  last_run_at: string | null
  next_run_at: string | null
}

export interface WorkflowResult {
  result_id: string
  workflow_id: string
  workflow_name: string
  output: string
  ran_at: string
}

export interface CreateWorkflowBody {
  name: string
  description: string
  schedule: string
}

/** PATCH /workflows/{id}. Every field is optional; omitted fields are untouched. */
export interface UpdateWorkflowBody {
  name?: string
  description?: string
  schedule?: string
  status?: WorkflowStatus
}
