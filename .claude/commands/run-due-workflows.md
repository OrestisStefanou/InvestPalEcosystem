---
description: Check InvestPal for scheduled workflows that are due and execute them
---

Run any InvestPal scheduled workflows that are due right now. The SessionStart hook
already does this at launch; use this command to re-check mid-session.

InvestPal is a single-user project: no InvestPal MCP tool takes a `user_id`, so never
pass one.

Steps:

1. Get the current time in UTC with `date -u +%Y-%m-%dT%H:%M:%S+00:00`. Do NOT use
   `getCurrentDatetime` for this comparison — it returns naive **local** time while
   `next_run_at` is UTC, so comparing the two directly marks workflows due early by
   the local offset.
2. Call `getAgentWorkflows` (no arguments).
3. Triage by `status`:
   - **`active`** with `next_run_at` at or before the current UTC time → **due**, run it.
   - **`active`** with a later `next_run_at`, or **`paused`** → skip.
   - **`running`** → a previous run died before storing a result, so the lock was never
     released and the workflow will never come up as due again. Do not run it. Report it
     to the client and clear it with `updateAgentWorkflow(workflow_id=..., status="active")`
     once they confirm.

   If nothing is due, say so (mentioning any stuck workflows) and stop.
4. For EACH due workflow:
   - Launch a subagent (Task tool) whose goal is the workflow's `description`. The
     subagent must use the InvestPal skills (`getSkillDefinitions`, then `getSkill`
     for the relevant ones), market-data tools, and portfolio tools as needed, and
     return a concise report.
   - Persist it: `storeWorkflowResult` with the `workflow_id`, `workflow_name` set to
     the workflow's `name`, and `output` set to the report.

   `storeWorkflowResult` is what **completes** the run: in one transaction it stores the
   report, sets `last_run_at`, advances `next_run_at` from the cron schedule and releases
   the running lock. It is therefore the only call needed. Do NOT also call
   `updateAgentWorkflow` to re-set the schedule — that re-bases `next_run_at` from now a
   second time and silently skips an occurrence.
5. Summarize what ran and the key takeaways for each.
