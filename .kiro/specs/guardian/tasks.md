# Guardian: Tasks

Deadline: **Dec 4, 2026, 2:00 PM PT** (Kiroween submission).
Category: **Frankenstein**. Every phase ends at a verification gate
(steering/verification-protocol.md): tests green, claims
reproducible live, event log verifies. No gate, no next phase.

Shared-resource note: One shared 4,000-credit grant funds both
Kiroween entries; every session logs start/stop balances; flag
and pause for review as combined known burn approaches each
1,000-credit mark; per-entry allocation is set from GhostBridge
Session 1 burn data before Guardian Session 1 runs.

## Phase 0: Prep (before / alongside Session 1)
- [x] Concept + feasibility + legal record (Kiroween entry folder,
      concepts/frankenstein-wearable-*.md, Nov 13)
- [x] John's amendments locked: vendor-neutral open source;
      app-first Android + iOS, no purchase required (Nov 13)
- [x] Frankenstein entry designated by John (Nov 13)
- [x] Product spec (docs/PRODUCT-SPEC.md)
- [x] Engine COMPLETE and tested, pre-existing and DISCLOSED:
      engine/ — engine.js (state machine), eventlog.js
      (hash-chained log), scheduler.js, notifier.js (console/mock),
      dispatcher.js (Noonlight sandbox payload builder, dispatch
      disabled by default), index.js, test/ (tests pass)
- [x] Adapters, pre-existing and DISCLOSED: adapters/ —
      health-store.js, ble-hr.js, phone-sensors.js, README.md
- [x] Docs and root files, pre-existing and DISCLOSED: docs/
      (PRODUCT-SPEC.md, ARCHITECTURE.md, BUILD-PLAN.md), LICENSE,
      README.md
- [x] This /.kiro pack (specs + steering + SESSION-1.md)
- [x] Stack reconciliation DONE: Flutter confirmed by
      docs/ARCHITECTURE.md §1; design.md and SESSION-1.md carry
      no provisional stack hedges
- [x] .kiro/hooks/test-gate.json adapted from its DRAFT shape to
      Kiro's installed hook schema (ships as a draft in this
      pack; adaptation is a Session 1 step — see SESSION-1.md)
- [ ] Repo created on GitHub (public, MIT license at root; John's
      go at creation time); .kiro committed, NOT gitignored

## Phase 1: Engine integration + app shell (Session 1)
- [x] Integrate and verify the existing tested engine (engine/,
      pre-existing, disclosed) — do NOT rebuild the state machine.
      Its states are the project's vocabulary: IDLE → TRIGGERED →
      CANCEL_WINDOW → CASCADE → DISPATCH → RESOLVED. Wearer cancel
      inside the cancel window returns to IDLE, logged as
      cancelled. Dispatch happens only on cascade exhaustion,
      with the sandbox payload built and logged, never sent.
      Verification gate: the engine's own test suite passes
      unmodified
- [x] Mock adapters: TraceSimulatorAdapter emitting LABELLED
      simulated signals; MockNotifier; sandbox-payload Dispatcher
      (payload built and logged; nothing sent, no credentials)
- [x] Flutter app shell (stack confirmed, ARCHITECTURE.md §1):
      wearer home (big-button), cancel-window screen, episode
      timeline rendering proofs/episode-log.json (the log bridge
      exported by the Step 4 proof runner)
- [x] End-to-end proof on mocks: simulated fall → cancel window →
      (a) wearer cancel → engine back to IDLE, cancellation
      logged, log verifies; (b) lapse path → one ordered cascade
      pass in wearer order (per-contact ack timeout, default
      120s) → cascade exhausted → DISPATCH with sandbox payload
      logged → RESOLVED. Proof runner exports both episodes to
      proofs/episode-log.json
- [x] SESSION-1-RESULT.md with burn log, gaps listed, no silent
      stubs

## Phase 2: Sensor layer, phone first
- [x] Dart port of the escalation engine with test-parity against
      the Node reference implementation in engine/ (its suite is
      mirrored case-for-case; the Node engine stays the verified
      reference)
