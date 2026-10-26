# claude-skills — backlog

Packages not yet created. Once a package exists under `packages/`, its items
move to that package's own `BACKLOG.md`.

---

## 1. `/owl` — redo the last answer end to end — **DONE 26 Oct 2026, raised 26 Oct 2026**

**Built 26 Oct 2026** as `packages/owl`, version 0.1.0, not yet released.

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

## 2. `/again` — re-present the last question set or list in full — **DONE 26 Oct 2026, raised 26 Oct 2026**

**Built 26 Oct 2026** as `packages/again`, version 0.1.0, not yet released.

**What.** A skill that gives the last set of questions or list again, complete:
every item with its context, the current behaviour and the options. No bare
references are left unexplained — F-numbers, `1b`-style answers, `D-NN`
decision ids, requirement ids.

**Why.** Between 28 Sep and 26 Oct the user asked about fifteen times for a
question set or list to be given again in full. A `Stop` hook that blocks bare
references is being built in `claude-hooks`' `claude-guard-hooks`; `/again`
repairs a reply that has already gone out.

## 3. `/mate` or `/bruv` — say the last answer again, shorter and in plain English — **OPEN, raised 26 Oct 2026**

**What.** A skill that rewrites the last answer shorter and in plain English:
the same facts and decisions, with the jargon replaced by what it means. It
runs when the user types `/mate` or `/bruv`, and also when the user's whole
message is just `mate` or `bruv`. A plain-word trigger needs more than a typed
skill, such as a `UserPromptSubmit` hook that expands the bare word into the
skill. Which of the two names, or both, is still to choose.

**Why.** Some answers come back as a wall of text or thick with jargon, and the
user wants a leaner version without having to say how to change it.

## 4. Compare what has been given, often side by side — **OPEN, raised 26 Oct 2026**

**What.** A skill that takes things already given in the conversation — two
drafts, options, files, versions, outputs — and compares them. Usually it sets
them side by side as defined in `~/.claude/CLAUDE.md` "Side-by-side means
columns": parallel hard-wrapped columns in a code fence, corresponding lines
level, both sides verbatim. It then names each difference. The command name is
still to choose (`/compare`, `/side-by-side`).

**Why.** The writing rule says what side-by-side looks like when asked for, but
there is no short way to ask for a comparison of things already on screen.

## 5. Go through a list one item at a time, with more detail — **OPEN, raised 26 Oct 2026**

**What.** A skill that takes a list of questions or points already given and
deals with each one on its own, with more detail than the list had: what it is,
what happens today, what each option changes. The command name is still to
choose (`/one-by-one`, `/individually`, `/separately`). Also still to decide:
all items in one reply, or one item per reply, waiting for the user's answer
before the next.

**Why.** A list of several questions or points answered together gets each one
too briefly; taking them separately gives each one the detail it needs.
