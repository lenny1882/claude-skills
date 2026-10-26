---
name: again
description: Re-present the last question set or list in full — every item with its context, the current behaviour and the options, and every bare reference (F-numbers, 1b-style answers, D-NN decision ids, requirement ids) written out. Use only when the user types /again.
disable-model-invocation: true
---

# again — re-present the last question set or list in full

The user typed `/again` because the last question set or list could not be
read on its own. Give it again so that it can be answered without scrolling up
or remembering anything.

## 1. Find what to re-present

It is the most recent set of questions, options, findings or numbered items
Claude gave — including a list of follow-ups such as F-numbered items. If the
user named one (`/again F4`, `/again the decisions`), use that one.

## 2. Give every item in full

Keep the original numbering, so answers already given still map to the right
item. For each item:

- **What it is** — in full sentences: what it concerns and which file, package,
  phase or system it is about.
- **Now** — the current behaviour or state, as checked, not as remembered.
- **Options** — each option with what it does and what it rules out later.
  Mark the recommended one and give its reason in one line.

Include every item, answered ones too. Mark an answered item as answered and
give the answer, so the set stays complete. Add no new items and drop none.
Change a recommendation only when the facts behind it have changed, and say
what changed.

## 3. Write out every bare reference

Any reference whose meaning is somewhere else in the conversation gets written
out where it appears:

- F-numbers (`F7`) — what that item is.
- Answers like `1b` or `2a` — the question and the option they chose.
- Decision ids (`D-12`) and requirement ids (`REQ-04`) — the decision or
  requirement itself.
- Phase or plan numbers, commit hashes, "the above", "as before", "option 2" —
  what each one is.

The id can stay in brackets after the text, so it can still be quoted back.

## The part that is easy to get wrong

Shortening the second time round. "Same as before", "see F3" and "unchanged"
are the reason `/again` was typed. The re-presented set is longer than the
original, never shorter.
