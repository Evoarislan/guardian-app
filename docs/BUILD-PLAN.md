# Guardian — Build Plan

Target: **demo-able v1 by Dec 4, 2026** (21 days from Nov 13).
Builder: John (solo) + Muse, Kiro-assisted build on John's machine.
Companion docs: PRODUCT-SPEC.md, ARCHITECTURE.md.

This plan builds the **product**. Guardian IS the Kiroween
Frankenstein entry — John decided Nov 13, 2026. Entry-specific work
sits in Phase 6 (committed) and nothing in Phases 0-5 depends on
it, but Phase 6 is part of the plan, not an option. Total effort
is ~16-21 pd (core ~13-17 pd + entry extras ~3-4 pd). Effort is
in person-days (pd) of focused build time; calendar fit is
checked against the fact that GhostBridge already occupies much of
this window (see §5, the honest constraint).

---

## Phase 0 — Foundations (1 pd)

- Repo `guardian-app` created (public, MIT license as shipped in
  the repo LICENSE file),
  Flutter project scaffold, feature-folder layout per ARCHITECTURE.md §9.
- `.kiro/` pack: specs (guardian core loop), steering files
  (honesty-labelling rules, escalation-safety rules, consent rules),
  hooks (run engine tests on change; block "done" on red tests;
  write build receipt). Hook JSON adapted to Kiro's installed schema.
- Backend skeleton (thin executor) with env-based secrets; Twilio
  trial account + Noonlight developer sandbox token obtained by John
  (accounts are his step; no spend beyond trial credit).
- Local HAPI FHIR server running via Docker on the dev machine.
- **Exit gate:** empty app installs on one Android phone and one
  iPhone; backend health-check answers; HAPI accepts a test
  Observation create/read.

## Phase 1 — Sensing + ingestion (3-4 pd)

- Health-store adapter: `health` package integration, HealthKit +
  Health Connect permission flows, HR/SpO2/steps/sleep reads into
  the normalized Reading model with source + freshness stamps.
- Phone sensor layer: accelerometer stream, fall-signature pipeline
  (free-fall → impact → immobility), Android foreground service;
  iOS foreground + motion-history queries within platform limits.
- Inactivity/long-lie timer and missed-check-in scheduler (local
  notifications as soft prompts).
- Demo Trace Simulator adapter: replays labelled traces through the
  same ingestion contract (badged SIMULATOR end to end).
- Wearer view v0: today's signals with source/freshness labels,
  big-button "I'm OK / I need help", active-protections panel
  (honest per-OS capability display).
- **Exit gate:** dropping the dev phone onto a cushion produces a
  real fall CANDIDATE event from real sensor data; health-store
  readings from a real paired source (or the labelled simulator)
  appear with correct freshness.

## Phase 2 — Escalation engine + cascade (3-4 pd)

- Dart port of the escalation engine with test-parity against
  the verified Node.js reference implementation in `engine/`
  (ARCHITECTURE.md §1/§5): the port implements the same state
  machine and declarative transition table (MONITOR →
  CANDIDATE → ALERTING → CASCADING → KIN_HANDLED / DISPATCHED →
  RECORDED, with the manual-help shortcut and
  undelivered-failure recording), exchanges episode logs in the
  reference engine's exported JSON format, and must reproduce
  the Node suite's transitions on the same traces. The port is
  budgeted inside this phase's 3-4 pd.
- Unit/replay tests: recorded cushion-drop trace + synthetic
  vitals/check-in traces replayed through the real table, in both
  the Node reference suite and the Dart port; red suite blocks
  phase sign-off (hook-enforced).
- Backend cascade executor: Twilio SMS + voice down the ordered
  kin list, ack handling (keyword reply / link), all-contacts
  notification on ack, location link in every message.
- Cancel window UX: full-screen alarm, one huge "I'm OK", voice
  prompt, 60 s default countdown, wearable-agnostic (phone only).
- **Exit gate:** end-to-end on real phones — drop test → alarm →
  (no cancel) → real SMS + call land on a second phone → ack stops
  the cascade → event recorded with a complete timeline.

## Phase 3 — Dispatch + FHIR record (2-3 pd)

- Noonlight sandbox adapter behind the dispatch interface:
  alarm create with location + event summary, sandbox alarm ID
  captured into the event; UI and copy state "sandbox — no
  emergency services contacted" wherever dispatch appears.
- FHIR writer: Patient/Device/Observation/Encounter/Flag/
  Provenance mapping per ARCHITECTURE.md §7, POSTed to local HAPI;
  freshness + source preserved in the Observation extension.
- Provider view: FHIR-backed record — event history, vitals with
  ages, trend summary, export (FHIR bundle JSON + printable report).
- **Exit gate:** a dispatched demo event is visible in HAPI,
  read back in the provider view, with the sandbox alarm ID on the
  Encounter and every reading's provenance intact.

## Phase 4 — Consent, routing policy, remaining role views (2-3 pd)

- Grant model + policy store (ARCHITECTURE.md §6): per-role,
  per-data-class grants; escalation order/windows; per-event-type
  routing; policy versioning stamped onto events; revocation and
  the wearer-readable audit log.
- Kin view: alert detail with live location (event-scoped),
  acknowledge action, daily all-quiet digest.
- Nutritionist view: event-linked summary (post-event activity /
  sleep / appetite-proxy trends), exportable.
- Camera PPG spot check: 30 s fingertip HR, labelled as a spot
  check, written to the record; never an emergency trigger.
- Wearer settings pass for the actual user: text size, contrast,
  voice prompts, passwordless sign-in flow.
