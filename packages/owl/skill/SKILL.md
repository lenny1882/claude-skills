---
name: owl
description: Redo the previous answer end to end because it skipped steps — every step written out with where it runs, the exact command, any short-lived key it needs, what to capture and the expected output, then Claude runs each step it can and ends on the one command left for the user. Use only when the user types /owl.
disable-model-invocation: true
---

# owl — redo the last answer end to end

The user typed `/owl` because the previous answer skipped most of the steps
needed to finish the task. Redo it completely, from where things stand now to
done. `/owl` is the instruction to run the steps as well as list them — do not
ask whether to start.

## 1. Find the task, then check the current state

The task is what the user's request needed finished, not the last fragment the
previous answer dealt with. Before listing anything, check what is already true
— `git status`, whether files and installs exist, what the last command
actually printed — rather than reusing what the earlier answer assumed.

## 2. List every step, in order

Number them. Write out every step, including ones already done or trivial. Each
step gives all five of these:

- **Where** — exactly one of: Claude's Bash; `!` in Claude Code (the user types
  `! <command>` and the output lands in the conversation); the user's own
  terminal. Name the machine when it is not this one.
- **Command** — exact and complete, ready to paste. A placeholder only for a
  value only the user has, and then say where it comes from.
- **Needs** — any short-lived or single-use key, token, login or code: exactly
  how to get it (the URL, command or menu path), and how long it stays valid.
  Long-standing accounts the user already has are not listed.
- **Capture** — what to keep from the output and where it goes. A script handed
  to the user logs its own output to a file Claude can read, such as
  `/tmp/<script>-<subcommand>.log`, built into the script.
- **Expect** — the output that means it worked, and what a failure looks like.

## 3. Run every step Claude can run

Go through the steps in order and run each one whose **Where** is Claude's
Bash. Report each result against its **Expect**. On a failure, fix it and
carry on, or stop and report the full error. An outward-facing step — a push,
a post, a release — still needs the user's approval of that one action; ask
for it, and run the rest.

## 4. End on the one remaining command

The last line of the answer is the single command left for the user, on one
line — steps joined with `&&`, refs combined into one `git push --atomic`, and
so on — with where to run it. If nothing is left for the user, say it is done
and what showed it.

## The part that is easy to get wrong

Each of these reproduces the answer `/owl` was typed to replace:

- Listing only the steps the earlier answer skipped. The user needs the whole
  route in one place.
- Collapsing steps: "repeat for the others", "and so on", "set up the rest".
- Listing the steps and then asking "shall I run them?".
- Ending on a block of commands, or on several separate commands, instead of
  one line.
