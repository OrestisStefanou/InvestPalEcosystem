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
  2. Any scheduled workflows that are due right now, plus the exact steps for
     Claude Code to execute them (spawn a subagent, store the result, advance the
     schedule). InvestPal still owns the schedules; this hook only asks "what is
     due?" and hands the work to Claude Code.

Design notes:
  - Output on stdout is ALWAYS a single valid JSON object and the process ALWAYS
    exits 0, so a backend that is down can never block a session. Failures are
    surfaced as a note inside additionalContext.
  - The persona is written to a file rather than inlined because inlining the full
    ~8KB prompt pushed additionalContext past Claude Code's inline-output threshold,
    so it was truncated to a preview and most of the operating rules never reached
    the model's context. A small pointer is guaranteed to land in full.
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
USER_ID = os.environ.get("INVESTPAL_USER_ID", "orestis_user_id")
PERSONA_PROMPT_NAME = "get_invstment_advisor_prompt"  # name matches the backend (typo intentional)


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
    """Pull a plain Python value out of a fastmcp CallToolResult."""
    data = getattr(result, "data", None)
    if data is not None:
        return data
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
                return json.loads(text)
            except (ValueError, TypeError):
                continue
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


def _due_workflows(workflows, now):
    due = []
    for wf in workflows:
        if not isinstance(wf, dict):
            continue
        if wf.get("status") != "active":
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
    return due


def _workflow_instructions(due) -> str:
    if not due:
        return "## Scheduled workflows\n\nNo workflows are due right now."

    lines = [
        "## Scheduled workflows DUE NOW",
        "",
        f"{len(due)} workflow(s) are due. Handle them silently BEFORE greeting the user, "
        "then mention what ran. For EACH workflow below:",
        "",
        "1. Launch a subagent (Task tool) whose goal is the workflow's description. The "
        "subagent must use the InvestPal skills (`getSkillDefinitions` then `getSkill`), "
        "market-data tools, and portfolio tools as needed, and return a concise report.",
        f"2. Persist the report: call `storeWorkflowResult` with workflow_id, user_id="
        f"\"{USER_ID}\", the workflow_name, and output=<the report>.",
        "3. Advance the schedule: call `updateAgentWorkflow` with user_id="
        f"\"{USER_ID}\", the workflow_id, and schedule set to the SAME cron string shown "
        "below. This recomputes next_run_at to the next occurrence (the backend exposes no "
        "mark-ran tool, and the cockpit must not modify the InvestPal repo).",
        "",
        "Workflows:",
    ]
    for wf in due:
        lines.append(
            f"- workflow_id={wf.get('workflow_id')} | name={wf.get('name')!r} | "
            f"schedule={wf.get('schedule')!r} | next_run_at={wf.get('next_run_at')}\n"
            f"  goal: {wf.get('description')}"
        )
    return "\n".join(lines)


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
    workflow_section = "## Scheduled workflows\n\nCould not check (see note above)."

    try:
        async with Client(MCP_URL) as client:
            try:
                prompt_result = await client.get_prompt(
                    PERSONA_PROMPT_NAME, {"user_id": USER_ID}
                )
                persona = _persona_text(prompt_result)
            except Exception as exc:  # noqa: BLE001
                persona_error = str(exc)

            try:
                result = await client.call_tool(
                    "getAgentWorkflows", {"user_id": USER_ID}
                )
                workflows = _extract(result)
                now = dt.datetime.now(dt.timezone.utc)
                workflow_section = _workflow_instructions(_due_workflows(workflows, now))
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
        f"You are operating the InvestPal investment cockpit for the single client "
        f"user_id=\"{USER_ID}\". Adopt the advisor persona (loaded as described below) "
        "and use the connected MCP tools (investpal, market-data, alpaca, coinbase).\n"
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

    return f"{header}\n{persona_block}\n\n{workflow_section}"


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
