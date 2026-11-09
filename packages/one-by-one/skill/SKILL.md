---
name: one-by-one
description: Go through a list of questions or points already given one item per reply, each with more detail than the list had — what it is, what happens today, what each option changes — waiting for the user's answer before giving the next. Use only when the user types /one-by-one.
disable-model-invocation: true
---

# one-by-one — take a list one item at a time, in full

The user typed `/one-by-one` because a list of questions or points was given
together, and each item got too little detail to answer well. Go through it
one item per reply, giving each the detail it needs. Do not ask whether to
start.

## 1. Find the list

It is the most recent list of questions, decisions, options, findings or
points Claude gave, including a list of follow-ups such as F-numbered items. If
the user named one (`/one-by-one the decisions`, `/one-by-one F9-F12`), use
that one. Keep the original numbering, so the user can still refer to items by
it.

In the first reply, say in one line which list it is and how many items it
has. Items the user has already answered are left out; say which ones and what
the answer was, in that same line.

## 2. One item per reply

Give only the current item, headed with where it sits: "2 of 5 — <what it
is>". For that item:

- **What it is** — in full sentences: what it concerns, and which file,
  package, phase or system it is about. Every id or reference written out.
- **Now** — what happens today, checked rather than remembered: read the file,
  run the status command.
- **Options** — each option with what it changes and what it rules out later.
  Mark the recommended one and give the reason in one line. A point that is
  information, not a choice, gets what it means for the user instead.

Then stop. Do not give the next item, or a preview of it, in the same reply.

## 3. Move on when the user answers

The user's reply answers the current item. Act on the answer only as far as it
tells you to, then give the next item in the next reply. The user can also
say "skip", "next" or "back"; follow it. If the answer changes a later item —
makes it moot, or changes its options — say so when that item comes up, or
leave it out and say why.

When the last item is answered, give one closing list: every item, in its
original numbering, with the answer it got, each written out in full.

## The part that is easy to get wrong

- **Two items in one reply.** "And while we're here, item 3…" is the bundle
  `/one-by-one` was typed to break up. One item, then stop.
- **The same detail as the list.** Each item needs more than it had, not the
  same sentence again. If the original line was the whole of it, check the
  current state and say what it is.
- **Splitting a sequence of steps.** This is for questions and points the
  user has to answer or weigh. A run of commands meant to be pasted together
  is not a list to go through one by one.
- **Losing the place.** After an answer, the next reply is the next item.
  Not a recap of the last one, and not the remaining items all at once.
