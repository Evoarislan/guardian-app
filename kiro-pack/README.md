# Kiro pack: Guardian (Kiroween 2026, Frankenstein entry)

## What this pack is
The build pack for Guardian, our second Kiroween 2026 entry,
filed under **Frankenstein** (the GhostBridge entry is the
Resurrection flagship, in its own repo and pack). Guardian is a
free, open-source health guardian app for elderly people living at
home: phone-first sensing, any wearable as an optional booster,
and an escalation loop — trigger → cancel window → kin cascade →
monitored dispatch (sandbox in the demo) → FHIR record — stitched
from HealthKit, Health Connect, BLE profiles, Gadgetbridge-class
bridges, phone sensors, Twilio, Noonlight, and FHIR/HAPI, none of
which were designed to meet. That stitch is the Frankenstein
story, and the specs tell it that way.

Contents:
- .kiro/specs/guardian/requirements.md — purpose, the Frankenstein
  claim, locked scope, functional and honesty requirements, the
  pre-existing-code disclosure, and the submission compliance
  checklist.
- .kiro/specs/guardian/design.md — the parts table (foreign body →
  adapter), the FHIR-shaped event spine, the escalation state
  machine, the app shell, consent/routing, and the demo design.
- .kiro/specs/guardian/tasks.md — phases to the Dec 4 deadline,
  each ending at a verification gate.
- .kiro/steering/ — three Guardian-specific files:
  safety-and-honesty.md (never dial 911; simulated always
  labelled; consent governs every share; no medical claims),
  escalation-etiquette.md (cancel window sacred; wearer-defined
  cascade order; every transition logged), and
  verification-protocol.md (tests + log verify + live reproduction
  gate every phase).
- .kiro/hooks/test-gate.json — a DRAFT-shape hook (run the engine
  tests on file save / pre-commit style); adapt it to Kiro's
  installed hook schema in Session 1 before use.
- SESSION-1.md — the paste-ready script for John's first Guardian
  Kiro session: integrate and verify the disclosed, complete
  engine, prove both escalation endings against mocks, stand up
  the app shell.

## How it differs from the GhostBridge pack
- **Different category mechanics.** GhostBridge's pack is a
  family queue: one locked corpse family, member-by-member Proof
  of Life gates, an unmodified rule for other people's code. This
  pack is a phase plan for our own product: engine first, sensors,
  adapters, channels, record, demo — with verification gates
  shaped around honesty (labels, log chain, live reproduction)
  rather than resurrection receipts.
- **Steering is original to this pack.** GhostBridge inherited the
  Mass Necro crew steering from its v1 pack. Guardian's steering
  was written for Guardian: safety law (no direct 911, monitored
  dispatch only), escalation etiquette, and a verification
  protocol whose prohibitions (no credentials in repo, no
  unlabelled data, no medical claims) have no GhostBridge analogue.
- **Pre-existing code is different in kind.** GhostBridge's spec
  assets were paperwork; Guardian also has running code written
  before Session 1 — the COMPLETE, tested engine/ (state machine,
  hash-chained event log, scheduler, notifier interface,
  Noonlight-sandbox payload builder with dispatch disabled, and
  its test suite), the adapters/ contracts and mocks, docs/
  (PRODUCT-SPEC.md, ARCHITECTURE.md, BUILD-PLAN.md), LICENSE, and
  README.md, all authored with Muse's assistance Nov 13, 2026,
  inside the build window. It is disclosed in requirements.md and
  must be disclosed again in the Devpost write-up. Session 1
  integrates and verifies it; it does not rewrite it.
- **No family queue, no spike directive.** Guardian's binding
  external evidence is the feasibility/legal audit
  (docs/concepts/frankenstein-wearable-feasibility.md), not an
  autopsy or a spike.

## The shared-credit note (read before every session)
ONE 4,000-credit Kiro grant funds BOTH entries. There is no
separate Guardian budget. Rules that follow:
- Every session of either entry records the credit balance at
  start and stop in its SESSION-N-RESULT.md.
- Guardian Session 1's guard: flag to Muse if the session would
  push the COMBINED known burn across both entries toward ~1,000
  credits. The same discipline applies in reverse — GhostBridge
  sessions log against the same total.
- If the combined burn ever forces a choice, the flagship's
  remaining gates are protected first and Guardian's later phases
  are the flex — that call is John's, made with the logs in front
  of him, never mid-session by the tool.

Source record: docs/PRODUCT-SPEC.md (product truth),
docs/concepts/frankenstein-wearable-opensource-amendment.md
(John's binding amendments),
docs/concepts/frankenstein-wearable-feasibility.md (feasibility
+ legal shape), engine/ (the disclosed, complete engine).
Stack reconciliation is DONE: Flutter is confirmed by
docs/ARCHITECTURE.md §1, and design.md / SESSION-1.md carry no
provisional stack hedges.
