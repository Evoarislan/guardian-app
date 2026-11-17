# Guardian: Requirements

## Purpose
Guardian is a free, open-source health guardian for elderly people
living at home. It watches for the moments a wearer cannot call for
help themselves — a fall, the long lie that follows, a dangerous
vital-sign pattern, a check-in that never comes — and moves help
toward them automatically: family first, then monitored professional
dispatch, with a clinical record written either way.

Guardian is the Kiroween 2026 **Frankenstein** entry (second entry;
the GhostBridge Resurrection entry is the flagship, separate repo).
Product record: docs/PRODUCT-SPEC.md (approved by John, Nov 13,
2026). Binding concept amendments:
docs/concepts/frankenstein-wearable-opensource-amendment.md
(vendor-neutral open source; app-first, no purchase required).
Feasibility and legal record:
docs/concepts/frankenstein-wearable-feasibility.md.

## The Frankenstein claim (this is the category story)
Guardian stitches together technologies that were never designed to
meet, into one body with one spine:

- Apple **HealthKit** and Android **Health Connect**: two rival,
  incompatible health-store contracts, read behind one adapter
  contract.
- Standard **BLE profiles** (Heart Rate 0x180D/0x2A37) from straps
  and workout-mode bands that expose them.
- **Gadgetbridge-class bridges**: reverse-engineered BLE protocols
  for Xiaomi/Amazfit/no-name bands that never touch a health store.
- The **phone's own sensors**: raw accelerometer, GPS, camera PPG —
  the only always-present, real-time layer.
- A **Twilio** SMS/voice cascade: consumer telecom plumbing.
- **Noonlight's monitored-dispatch API** (sandbox for the demo):
  a human-staffed central station behind a REST call.
- **HL7 FHIR R4** (HAPI server): the clinical world's data language.

None of these share a data model, a tempo, or an owner. Guardian's
event spine normalizes all of them into one FHIR-shaped record, one
detection/escalation engine, and four consent-based role views.
The stitching is the product, and it is the Frankenstein claim.

## Scope (locked by John's amendments)
- **App-first**: Android + iOS app. The base device is the phone the
  wearer already owns. Nobody has to buy anything.
- **Vendor-neutral, open source (MIT)**: any wearable that can reach
  the phone through an open route is a first-class citizen. Garmin,
  Apple-direct, and other brand connectors are optional future
  adapters behind the same ingestion contract, never requirements.
- **Detection and escalation only**: Guardian is a consumer safety
  aid, not a medical device. No diagnosis, no clinical claims.
- **Never dials 911**: automated dialing of emergency lines is
  prohibited (US FCC rules; Quebec Civil Protection Act s. 20;
  Canadian municipal bylaws). The dispatch step hands a verified
  alarm to a monitored dispatch partner (Noonlight class) whose
  human agents contact local emergency services. In the demo build,
  dispatch runs against Noonlight's developer SANDBOX and says so
  on screen.

## Functional requirements
1. SENSING, PHONE FIRST: on-device accelerometer fall detection,
   inactivity / long-lie pattern detection, and missed check-in
   escalation. Android runs a foreground service for continuous
   sensing; iOS leans more on health-store signals and check-ins
   (platform asymmetry is stated to the wearer, not hidden).
2. AGGREGATION: read heart rate, SpO2, steps, and sleep from
   HealthKit (iOS) and Health Connect (Android) behind ONE adapter
   contract. Every reading carries source and timestamp; freshness
   (live / fetched + age / simulated) is shown wherever a value is
   shown.
3. OPTIONAL SIGNAL BOOSTERS: BLE Heart Rate Profile devices read
   directly; Gadgetbridge-class import for budget bands. Each is an
   adapter; none is required for the core loop.
4. DETECTION ENGINE: deterministic rules/state machine over the
   normalized event spine: hard-fall signature, inactivity after a
   motion anomaly, vital-sign thresholds personal to the wearer,
   missed check-in. The logic is identical regardless of which
   source fed it.
