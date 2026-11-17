# Steering: Escalation Etiquette (Guardian — binding)

The escalation loop touches frightened people and their families.
How it behaves matters as much as whether it works.

## The cancel window is sacred
- Every trigger opens the cancel window first (default 60s,
  wearer-configurable). A wearer cancel ALWAYS wins: it resolves
  the episode, stops every downstream step, and is logged as a
  good outcome, not a failure.
- A cancel that arrives after the window but before dispatch
  still stops the escalation. Only an alarm already handed to the
  dispatch partner is beyond recall, and the wearer is told that
  plainly if it happens.
- The cancel affordance is one huge button, a loud alarm, and a
  voice prompt. It must be operable by a shaken person on the
  floor: no menus, no small text, no confirmation dialogs.

## The cascade respects the wearer's order
- Kin are contacted in the exact order the wearer (or their
  delegate) set. Never reorder by "likelihood to answer," never
  skip a contact silently, never add a contact the wearer did not
  name.
- Any kin acknowledgment pauses escalation and notifies the rest
  of the cascade that someone is handling it. The episode records
  who acknowledged and when.
- Messages to kin are plain and factual: what triggered, where
  (live location when granted), what Guardian has already done,
  what happens next if nobody responds. No speculation about the
  wearer's condition ("possible fall, no response to the alarm" —
  never "she has fallen and is injured").

## Every transition is logged
- Trigger, window open, cancel or lapse, each cascade step, each
  acknowledgment, dispatch, resolution: each is appended to the
  hash-chained event log BEFORE its side effect fires.
- The log is the episode's memory and the demo's proof. An
  unlogged action did not happen; a logged action that did not
  happen is fraud. Keep them identical.

## Dispatch is the last step, not the first
- Dispatch fires only after the cancel window lapses AND one
  ordered cascade pass over the kin contacts exhausts with no
  acknowledgment (per-contact acknowledgment timeout, default
  120s) — or when the wearer's own policy says otherwise (e.g.,
  an explicit SOS). There is NO separate dispatch window; that
  model was superseded by the canonical timing model settled
  Nov 13, 2026 (ARCHITECTURE.md, requirements.md, engine/).
  Never shorten windows for a demo.
- The wearer and kin are told a dispatch happened, with the
  partner's reference ID, as soon as it returns.
