# claude-skills — backlog

Packages not yet created. Once a package exists under `packages/`, its items
move to that package's own `BACKLOG.md`.

---

## 1. `/owl` — redo the last answer end to end — **OPEN, raised 26 Oct 2026**

**What.** A skill that redoes the last answer after Claude skipped most of its
steps. It lists every step in order. For each step it gives where it runs
(Claude's Bash, `!` in Claude Code, or the user's own terminal), the exact
command, how to get any short-lived or single-use key or login it needs (not
long-standing accounts), what to capture, and the expected output. Claude then
runs every step it can itself and ends on the single remaining command for the
user, as one line.

**Why.** Between 28 Sep and 26 Oct the user had to ask for missing steps, or
object to partial answers handed out a piece at a time, in about a dozen
sessions across five projects. The memory written to stop this
(`finish_the_task_dont_ask_about_steps`, in `hugoboss-flutter-runner`) was never
added to that project's `MEMORY.md` index, so it was never loaded.

## 2. `/again` — re-present the last question set or list in full — **OPEN, raised 26 Oct 2026**

**What.** A skill that gives the last set of questions or list again, complete:
every item with its context, the current behaviour and the options. No bare
references are left unexplained — F-numbers, `1b`-style answers, `D-NN`
decision ids, requirement ids.

**Why.** Between 28 Sep and 26 Oct the user asked about fifteen times for a
question set or list to be given again in full. A `Stop` hook that blocks bare
references is being built in `claude-hooks`' `claude-guard-hooks`; `/again`
repairs a reply that has already gone out.
