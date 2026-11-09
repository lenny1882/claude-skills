# claude-skills — backlog

Packages not yet created, and recurring faults that may become hooks in
`claude-hooks` instead. Once a package exists under `packages/`, its items
move to that package's own `BACKLOG.md`; once a hook is taken up in
`claude-hooks`, its item moves to that repo's backlog.

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
(`finish_the_task_dont_ask_about_steps`, in a client app project) was never
added to that project's `MEMORY.md` index, so it was never loaded.

## 2. `/again` — re-present the last question set or list in full — **DONE 26 Oct 2026, raised 26 Oct 2026**

**Built 26 Oct 2026** as `packages/again`, version 0.1.0, not yet released.

**What.** A skill that gives the last set of questions or list again, complete:
every item with its context, the current behaviour and the options. No bare
references are left unexplained — F-numbers, `1b`-style answers, `D-NN`
decision ids, requirement ids.

**Why.** Between 28 Sep and 26 Oct the user asked about fifteen times for a
question set or list to be given again in full. A `Stop` hook that blocks bare
references ships in `claude-hooks`' `claude-guard-hooks` as
`check-bare-references.sh`; `/again` repairs a reply that has already gone
out.

## 3. `mate`, `bruv`, `dude` — redo the last answer that missed the point — **OPEN, raised 26 Oct 2026, widened 9 Nov 2026**

**What.** One skill, reached three ways: `/mate`, `/bruv`, `/dude`, or a
message that is only one of those words. A bare word needs a
`UserPromptSubmit` hook that expands it into the skill. The skill checks the
last answer against the session's context and the question it answered, names
which of four faults it has, and redoes the answer to fix that fault:

1. **Off on a tangent.** The answer left the session's mode or subject: it
   built or changed things during planning or discussion, worked in another
   repo or package, or raised items the user had parked or dropped. The redo
   goes back to the question. If the tangent ran commands or wrote files, it
   first lists what changed, and undoes nothing unless told to.
2. **Overkill.** The question took a yes/no or a single fact, and the answer
   gave a page. The redo gives the yes/no or the fact, plus at most one line
   on why.
3. **Technical instead of an answer.** The answer explained the mechanism when
   the question asked about the outcome: "are we protected", "regression or
   same behaviour", "what does adding this change". The redo answers the
   outcome in plain words, for a reader with some technical background.
4. **Several things in one.** The answer bundled separate questions or
   decisions, so the user would have to reply to all of them in one message.
   The redo takes them one per reply and waits for the answer before the next.
   A run of commands meant to be pasted as one is not split.

This takes in item 5's splitting. Whether item 5 goes altogether, or stays
for its "more detail per item" part, is still to decide.

**Why.** In 2,140 typed user messages from 12 Oct to 9 Nov 2026, the four
faults drew about 20, 12, 8 and 7 complaints. Examples, with project names
left out:

- *Tangent:* "the context is things that we need to cover before we build" —
  an infrastructure planning session given build-time items. "We're in the
  middle of executing" — a phase execution session that reached for a quick
  task. "I'm in the middle of a test, I just need the environment" — scripts
  rewritten mid-test. "Why is this session driving an unrelated repo?" Unasked
  removals and amends: "Did I ask you to remove it from the planning docs?",
  "Did I ask you to amend?"
- *Overkill:* "That's a lot of words to not answer my question." "I don't want
  a table, I don't want a wall of text … is there anything untested, or that
  has failed." "Can you make the changes per repo, yes or no?" — asked twice,
  after a table.
- *Technical:* "Clear English: are we protected. If not, what isn't." It took
  three more asks to get the right level. "Does the current app use the image
  or make another call … regression or same behaviour."
- *Several in one:* "I'm not reading through a wall of text to pick out
  questions and discussion points, and then giving you one answer containing
  everything." "Why are you combining voice and decision-making?" "Did I ask
  you to stop presenting them one by one?"
- *Counter-example:* "Why have you separated everything, rather than one
  [command]?" Splitting applies to questions and decisions, not to a sequence
  of steps.

**What the replies that drew complaints looked like.** Measured over the whole
turn's text, against a median of 139 words for every reply in the same
period:

- *Tangent:* median 269 words, tables in 5 of 13. Usually a report of work
  nobody asked for.
- *Overkill:* median 158 words, close to the median for all replies, with
  almost twice the code spans (14 against 8). The fault is length relative to
  the question, not length alone. Several replies opened with the right
  "Yes." or "No." and then kept going. A length cap would not catch it; the
  skill has to read the question.
- *Technical:* median 214 words, tables in 1 of 7. The answers were about how
  the thing works (policy paths, TTLs, git's meaning of "revert") when the
  question was about the result.
- *Several in one:* median 415 words, about three times the median for all
  replies, and 13 list items. Each one held a list of decisions to answer in
  one reply.

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