- [ ] PhoneSensorAdapter: accelerometer stream, hard-fall
      signature, inactivity/long-lie pattern, missed check-in
      scheduler; Android foreground service; iOS limitations
      surfaced in-app ("which protections are active on this
      phone")
- [ ] Drop test on a real phone drives a real trigger end to end
- [ ] Verification: trigger reproducible on demand; false-positive
      behaviour observed and noted honestly (no tuned-for-demo
      thresholds hidden from the write-up)

## Phase 3: Aggregation adapters (harden the existing adapters)
The adapter contracts and mocks in adapters/ are pre-existing and
disclosed. This phase hardens them against real sources; it does
not build them from scratch.
- [ ] HealthStoreAdapter (adapters/health-store.js) moved from
      mock to real reads: Health Connect (Android) and HealthKit
      (iOS) behind the one existing contract; HR, SpO2, steps,
      sleep; source + observedAt preserved; freshness shown in UI
- [ ] Vitals guardrails: per-wearer thresholds over the freshest
      readings, age displayed with every value
- [ ] BleHeartRateAdapter (adapters/ble-hr.js) hardened against a
      real 0x180D device (straps / workout-mode bands)
- [ ] BridgeImportAdapter: Gadgetbridge-class export/import for a
      budget band, labelled fetched with sample ages
- [ ] Verification: one real wearable reading visible in the app
      with correct source/freshness labels, or the gap stated in
      the result file (no simulated reading dressed as live)

## Phase 4: Cascade + sandbox dispatch (real channels, reviewed)
- [ ] Twilio trial wiring behind the Notifier interface:
      credentials from environment only, never in repo; real SMS +
      voice to the demo kin phones; acknowledgment intake (reply /
      keypress / app tap) pauses escalation
- [ ] Noonlight SANDBOX wiring behind the Dispatcher interface:
      sandbox token from environment; alarm POST to
      api-sandbox.noonlight.com; sandbox alarm ID displayed and
      logged; on-screen "sandbox — no emergency services are
      contacted" disclosure visible in the flow
- [ ] Verification: a full uncancelled episode reaches a real
      sandbox alarm ID with the log chain verifying; NO production
      account, NO production credential, NO direct emergency-number
      call anywhere in the code (grep proves it)

## Phase 5: FHIR record + role views
- [ ] FhirRecordWriter: episode + vitals as FHIR R4 (LOINC-coded
      Observations, Patient, Device, Encounter/Flag) to a LOCAL
      HAPI server; read-back into the provider view
- [ ] Role views completed: wearer, kin (alerts + digest),
      provider (record + export), nutritionist (event-linked
      summary); consent grants enforced at send/render time;
      revocation tested
- [ ] Camera PPG spot check, labelled as a spot check
- [ ] Verification: judge-shaped run — POST an episode, read it
      back in the provider view, revoke a grant, show the share
      stop

## Phase 6: Demo flow + demo build
- [ ] The demo flow (design.md) runs end to end on one phone:
      drop test → cancel window lapses → real cascade → sandbox
      alarm ID → FHIR read-back → log verifies
- [ ] Judge package: public GitHub Release with the Android APK
      attached; install instructions in the repo README; demo
      video linked. iOS is presented via the demo video and
      screenshots only — no TestFlight build is promised
- [ ] Demo build packaged with test instructions a judge can
      follow without help; every screen's data labelled
      live/fetched/simulated
- [ ] Failure honesty pass: anything in the flow that only works
      sometimes is either fixed or disclosed in the write-up

## Phase 7: Submission assets (by Dec 2-3)
- [ ] Demo video under 3 minutes, public on YouTube: the drop
      test, the cascade, the sandbox alarm, the record; honest
      limits stated in the video, not just the fine print
- [ ] Devpost text: Frankenstein stitch story (design.md parts
      table), the equity spine, honest limits, pre-existing-code
      disclosure (Phase 0 list), shared-credit note
- [ ] Compliance checklist in requirements.md fully ticked
- [ ] Blog Bonus: qualifying public blog post mentioning
      Kiroween 2026 published and linked from the Devpost text
- [ ] Social Blitz: post published, starting with
      #KiroweenHackathon26
- [ ] Best Demo: video reviewed against the Presentation
      criterion (Best Demo derives from it); no separate entry
- [ ] Best Startup: CLAIM or SKIP — John's decision, recorded
      before submission; not claimed by default
- [ ] Submit Dec 2-3; Dec 4 is verification only
