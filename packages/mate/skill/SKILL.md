---
name: mate
description: Redo the previous answer because it missed the point — name which of four faults it has (off on a tangent, overkill, technical instead of an answer, several things in one) and give the answer again with that fault fixed. Use only when the user types /mate, /bruv or /dude, or a message that is only one of those words.
disable-model-invocation: true
---

# mate — redo the last answer that missed the point

The user typed `mate`, `bruv` or `dude` because the previous answer did not
answer what they asked. Work out which way it missed, say so in one line, and
give the answer again. The word is the instruction to redo it — do not ask
whether to.

## 1. Find the question and the mode

The question is the user's last message before the word, read together with
what the session is doing: planning, discussing, executing a phase, in the
middle of a test, reviewing. That mode is part of the question. "What's left"
asked during planning means what is left to plan, not to build.

If the user's last message held an instruction as well as a question, both
count.

## 2. Name the fault

Check the previous answer against the question and pick the fault that fits
best. More than one can apply; name each that does, the main one first.

1. **Off on a tangent.** The answer left the session's mode or subject. It
   built or changed things during planning or discussion, worked in another
   repo or package, reached for a different workflow mid-execution, or raised
   items the user had parked or dropped.
2. **Overkill.** The question took a yes/no or a single fact, and the answer
   gave a page, a table, or the right "Yes." followed by paragraphs. Length is
   judged against the question, not on its own: 150 words is overkill for
   "yes or no?".
3. **Technical instead of an answer.** The question asked about an outcome —
   "are we protected", "regression or same behaviour", "what does adding this
   change" — and the answer explained the mechanism: policy paths, TTLs, what
   git means by "revert".
4. **Several things in one.** The answer bundled separate questions or
   decisions, so the user would have to answer all of them in one message.

The first line of the reply names the fault in plain words, e.g. "That went
off into build work; the question was what is left to plan." No apology, no
account of why it happened.

## 3. Redo it, by fault

- **Tangent.** Go back to the question and answer it inside the session's
  mode. If the tangent ran commands, wrote files, committed or changed state,
  first list each change: file, command, commit. Undo nothing unless told to.
  Do not carry on the tangent's work.
- **Overkill.** Give the yes/no or the fact, plus at most one line on why.
  Nothing else: no table, no list, no follow-on points.
- **Technical.** Answer the outcome in plain words, for a reader with some
  technical background who wants the result, not the workings. "Yes, except
  the admin export, which still sends the token in the URL." If something is
  not covered, say what it is.
- **Several in one.** Give only the first question or decision, with its
  context: what it is about, what happens today, what each option changes,
  which one is recommended and why. Then stop and wait for the answer before
  giving the next. Say how many are still to come, in one line.

## The part that is easy to get wrong

- **Repeating the fault in the redo.** A redo of an overkill answer that
  explains at length why the first one was overkill is overkill again. A redo
  of a tangent that finishes the tangent's work first is the tangent again.
- **Splitting a sequence of steps.** Fault 4 is about questions and decisions
  the user has to answer. A run of commands meant to be pasted as one, or a
  set of steps to run in order, stays together. "Why have you separated
  everything, rather than one command?" is the complaint when this is got
  wrong.
- **Undoing a tangent's changes unasked.** Listing them is the job; reverting
  them is the user's call, and an unasked revert is a second tangent.
