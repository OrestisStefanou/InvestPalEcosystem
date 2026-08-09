"""
InvestPal cockpit: Claude Code SessionStart hook.

Runs when a Claude Code session starts. It talks to the InvestPal MCP server
(the single source of truth) and injects into the session context via
`hookSpecificOutput.additionalContext`:

  1. A SHORT pointer to the canonical investment-advisor persona. The persona (the
     `get_invstment_advisor_prompt` MCP prompt) is fetched fresh from the backend
     and written to a file; the hook only emits the file path plus an instruction
     to read it. This keeps additionalContext small enough to never be truncated
     to a preview, while the full persona stays loadable on demand. (The MCP server
     remains the single source of truth: nothing is copied into the repo.)
  2. The client's profile notes and open reminders, so the first response is already
     informed by them instead of costing a tool round-trip.
  3. Any scheduled workflows that are due right now, plus the exact steps for
     Claude Code to execute them (spawn a subagent, store the result). InvestPal
     still owns the schedules; this hook only asks "what is due?" and hands the
     work to Claude Code.

Design notes:
  - Output on stdout is ALWAYS a single valid JSON object and the process ALWAYS
    exits 0, so a backend that is down can never block a session. Failures are
    surfaced as a note inside additionalContext.
  - The persona is written to a file rather than inlined because inlining the full
    ~8KB prompt pushed additionalContext past Claude Code's inline-output threshold,
    so it was truncated to a preview and most of the operating rules never reached
    the model's context. A small pointer is guaranteed to land in full. The profile
    and reminder sections are inlined but budgeted (see CONTEXT_BUDGET_CHARS) for
    the same reason: they must never grow enough to push the workflow instructions
    out of context.
  - InvestPal is a single-client project. Since the "Single user project migration"
    no InvestPal MCP tool or prompt takes a `user_id`, so this hook passes none.
  - Run via the InvestPal project's uv environment (which already has `fastmcp`
    installed) so this hook needs no dependencies of its own and touches nothing
    in the nested service repos.
"""

import asyncio
import datetime as dt
import json
import os
import sys
import tempfile

MCP_URL = os.environ.get("INVESTPAL_MCP_URL", "http://127.0.0.1:9000/mcp")
PERSONA_PROMPT_NAME = "get_invstment_advisor_prompt"  # name matches the backend (typo intentional)

# Combined cap for the profile + reminder sections. Both grow without bound as the
# client is used, and additionalContext is truncated to a preview once it gets too
# large -- which would silently drop the workflow instructions below them.
CONTEXT_BUDGET_CHARS = 1000


def _emit(additional_context: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": additional_context,
                }
            }
        )
    )


def _extract(result):
    """Pull a list of plain dicts out of a fastmcp CallToolResult.

    Prefer `structured_content` (plain JSON dicts) over `.data`. Recent fastmcp
    deserializes `.data` into typed model objects (e.g. `Root`) that are NOT
    `dict` instances, and downstream callers (`_partition_workflows`,
    `_workflow_instructions`) rely on dict access — returning models silently
    makes every workflow look not-due. `.data` is kept only as a last resort.
    """
    structured = getattr(result, "structured_content", None) or getattr(
        result, "structuredContent", None
    )
    if isinstance(structured, dict) and "result" in structured:
        return structured["result"]
    if isinstance(structured, list):
        return structured
    for block in getattr(result, "content", []) or []:
        text = getattr(block, "text", None)
        if text:
            try:
                parsed = json.loads(text)
            except (ValueError, TypeError):
                continue
            if isinstance(parsed, dict) and "result" in parsed:
                return parsed["result"]
            return parsed
    data = getattr(result, "data", None)
    if data is not None:
        return data
    return []


def _persona_text(prompt_result) -> str:
    parts = []
    for message in getattr(prompt_result, "messages", []) or []:
        content = getattr(message, "content", None)
        text = getattr(content, "text", None)
        if text:
            parts.append(text)
    return "\n".join(parts).strip()


def _read_session_id() -> str | None:
    """SessionStart hooks receive a JSON payload on stdin; pull session_id if present."""
    try:
        raw = sys.stdin.read()
        if not raw:
            return None
        payload = json.loads(raw)
        sid = payload.get("session_id")
        return str(sid) if sid else None
    except Exception:  # noqa: BLE001 - stdin is best-effort; never block the session
        return None


