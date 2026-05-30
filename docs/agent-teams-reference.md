# Agent Teams — Master Reference Guide

> Source: https://code.claude.com/docs/en/agent-teams
> Requires: Claude Code v2.1.32+, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

---

## What Agent Teams Are

Multiple Claude Code instances working together. One session is the **lead** — it creates the team, assigns tasks, and synthesizes results. **Teammates** each have their own context window, work independently, and can message each other directly (not just back to the lead).

---

## Enable Agent Teams

In `.claude/settings.local.json` (project-local) or `~/.claude/settings.json` (global):

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Or export the variable in your shell environment.

---

## Agent Teams vs Subagents

| | Subagents | Agent Teams |
|---|---|---|
| **Context** | Own context; results return to caller | Own context; fully independent |
| **Communication** | Report back to main agent only | Teammates message each other directly |
| **Coordination** | Main agent manages all work | Shared task list; self-coordinate |
| **Best for** | Focused tasks where only the result matters | Complex work needing discussion and collaboration |
| **Token cost** | Lower (results summarized back) | Higher (each teammate is a full Claude instance) |

**Rule of thumb:** use subagents for quick, focused work; use agent teams when teammates need to share findings, challenge each other, or coordinate on their own.

---

## Best Use Cases

- **Research and review** — multiple teammates investigate different aspects simultaneously, then share and challenge findings
- **New independent modules/features** — each teammate owns a separate piece; no overlap
- **Debugging with competing hypotheses** — teammates test different theories in parallel; the surviving theory is more reliable
- **Cross-layer changes** — frontend, backend, and tests each owned by a different teammate

**Not a good fit for:** sequential tasks, same-file edits, tasks with many dependencies. Use a single session or subagents instead.

---

## Starting a Team

Just describe the task and team structure in natural language:

```
Create an agent team to explore this from different angles:
one teammate on UX, one on technical architecture,
one playing devil's advocate.
```

Claude creates the team, spawns teammates, manages the shared task list, and cleans up when done. You can also specify count and model:

```
Create a team with 4 teammates. Use Sonnet for each teammate.
```

---

## Display Modes

| Mode | How it works | When to use |
|---|---|---|
| `auto` (default) | Split panes if inside tmux, otherwise in-process | Works everywhere |
| `in-process` | All teammates in one terminal; Shift+Down cycles through them | Any terminal, no setup |
| `tmux` | Each teammate in its own pane; requires tmux or iTerm2 | When you want all output visible at once |

Override in `~/.claude/settings.json`:
```json
{ "teammateMode": "in-process" }
```

Or per session:
```bash
claude --teammate-mode in-process
```

---

## Keyboard Controls (In-Process Mode)

| Key | Action |
|---|---|
| `Shift+Down` | Cycle to next teammate (wraps back to lead after last) |
| `Enter` | View a teammate's session |
| `Escape` | Interrupt a teammate's current turn |
| `Ctrl+T` | Toggle the shared task list |

In split-pane mode, click into any pane to interact with that teammate directly.

---

## Task System

The shared task list is the coordination backbone. Tasks have three states: **pending**, **in progress**, **completed**. Tasks can depend on other tasks — blocked tasks auto-unblock when their dependencies complete.

- The lead creates tasks; teammates claim and complete them
- Self-claim: after finishing a task, a teammate automatically picks up the next unassigned, unblocked task
- File locking prevents race conditions when multiple teammates claim simultaneously

Ideal task sizing: **5–6 tasks per teammate**. Too small = coordination overhead beats the benefit. Too large = teammates run too long without check-ins.

---

## Key Commands to Give the Lead

```
Wait for your teammates to complete their tasks before proceeding.
Spawn a researcher teammate with the prompt: "..."
Require plan approval before the architect teammate makes any changes.
Ask the researcher teammate to shut down.
Clean up the team.
```

---

## Plan Approval Flow

Request it in the spawn prompt:

```
Spawn an architect teammate to refactor the auth module.
Require plan approval before they make any changes.
```

Flow: teammate works in read-only plan mode → sends approval request to lead → lead approves or rejects with feedback → if rejected, teammate revises and resubmits → once approved, implementation begins.

Control the lead's approval criteria in your prompt: `"only approve plans that include test coverage"`.

---

## Architecture Internals

| Component | Role |
|---|---|
| Team lead | Main session; creates team, spawns teammates, coordinates work |
| Teammates | Separate Claude Code instances; own context windows |
| Task list | Shared list of work items with dependency tracking |
| Mailbox | Messaging system between agents |

**Storage locations:**
- Team config: `~/.claude/teams/{team-name}/config.json` — do not hand-edit; overwritten on each state update
- Task list: `~/.claude/tasks/{team-name}/`

**Do not create** `.claude/teams/teams.json` in your project directory — it is not recognized as config and Claude treats it as an ordinary file.

---

## Context Each Teammate Gets

- Project `CLAUDE.md` files (from working directory)
- MCP servers and skills from project + user settings
- The spawn prompt from the lead
- **Not inherited:** the lead's conversation history

Always put task-specific details in the spawn prompt:

```
Spawn a security reviewer with the prompt: "Review src/auth/ for vulnerabilities.
Focus on token handling, session management, and input validation. The app uses
JWT tokens in httpOnly cookies. Report issues with severity ratings."
```