- **Exit gate:** toggling a grant changes what the corresponding
  role view shows on the next event, and the audit log explains
  every share that occurred during the Phase 2-3 demo events.

## Phase 5 — Hardening + demo rehearsal (2 pd)

- Failure drills: backend down (on-device fallback + honest
  "undelivered" recording), no network, denied permissions per
  type, stale-vitals downgrade rule (old readings → digest, never
  cascade), iOS protection-level differences displayed correctly.
- Battery sanity on Android foreground service; false-alarm tuning
  on the fall pipeline against a scripted set of non-fall motions
  (sitting down hard, phone tossed on a bed, walking) — results,
  including misses, written into the demo notes as numbers.
- Full demo run rehearsed end to end twice on the real demo
  phones; timing pass against the script in §4.
- **Exit gate:** two consecutive clean full-loop runs; every
  failure drill produces the honest UI state, not a crash or a
  silent success.

**Core total (Phases 0-5): ~13-17 pd.**

## Phase 6 — Kiroween entry extras (COMMITTED) (3-4 pd)

Guardian is entered in Kiroween 2026 (Frankenstein category) —
John's decision, Nov 13, 2026. This phase is committed. None of
it touches the product code paths above.

- Devpost submission package: description built on the problem
  numbers (long-lie evidence) and the equity spine; category filed
  as Frankenstein (stitched open protocols: health stores, BLE
  profile shapes, phone sensors, telephony, dispatch API, FHIR —
  the chimera is the ingestion spine).
- Demo video (<3 min) per §4, captured from real runs.
- Blog Bonus post (build story: the honest-limits design process)
  + Social Blitz post starting with #KiroweenHackathon26, John's
  own words.
- Gallery hygiene: live demo instructions (sandbox dispatch +
  local-HAPI read-back path documented for judges), repo README
  with the real-vs-simulated table from ARCHITECTURE.md §8.

**Total, entry extras included (committed): ~16-21 pd.**

## Phase 7 — Open decisions (John's, recorded here)

- **Priority rule: PENDING** — John's decision, drop-dead
  Nov 16, 2026. Until it is recorded, neither entry is documented
  as protected: if the window forces a choice between GhostBridge
  and Guardian, no doc in this repo pre-decides which one yields.
- **Credit allocation: PENDING** — the per-entry split of the
  shared 4,000-credit grant is to be set from GhostBridge
  Session 1 burn data, before Guardian Session 1 runs. Interim
  guard: flag and pause for review as combined known burn
  approaches each 1,000-credit mark.

## 4. Demo script shape (the 3-minute story)

1. **0:00 — The problem.** One statistic on screen: 97% of long
   lies happened to people who owned an alarm they never pressed.
   "Guardian presses it for them — on the phone already in their
   pocket."
2. **0:20 — The stitch.** The demo phone's signal panel: phone
   sensors live, health-store readings with ages (real paired
   source or the badged simulator), the four role views in one row.
3. **0:45 — The fall.** The phone is dropped onto a cushion.
   Real accelerometer trace spikes on screen; ALERTING fires;
   the cancel window counts down, huge "I'm OK" untouched.
4. **1:15 — The cascade.** Window expires. A second phone (kin)
   rings and buzzes with the real Twilio call + SMS, location
   included. Nobody acks.
5. **1:45 — Dispatch.** The cascade pass exhausts with no ack; Noonlight sandbox
   alarm fires; the sandbox alarm ID lands on the event, beside
   the on-screen label "sandbox — production needs a monitoring
   partnership; Guardian never dials 911 itself."
6. **2:10 — The record.** Provider view: the event as FHIR —
   Encounter, Observations with provenance and freshness — read
   back from HAPI. Nutritionist view shows the event queued into
   the follow-up summary.
7. **2:40 — The close.** Revoke the kin grant live; the next view
   shows the data gone. End card: "Open source. Any phone. Any
   wearable. No button to press."

## 5. Kill / scope lines (binding)

- **Dec 4 is a demo-able v1, not a launch.** Anything requiring a
  contract (production dispatch, EHR registration, Google OAuth
  verification, Garmin program) is out by definition; interfaces
  are built, partnerships are not chased.
- **If Phase 2's exit gate is not met by ~Nov 27**, cut in this
  order: (1) camera PPG, (2) nutritionist view (ship as export
  only), (3) iOS sensing depth (iOS demo rides health-store +
  check-ins; Android carries the fall demo). The core loop —
  detect → cancel → cascade → sandbox dispatch → FHIR record — is
  never the cut.
- **No silent stubs.** Any adapter not genuinely wired is badged
  simulated or removed from the demo path. A smaller honest demo
  beats a larger staged one (the ScopeHound lesson, and the
  winner-pattern evidence).
- **GhostBridge contention is real.** GhostBridge (locked flagship)
  plus its boost plan already claim much of Nov 13-Dec 4. This
  plan's 13-17 core pd does not fit *alongside* GhostBridge at full
  scope in the same solo window; both are now committed entries, so
  if the window forces a choice, one takes the Nov 27 cut above —
  which one yields is governed by the priority rule, which is
  PENDING John's decision (drop-dead Nov 16, 2026; see Phase 7).
  The plan is written to be executable standalone or post-Kiroween
  unchanged.
- **Safety stop:** no real wearer pilots, no real health data on
  shared/public servers (public HAPI is for synthetic demo data
  only; the demo runs on a local HAPI), and no production dispatch
  claims anywhere — in the app, the video, or the write-up.