5. ESCALATION (the core loop): trigger → **cancel window** (default
   60s, one huge "I'm OK" button; the window is ALWAYS honoured) →
   **kin cascade** (one ordered pass over wearer-defined contacts,
   SMS + voice with live location; per-contact acknowledgment
   timeout, default 120s; any acknowledgment stops the cascade
   and resolves the episode) → **dispatch** (only when the cascade
   is exhausted without acknowledgment: alarm to the
   monitored-dispatch interface; sandbox in the demo build) →
   **record**. There is no separate dispatch window.
6. EVENT LOG: every transition is appended to a hash-chained,
   tamper-evident event log. The log is the audit trail for every
   claim the demo makes.
7. FHIR RECORD: episodes and vitals are written as FHIR R4
   resources (Observation with LOINC codes, Patient, Device,
   Encounter/Flag) to a HAPI FHIR server (local preferred; the
   public test server only with synthetic data) and read back into
   the provider view.
8. CONSENT AND ROUTING: the wearer controls every share, per role,
   revocable from the wearer's phone: kin alerts, kin full view,
   provider record, nutritionist summary. Escalation order and
   windows are wearer-defined. Consent state is part of the record
   and visible in the app.
9. FOUR ROLE VIEWS: wearer (big-button, high-contrast, voice
   prompts), next of kin (alerts + daily digest + check-in status),
   provider (FHIR-backed record + export), nutritionist
   (event-linked summary — a role view of the same record; there
   is no nutritionist system to integrate with, and the app says
   so).
10. CAMERA PPG SPOT CHECK: fingertip heart-rate spot check,
    labelled as a spot check, never presented as continuous
    monitoring.

## Honesty requirements (binding; see steering/safety-and-honesty.md)
- Simulated data is ALWAYS labelled simulated, on screen and in any
  recording. Live and fetched data are labelled with source and age.
- No claim in the demo that cannot be reproduced live in the demo.
- The honest limits from PRODUCT-SPEC.md Section 6 ship in the app:
  phone-on-person requirement, iOS/Android sensing asymmetry,
  sandbox dispatch, vitals freshness, not-a-medical-device.

## Disclosure (Kiroween rules: pre-existing code must be disclosed)
The following were authored with Muse's assistance on Nov 13,
2026, inside the Oct 30 - Dec 4 build window, before the first
Kiro session, and are disclosed as pre-existing in the submission
write-up:
- engine/ — the COMPLETE, tested escalation engine: engine.js
  (state machine), eventlog.js (hash-chained log), scheduler.js,
  notifier.js, dispatcher.js, index.js, and test/.
- adapters/ — health-store.js, ble-hr.js, phone-sensors.js, and
  README.md (adapter contracts and mocks).
- docs/ — PRODUCT-SPEC.md, ARCHITECTURE.md, BUILD-PLAN.md.
- LICENSE and README.md at the repo root.
All Flutter app code, and the integration of the above, are built
in Kiro sessions from Session 1 on.
- Techniques carried from our earlier projects (hash-chained
  append-only logs) are disclosed the same way.

## Compliance checklist (submission)
- [ ] Public GitHub repo, MIT license file detectable at repo root.
- [ ] /.kiro at repo root, NOT in .gitignore (specs, steering,
      hooks if adapted).
- [ ] Category identified on the submission form: **Frankenstein**.
- [ ] Judge access: public GitHub Release with the Android APK
      attached and install instructions in the repo README, plus
      the demo video. iOS is presented via the demo video and
      screenshots — no TestFlight build is promised.
- [ ] Demo video public on YouTube, under 3 minutes, shows the
      project functioning, no copyrighted music or third-party
      trademarks.
- [ ] Text description discloses pre-existing code (above).
- [ ] Shared-credit log current (one 4,000-credit grant funds BOTH
      Kiroween entries; see pack README).
- [ ] Blog Bonus: a qualifying public blog post mentioning
      Kiroween 2026 is published and linked from the submission.
- [ ] Social Blitz: post published, starting with
      #KiroweenHackathon26.
- [ ] Best Demo: no separate entry — Best Demo is judged from the
      demo video's Presentation score; the video is cut with that
      in mind.
- [ ] Best Startup: CLAIM or SKIP — John's decision, recorded
      before submission; not claimed by default.