def _write_persona_file(persona: str, session_id: str | None) -> str:
    """Write the persona to a temp file and return its absolute path.

    Session-scoped filename when we know the session id, so concurrent sessions do
    not clobber each other; falls back to a fixed name otherwise.
    """
    name = f"investpal_persona_{session_id}.md" if session_id else "investpal_persona.md"
    path = os.path.join(tempfile.gettempdir(), name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(persona)
    return path


def _bulleted_section(title: str, bullets: list[str], empty: str, budget: int) -> str:
    """Render a markdown section, dropping trailing bullets that exceed `budget` chars.

    The count of what was dropped is reported rather than silently omitted, so a
    truncated profile never reads as a complete one.
    """
    if not bullets:
        return f"## {title}\n\n{empty}"

    kept: list[str] = []
    used = 0
    for bullet in bullets:
        line = f"- {bullet}"
        if kept and used + len(line) > budget:
            break
        kept.append(line)
        used += len(line)

    dropped = len(bullets) - len(kept)
    if dropped:
        kept.append(f"- (+{dropped} more not shown here; read them with the relevant tool)")
    return f"## {title}\n\n" + "\n".join(kept)


def _profile_section(notes, budget: int) -> str:
    bullets = [
        str(note.get("note")).strip()
        for note in notes
        if isinstance(note, dict) and note.get("note")
    ]
    return _bulleted_section(
        "Client profile",
        bullets,
        "No profile notes recorded yet. Build the profile with `createUserProfileNote` "
        "as you learn durable facts about the client.",
        budget,
    )


def _reminders_section(reminders, budget: int) -> str:
    bullets = []
    for reminder in reminders:
        if not isinstance(reminder, dict):
            continue
        description = str(reminder.get("description") or "").strip()
        if not description:
            continue
        due_date = reminder.get("due_date")
        suffix = f"due {due_date}" if due_date else "no due date"
        bullets.append(f"{description} ({suffix}) [id={reminder.get('id')}]")
    return _bulleted_section(
        "Open reminders",
        bullets,
        "No open reminders.",
        budget,
    )


def _partition_workflows(workflows, now):
    """Split workflows into (due, stuck).

    Due: `active` with a `next_run_at` at or before `now`. `paused` is never run.

    Stuck: anything left in `running`. The cockpit never claims the lock, so a
    `running` row can only come from a backend run that died before storing its
    result. Such a row is invisible to the active-only due filter forever, which is
    why it is surfaced separately rather than ignored.
    """
    due = []
    stuck = []
    for wf in workflows:
        if not isinstance(wf, dict):
            continue
        status = wf.get("status")
        if status == "running":
            stuck.append(wf)
            continue
        if status != "active":
            continue
        next_run_at = wf.get("next_run_at")
        if not next_run_at:
            continue
        try:
            when = dt.datetime.fromisoformat(next_run_at)
        except (ValueError, TypeError):
            continue
        if when.tzinfo is None:
            when = when.replace(tzinfo=dt.timezone.utc)
        if when <= now:
            due.append(wf)
    return due, stuck


def _stuck_note(stuck) -> str:
    if not stuck:
        return ""
    lines = [
        "",
        "",
        "### Possibly stuck runs",
        "",
        "These workflows are still marked `running`, which means an earlier run died "
        "before storing a result. They will never come up as due again until the lock "
        "is released. Tell the client, and clear each one with "
        "`updateAgentWorkflow(workflow_id=..., status=\"active\")` when they confirm:",
    ]
    for wf in stuck:
        lines.append(
            f"- workflow_id={wf.get('workflow_id')} | name={wf.get('name')!r} | "
            f"last_run_at={wf.get('last_run_at')}"
        )
    return "\n".join(lines)


def _workflow_instructions(due, stuck) -> str:
    if not due:
        return "## Scheduled workflows\n\nNo workflows are due right now." + _stuck_note(stuck)

    lines = [
        "## Scheduled workflows DUE NOW",
        "",
        f"{len(due)} workflow(s) are due. Handle them silently BEFORE greeting the user, "
        "then mention what ran. For EACH workflow below:",
        "",
        "1. Launch a subagent (Task tool) whose goal is the workflow's description. The "
        "subagent must use the InvestPal skills (`getSkillDefinitions` then `getSkill`), "
        "market-data tools, and portfolio tools as needed, and return a concise report.",
        "2. Persist the report: call `storeWorkflowResult` with the workflow_id, "
        "workflow_name set to the workflow's name shown below, and output=<the report>.",
        "",
        "`storeWorkflowResult` is what COMPLETES the run: in one transaction it stores the "
        "report, sets last_run_at, advances next_run_at from the cron schedule and releases "
        "the running lock. So that is the only call needed — do NOT also call "
        "`updateAgentWorkflow` to re-set the schedule, which would advance next_run_at a "
        "second time and skip an occurrence.",
        "",
        "Workflows:",
    ]
    for wf in due:
        lines.append(
            f"- workflow_id={wf.get('workflow_id')} | name={wf.get('name')!r} | "
            f"schedule={wf.get('schedule')!r} | next_run_at={wf.get('next_run_at')}\n"
            f"  goal: {wf.get('description')}"
        )
    return "\n".join(lines) + _stuck_note(stuck)


async def _build_context(session_id: str | None) -> str:
    try:
        from fastmcp import Client
    except Exception as exc:  # noqa: BLE001
        return (
            "InvestPal cockpit: could not import fastmcp to load the advisor persona "
            f"({exc}). Ensure InvestPal dependencies are installed (`make install`). "
            f"You can still load the persona manually with "
            f"/mcp__investpal__{PERSONA_PROMPT_NAME}."
        )

    persona = ""
    persona_error = None
    profile_section = "## Client profile\n\nCould not load (see note above)."
    reminders_section = "## Open reminders\n\nCould not load (see note above)."
    workflow_section = "## Scheduled workflows\n\nCould not check (see note above)."

    try:
        async with Client(MCP_URL) as client:
            # Each call is isolated: one failing backend read degrades to a note
            # rather than costing the session every other section.
            try:
                prompt_result = await client.get_prompt(PERSONA_PROMPT_NAME)
                persona = _persona_text(prompt_result)
            except Exception as exc:  # noqa: BLE001
                persona_error = str(exc)

            try:
                notes = _extract(await client.call_tool("getUserProfileNotes", {}))
                profile_section = _profile_section(notes, CONTEXT_BUDGET_CHARS // 2)
            except Exception as exc:  # noqa: BLE001
                profile_section = f"## Client profile\n\nCould not load profile notes: {exc}"

            try:
                reminders = _extract(await client.call_tool("getAgentReminders", {}))
                reminders_section = _reminders_section(reminders, CONTEXT_BUDGET_CHARS // 2)
            except Exception as exc:  # noqa: BLE001
                reminders_section = f"## Open reminders\n\nCould not load reminders: {exc}"

            try:
                workflows = _extract(await client.call_tool("getAgentWorkflows", {}))
                now = dt.datetime.now(dt.timezone.utc)
                workflow_section = _workflow_instructions(*_partition_workflows(workflows, now))
            except Exception as exc:  # noqa: BLE001
                workflow_section = (
                    "## Scheduled workflows\n\nCould not list workflows: "
                    f"{exc}"
                )
    except Exception as exc:  # noqa: BLE001
        return (
            f"InvestPal cockpit: the InvestPal MCP server is unreachable at {MCP_URL} "
            f"({exc}). Start the infrastructure (`make start`), then reconnect MCP with "
            f"/mcp. Load the persona with /mcp__investpal__{PERSONA_PROMPT_NAME} once it is up."
        )

    header = (
        "=== InvestPal cockpit ===\n"
        "You are operating the InvestPal investment cockpit for its single client. "
        "InvestPal is a single-user project: no InvestPal MCP tool or prompt takes a "
        "user_id, so never pass one. Adopt the advisor persona (loaded as described "
        "below) and use the connected MCP tools (investpal, market-data, alpaca, "
        "coinbase).\n"
    )

    if persona:
        try:
            persona_path = _write_persona_file(persona, session_id)
            persona_block = (
                "## Advisor persona — READ THIS FIRST\n\n"
                "The canonical InvestPal advisor persona (source of truth: the investpal "
                "MCP server) has been fetched and saved to:\n\n"
                f"    {persona_path}\n\n"
                "READ THIS FILE IN FULL NOW, before your first response to the client, and "
                "adopt it as your operating instructions for the entire session. It defines "
                "session initialization, memory rules, skills usage, trading rules, and "
                "communication style. Do not skip it or rely on a summary."
            )
        except Exception as exc:  # noqa: BLE001 - fall back to inlining if the write fails
            persona_block = (
                f"(Could not write the persona to a file: {exc}. Persona follows inline.)\n\n"
                f"{persona}"
            )
    elif persona_error:
        persona_block = (
            f"(Advisor persona prompt failed to load: {persona_error}. Load it manually "
            f"with /mcp__investpal__{PERSONA_PROMPT_NAME}.)"
        )
    else:
        persona_block = (
            f"(Advisor persona unavailable. Load it with "
            f"/mcp__investpal__{PERSONA_PROMPT_NAME}.)"
        )

    return (
        f"{header}\n{persona_block}\n\n"
        f"{profile_section}\n\n{reminders_section}\n\n{workflow_section}"
    )


def main() -> None:
    session_id = _read_session_id()
    try:
        context = asyncio.run(_build_context(session_id))
    except Exception as exc:  # noqa: BLE001 - never let the hook crash the session
        context = f"InvestPal cockpit hook error: {exc}"
    _emit(context)
    sys.exit(0)


if __name__ == "__main__":
    main()