---

## Using Subagent Definitions as Teammate Roles

Define a role once (as a subagent file in any scope: project, user, plugin, CLI) and reuse it for teammates:

```
Spawn a teammate using the security-reviewer agent type to audit the auth module.
```

The teammate respects that definition's `tools` allowlist and `model`. Team coordination tools (`SendMessage`, task tools) are always available regardless of `tools` restrictions.

Note: `skills` and `mcpServers` frontmatter from the subagent definition are **not** applied when it runs as a teammate — those come from project/user settings instead.

---

## Permissions

- Teammates start with the lead's permission settings
- If lead runs `--dangerously-skip-permissions`, all teammates do too
- Per-teammate modes can be changed after spawning, but not at spawn time
- Permission requests bubble up to the lead — pre-approve common operations in settings before spawning to reduce friction

---

## Hooks for Quality Gates

| Hook | Trigger | Use |
|---|---|---|
| `TeammateIdle` | Teammate is about to go idle | Exit code 2 to send feedback and keep working |
| `TaskCreated` | Task being created | Exit code 2 to block creation and send feedback |
| `TaskCompleted` | Task being marked complete | Exit code 2 to block completion and send feedback |

---

## Token Costs

Token usage scales linearly with teammates — each has its own full context window. Good investment for research, review, and parallel new feature work. Not worth it for routine sequential tasks.

---

## Sizing Guidelines

| Scenario | Recommendation |
|---|---|
| Most workflows | 3–5 teammates |
| Tasks per teammate | ~5–6 |
| When to scale up | Only when work genuinely benefits from simultaneous execution |

Three focused teammates often outperform five scattered ones.

---

## Proven Prompt Patterns

### Parallel Code Review
```
Create an agent team to review PR #142. Spawn three reviewers:
- One focused on security implications
- One checking performance impact
- One validating test coverage
Have them each review and report findings.
```

### Competing Hypothesis Debugging
```
Users report the app exits after one message instead of staying connected.
Spawn 5 agent teammates to investigate different hypotheses. Have them talk
to each other to try to disprove each other's theories, like a scientific
debate. Update the findings doc with whatever consensus emerges.
```

### Multi-angle Exploration
```
I'm designing a CLI tool that helps developers track TODO comments across their
codebase. Create an agent team to explore this from different angles: one
teammate on UX, one on technical architecture, one playing devil's advocate.
```

---

## Best Practices Checklist

- [ ] Include task-specific context in every spawn prompt (teammates don't get the lead's history)
- [ ] Start with 3–5 teammates; scale only when parallel work genuinely helps
- [ ] Size tasks as self-contained units with a clear deliverable (a function, a test file, a review)
- [ ] Assign each teammate a distinct set of files to avoid overwrites
- [ ] Avoid leaving the team unattended for long — check in, redirect, and steer
- [ ] For new teams, start with research/review tasks (no parallel file writing) to learn the coordination model
- [ ] Tell the lead to wait for teammates when it starts implementing itself: `"Wait for teammates to finish before proceeding."`
- [ ] Pre-approve common operations in permission settings to reduce prompt interruptions
- [ ] Put reusable roles in subagent definitions so they can be referenced by name
- [ ] Use `CLAUDE.md` to provide project-specific guidance to all teammates automatically

---

## Limitations (Experimental)

| Limitation | Workaround |
|---|---|
| No session resumption with in-process teammates | After `/resume`, tell the lead to spawn new teammates |
| Task status can lag | Manually update task status or tell the lead to nudge the teammate |
| Shutdown can be slow | Teammates finish current request before shutting down |
| One team at a time | Clean up before creating a new team |
| No nested teams | Only the lead can manage the team; teammates cannot spawn sub-teams |
| Lead is fixed | Can't promote a teammate or transfer leadership |
| Split panes not supported in VS Code terminal, Windows Terminal, or Ghostty | Use in-process mode |

---

## Troubleshooting

**Teammates not appearing:**
- In-process: press `Shift+Down` — they may already be running
- Check that the task was complex enough to warrant a team
- Verify tmux is in PATH: `which tmux`
- For iTerm2: ensure `it2` CLI is installed and Python API is enabled in preferences

**Task appears stuck:**
- Check if the work is actually done; update status manually or ask the lead to nudge

**Orphaned tmux sessions:**
```bash
tmux ls
tmux kill-session -t <session-name>
```

**Lead shuts down too early:**
- Tell it to keep going; instruct it to wait for teammates before proceeding

---

## Cleanup

Always clean up through the **lead**:
```
Clean up the team.
```

Shut down all teammates first — cleanup fails if any are still running. Never run cleanup from a teammate; team context may not resolve correctly and resources can be left in an inconsistent state.

---

## Next Steps / Related Docs

- [Subagents](/en/sub-agents) — lightweight delegation within a single session
- [Git Worktrees](/en/worktrees) — manual parallel sessions without automated coordination
- [Hooks](/en/hooks) — enforce quality gates on teammate and task events
- [Settings](/en/settings) — full list of available settings including `teammateMode`
- [Costs](/en/costs#agent-team-token-costs) — token cost guidance for agent teams
