# Session prompt — iOS App Store v1 phases

Paste the block below verbatim into a fresh Claude Code session to start (or
resume) the current phase. Prepend a line for anything decided or completed
since the last session that the plan docs don't yet reflect — e.g. "Apple
developer setup is done, the .p8 is provisioned" or "for SIWA on the PWA,
take the N/A exception."

```
Continue the iOS App Store v1 plan: work the current phase to its exit gate,
then commit and push.

Protocol:
- Read docs/plans/ios-appstore-v1.md first — its Status line names the
  current phase; follow §2 decisions and the §2.1 governing rule (behavior
  parity, native presentation).
- Read the current phase's doc under docs/plans/ios-v1/ including its
  Progress log and Notes, plus any companion docs it references
  (e.g. docs/apns-implementation-plan.md for P5).
- Work only the current phase. Do not start the next phase, even if you
  finish early.
- Keep docs/plans/client-parity.md rows in sync (the pre-push parity gate
  enforces this). For an iOS-only push, the pre-push hook needs
  SKIP_PARITY=1 — that's the sanctioned bypass used for P4.
- Some items only I can do: Apple developer portal setup, physical-device
  and TestFlight verification, App Store submission, owner sign-offs. Build
  and test everything that doesn't require those, leave their checklist
  items unticked, and end your summary with a clear "what I need from you"
  list. If the exit gate itself is owner-gated, update the index Status line
  to "code complete, <thing> pending" rather than marking the phase done.
- Verify before committing: build + NabuTests on a simulator (snapshot
  references under ios/NabuTests/__Snapshots__ were recorded on iOS 26 —
  keep them green, and snapshot any new visible UI), make test-go,
  make test-js, and any e2e specs the phase's exit gate names.
- Before ending: tick completed checklist items, append a dated note to the
  phase doc's Progress log, and update the index Status line.
```
