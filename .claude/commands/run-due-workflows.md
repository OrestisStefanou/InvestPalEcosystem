---
description: Check InvestPal for scheduled workflows that are due and execute them
---

Run any InvestPal scheduled workflows that are due right now. The SessionStart hook
already does this at launch; use this command to re-check mid-session.

Steps:

1. Get the current time with `getCurrentDatetime`.
2. Call `getAgentWorkflows` for user_id `orestis_user_id`.
3. A workflow is **due** when `status == "active"` and its `next_run_at` is at or
   before the current time. If none are due, say so and stop.
4. For EACH due workflow:
   - Launch a subagent (Task tool) whose goal is the workflow's `description`. The
     subagent must use the InvestPal skills (`getSkillDefinitions`, then `getSkill`
     for the relevant ones), market-data tools, and portfolio tools as needed, and
     return a concise report.
   - Persist it: `storeWorkflowResult` with the workflow_id, user_id `orestis_user_id`,
     the workflow_name, and `output` set to the report.
   - Advance the schedule: `updateAgentWorkflow` with user_id `orestis_user_id`, the
     workflow_id, and `schedule` set to the SAME cron string the workflow already has.
     This recomputes `next_run_at` to the next occurrence. Do not invent a mark-ran
     tool and do not modify the InvestPal repo.
5. Summarize what ran and the key takeaways for each.
