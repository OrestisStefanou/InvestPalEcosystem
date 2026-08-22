/**
 * Timestamp handling, which is fiddlier than it looks.
 *
 * InvestPal is inconsistent about offsets, by field:
 *   aware, "+00:00"  session.created_at (repos/sessions.py), message.created_at
 *                    (services/chat.py), workflow_result.ran_at, next_run_at
 *   naive, no offset  workflow.created_at (repos/agent_workflows.py),
 *                     reminder.created_at (repos/agent_reminders.py)
 *
 * Plain `new Date(s)` is nonetheless right for both. JS reads an offset-less
 * datetime as local time, which is exactly what Python's naive datetime.now()
 * wrote; and it reads "+00:00" as UTC and converts. That only holds because the
 * API and the browser are on the same machine, which for InvestPal they always
 * are. Do not "fix" this by force-appending Z: that would shift every naive
 * value by the local offset.
 */

export function parseStamp(s: string | null): Date | null {
  if (!s) return null
  const d = new Date(s)
  return Number.isNaN(d.getTime()) ? null : d
}

/**
 * due_date is a date, not a timestamp: "2026-08-22". new Date() reads a
 * date-only string as UTC midnight, so west of Greenwich it renders as the day
 * before. Build it in local time instead.
 */
export function parseDateOnly(s: string | null): Date | null {
  if (!s) return null
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s.trim())
  if (!m) return parseStamp(s)
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
}

const DAY = 86_400_000

export function relative(s: string | null): string {
  const d = parseStamp(s)
  if (!d) return '—'
  const diff = Date.now() - d.getTime()
  const mins = Math.round(diff / 60_000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.round(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.round(hrs / 24)
  if (days < 7) return `${days}d ago`
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
}

export function absolute(s: string | null): string {
  const d = parseStamp(s)
  if (!d) return '—'
  return d.toLocaleString(undefined, {
    day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
  })
}

/** For next_run_at: forward-looking, so "in 3h" rather than "3h ago". */
export function until(s: string | null): string {
  const d = parseStamp(s)
  if (!d) return '—'
  const diff = d.getTime() - Date.now()
  if (diff <= 0) return 'due now'
  const mins = Math.round(diff / 60_000)
  if (mins < 60) return `in ${mins}m`
  const hrs = Math.round(mins / 60)
  if (hrs < 24) return `in ${hrs}h`
  return `in ${Math.round(hrs / 24)}d`
}

export function dueLabel(s: string | null): string {
  const d = parseDateOnly(s)
  if (!d) return 'no due date'
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const days = Math.round((d.getTime() - today.getTime()) / DAY)
  if (days === 0) return 'due today'
  if (days === 1) return 'due tomorrow'
  if (days < 0) return `overdue by ${-days}d`
  if (days < 14) return `due in ${days}d`
  return `due ${d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}`
}

export function elapsed(ms: number): string {
  const total = Math.floor(ms / 1000)
  const m = Math.floor(total / 60)
  const s = total % 60
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}
