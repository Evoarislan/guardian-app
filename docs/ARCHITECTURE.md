# Guardian — Architecture

Companion to PRODUCT-SPEC.md. Design law inherited from the concept
record (Nov 13, 2026, as amended by John): **vendor-neutral, open
source, app-first, no purchase required.** Garmin/Apple-direct
connectors are optional future adapters behind the ingestion
contract, never dependencies. Partnership-gated surfaces (Garmin
Health API, production dispatch, real EHRs) are designed as plugs,
not foundations.

---

## 1. Stack choice: Flutter

**Decision: Flutter (Dart), single codebase for Android + iOS.**

Justification, in order of weight:

1. **One health-store contract, twice.** The `health` package for
   Flutter wraps **both** Apple HealthKit and Android Health Connect
   behind a single Dart API (same data types, same permission flow
   shape). The aggregation layer is Guardian's centre of gravity;
   Flutter is the only cross-platform option where it is one plugin,
   maintained, covering both stores. In React Native the equivalent
   is two unrelated libraries (react-native-health for iOS,
   react-native-health-connect for Android) with different models —
   double the integration surface for a solo builder.
2. **Solo builder + Kiro-assisted build.** One language, one widget
   tree, one state model. The escalation engine is a deterministic
   state machine; Dart's isolate model and Flutter's reactive UI let
   the sensor layer, engine, and role views live in one codebase
   without a JS bridge tax. Kiro specs map cleanly onto a
   feature-folder Dart layout.
3. **Sensor and platform access without escape hatches becoming the
   architecture.** Accelerometer (sensors_plus / platform channels),
   camera for PPG (camera plugin), background execution (Android
   foreground service via flutter_foreground_task; iOS background
   modes within Apple's limits) are all reachable. Where native code
   is unavoidable (Android foreground service polish, iOS motion
   coprocessor queries), it is isolated in one `platform/` folder per
   OS, behind Dart interfaces — never smeared across features.
4. **Testing the safety logic.** The escalation state machine's
   behaviour is pinned by a verified reference implementation (see
   "Engine placement" below) and must be unit-testable without a
   device, which matters more here than in most apps: the loop must
   be provably correct on simulated feeds before it ever runs on a
   person.

**Engine placement.** The escalation engine exists today as a
plain Node.js implementation in `engine/` (hash-chained event log,
notifier/dispatcher interfaces, deterministic injected scheduler,
a passing test suite). That Node implementation is the **verified
reference implementation**: it defines the behaviour. The Flutter
app integrates with it via an exported episode-log JSON (the app
emits and consumes episode logs in the reference engine's format),
and a Dart port of the engine — held to test-parity against the
Node suite, replaying the same traces to the same transitions —
is a BUILD-PLAN Phase 2 task. Until the port passes parity, the
Node engine is the source of truth for escalation behaviour.

Considered and rejected: React Native (fragmented health-store
libraries, two permission models to hand-stitch, JS bridge latency
on sensor streams); fully native dual builds (Kotlin + Swift) —
correct long-term, roughly double the effort, indefensible for a
solo builder on a Dec 4 clock; PWA (no HealthKit/Health Connect
access, no reliable background sensing — a non-starter for this
product).

**Backend: deliberately thin.** A small server (Node/TypeScript or
Dart Frog; final pick at build start) hosts exactly four things the
phone cannot: the Twilio cascade executor (API keys never ship in an
app), the Noonlight client, the FHIR writer/reader against HAPI, and
the consent/policy store of record for multi-device families. All
detection runs **on-device**; the backend sees events, not raw
sensor streams. This keeps the privacy story true ("your raw
movement data never leaves your phone") and the demo hostable on a
laptop.

---

## 2. System overview

```
                        ┌─────────────────────────────┐
   SIGNALS              │        GUARDIAN APP          │
 ┌──────────────────┐   │  (Flutter, Android + iOS)    │
 │ Phone sensors    │──▶│                              │
 │ (accel/GPS/mic)  │   │  Ingestion adapters ──▶ Event│
 ├──────────────────┤   │        spine (normalized,   │
 │ HealthKit (iOS)  │──▶│        source-labelled)      │
 │ Health Connect   │   │              │               │
 ├──────────────────┤   │              ▼               │
 │ BLE 0x180D strap │──▶│  Detection engine            │
 │ (later: direct)  │   │  (rules + state machine)     │
 ├──────────────────┤   │              │ event         │
 │ Gadgetbridge     │──▶│              ▼               │
 │ import (later)   │   │  Escalation engine ──────────┼──▶ Backend:
 ├──────────────────┤   │  (cancel window → cascade    │    Twilio kin cascade
 │ Demo trace       │──▶│   → dispatch → record)       │    Noonlight (sandbox)
 │ simulator        │   │              │               │    HAPI FHIR R4
 │ (LABELLED)       │   │              ▼               │    Consent/policy store
 └──────────────────┘   │  Role views (wearer / kin /  │
                        │  provider / nutritionist)    │
                        └─────────────────────────────┘
```

Every adapter emits the same internal event types onto one spine.
The detection engine cannot tell (and must not care) whether a heart
rate came from HealthKit, a strap, or the labelled simulator — but
the UI always can, and always says.

## 3. Aggregation layer (primary contract)

**HealthKit (iOS) + Health Connect (Android), via the Flutter
`health` package**, is the primary external data contract:

- Types read in v1: heart rate, blood oxygen (SpO2), steps, sleep
  sessions/stages where offered, resting heart rate where offered,
  and weight (smart scales that write to the health store).
- These stores already aggregate Apple Watch, Garmin, Fitbit,
  Samsung, Withings, Xiaomi (via their companion apps) and most
  bands whose owners sync to the phone. Reading one contract per OS
  replaces N vendor APIs. Scope of the claim, stated precisely:
  "any wearable" means any wearable **whose companion app syncs to
  the health store**. Bands that never touch the health stores are
  not covered by this layer; they arrive via the Gadgetbridge-class
  bridge import (Later, per PRODUCT-SPEC.md §4), behind the same
  ingestion contract.
- Known shape of the data (design for it, do not hide it): batch /
  sync-delivered, minutes-to-hours stale possible, sampling density
  varies wildly by source device. Every reading carries `source`,
  `recordedAt`, `ingestedAt`; freshness is computed and displayed.
- Permissions are per-type, OS-mediated, wearer-granted. Guardian
  requests the minimum set and degrades gracefully per type: denial
  of SpO2 disables the SpO2 guardrail and says so in the wearer view.

**Secondary routes (same contract, later phases):**

- **BLE standard profiles, direct:** Heart Rate Service 0x180D /
  measurement 0x2A37 (~1 Hz notify) from chest straps and devices
  that expose it; Battery and Device Information for housekeeping.
  This is the only genuinely *live* external vitals wire that needs
  no one's permission. Cheap wrist bands mostly do **not** expose it
  outside workout mode — the architecture treats BLE as a bonus
  live feed, never a promised one.
- **Gadgetbridge-class bridge:** import of fetched samples (HR,
  SpO2, steps, sleep incl. stages, supported-model temperature)
  from Xiaomi/Amazfit/no-name bands via Gadgetbridge's local data
  on Android. Samples, not streams; no raw accelerometer exists on
  this route, so no fall claims are ever sourced from a band.

**Explicitly not in the architecture:** Garmin Health API
(business-only program, sync-batch by design, license fees),
legacy Fitbit Web API (switched off Oct 30 / Nov 2, 2026), Zepp
cloud (no public API). Google Health API is a later connector if
its restricted-scope verification becomes worth it.

## 4. Phone sensor layer (the real-time layer)

The feasibility finding that shapes everything: **there is no live
wire from any wearable tier.** Every external feed is batch. The
phone is the only device present with live sensors, GPS, and a
voice line — so the real-time layer is the phone, by design, and
the product copy says so.

- **Fall detection (accelerometer).** On-device pipeline: free-fall
  / low-g phase → impact spike → post-impact immobility window →
  event candidate. Runs in the Android foreground service;
  on iOS, motion-coprocessor history queries + foreground sensing
  within Apple's background limits (protection level per OS is
  surfaced to the wearer, per the spec's honesty requirement).
  Phone-on-person is a stated precondition.
- **Inactivity / long-lie pattern.** After any motion anomaly, and
  continuously at a coarse level: no meaningful movement + no
  interaction + no response to a gentle prompt for a configured
  period (default 20 min) escalates as a *possible long lie*. This
  layer also covers the phone-left-on-the-table case at check-in
  times (below), more slowly and labelled as lower-confidence.
- **Missed check-ins.** Wearer sets (or accepts suggested) daily
  anchor check-ins ("I'm up", default morning). A missed check-in
  starts a soft prompt; an unanswered soft prompt becomes an event
  at the lowest escalation tier (kin digest flag first, cascade
  only per policy).
- **Camera PPG spot check.** Fingertip-over-camera photoplethysmography
  for an on-demand heart-rate spot check (30 s), for wearers with no
  HR source at all. Labelled in-app as a spot check with consumer
  accuracy; feeds the record, never the emergency trigger alone.
- **Vitals guardrails.** Heart-rate / SpO2 threshold rules evaluate
  the freshest health-store readings on each sync and on app wake.
  Thresholds are per-wearer (defaults + clinician/family-adjustable
  within wearer consent). A guardrail event is stamped with the
  reading's age; events on readings older than a configured
  freshness bound (default 30 min) are downgraded to digest items,
  never cascades. This rule is the architectural answer to
  batch-data honesty.

## 5. Escalation engine (deterministic state machine)

The engine is a pure, deterministic state machine. Its verified
reference implementation is the Node.js engine in `engine/`
(device-side behaviour is defined by it; the Dart port follows it
with test-parity, per §1, and the app exchanges episode logs with
the reference format as exported JSON). No ML, no probabilistic
triggers in v1: every transition is inspectable and testable, and
the same code path runs live and simulated feeds.

```
                 ┌──────────┐  candidate   ┌────────────┐
                 │ MONITOR  │─────────────▶│ CANDIDATE  │
                 └──────────┘              └─────┬──────┘
                      ▲                          │ confirm rules
                      │ false-alarm              ▼
                      │ learning (log)     ┌────────────┐
                      │                    │ ALERTING   │◀── cancel
                      │                    │ (cancel    │    window
                      │                    │  window,   │    expires
                      │                    │  60s def.) │
                      │                    └─────┬──────┘
                      │            wearer taps "I'm OK"
                      ├──────────────────────────┘
                      │                          │ no cancel
                      │                          ▼
                      │                    ┌────────────┐  kin ack
                      │                    │ CASCADING  │──────────┐
                      │                    │ Twilio SMS │          │
                      │                    │ + voice,   │          ▼
                      │                    │ ordered    │   ┌────────────┐
                      │                    │ contacts   │   │ KIN_HANDLED│
                      │                    └─────┬──────┘   └─────┬──────┘
                      │        cascade pass      │               │
                      │        exhausts, no ack  ▼               │
                      │                    ┌────────────┐        │
                      │                    │ DISPATCHED │        │
                      │                    │ Noonlight  │        │
                      │                    │ (sandbox   │        │
                      │                    │  in demo)  │        │
                      │                    └─────┬──────┘        │
                      │                          ▼               ▼
                      │                    ┌────────────────────────┐
                      └────────────────────│ RECORDED (FHIR write + │
                           event resolved  │ role-view updates)     │
                                           └────────────────────────┘
```

State-name mapping to the reference engine (one machine, two
altitudes): MONITOR/CANDIDATE are the pre-trigger detection layer;
ALERTING = the engine's CANCEL_WINDOW; CASCADING = CASCADE;
DISPATCHED = DISPATCH → RESOLVED; KIN_HANDLED and a wearer cancel
are RESOLVED endings (cancel returns the engine to IDLE, logged as
cancelled); RECORDED is the post-episode FHIR write, outside the
engine's states.

Transition rules (v1 defaults, all wearer-configurable):

- **CANDIDATE → ALERTING:** fall signature complete, OR vitals
  guardrail breach on a fresh reading, OR inactivity timer fired,
  OR check-in fully missed (policy-dependent entry point).
- **ALERTING:** local alarm (sound + vibration + full-screen),
  60 s default. "I'm OK" → RECORDED as `cancelled_by_wearer`.
  A second button, "I need help," skips straight to CASCADING.
- **CASCADING:** the escalation executor (the reference engine
  above) makes ONE ordered pass down the
  wearer's kin list: SMS + voice call per contact, live location
  link included, per-contact acknowledgment timeout (default
  120 s). Any contact's ack (reply keyword / link tap / in-app) →
  KIN_HANDLED, cascade stops, all other contacts notified that
  help is aware. The list does not repeat.
- **CASCADING → DISPATCHED:** the single cascade pass exhausts
  with no acknowledgment → the executor fires the dispatch alarm
  (Noonlight sandbox in the demo build; production adapter behind
  the same interface, enabled only under a monitoring agreement).
  Location + event summary + callback number included. There is
  no separate dispatch window: dispatch is a direct consequence
  of cascade exhaustion.
- **Any terminal state → RECORDED:** the full event timeline
  (signal snapshots, timestamps, who was contacted, who acked,
  dispatch alarm ID if any) is written as FHIR (see §7) and
  reflected into role views at granted granularity.
- **Failure honesty:** if the backend is unreachable, the app says
  so on the event screen and falls back to on-device direct SMS via
  the phone's own line where the OS permits; a cascade that could
  not be delivered is recorded as undelivered, never as sent.

The state machine's transition table is a single declarative file,
loaded by the app and the test suite alike: tests replay recorded
and synthetic traces through the *actual* table.

## 6. Consent and routing policy layer

This layer is the product's surviving commercial wedge and its
ethical spine; it is built as a first-class module, not settings
sprinkled through the UI.

- **Grant model:** per-recipient, per-data-class grants, owned by
  the wearer: `alerts` (event + location, at event time only),
  `digest` (daily summary), `record` (FHIR-backed history/trends),
  `live_view` (kin full view incl. recent vitals). Defaults: kin get
  `alerts` + `digest`; provider gets `record`; nutritionist gets a
  scoped `record` (activity/weight/appetite-proxy classes only).
  Everything else is opt-in by the wearer (or a wearer-designated
  delegate, post-v1).
- **Routing policy:** escalation order, per-contact channels
  (SMS/voice/app), cancel-window duration and the per-contact
  acknowledgment timeout,
  quiet hours for digests (never for cascades), and per-event-type
  routing (e.g., missed check-in → digest flag only; fall →
  full cascade). Policy is versioned; the version in force is
  stamped onto every event record, so "why did it call my son
  first?" always has a readable answer.
- **Revocation & audit:** revoking a grant takes effect on the next
  event and hides historical shared views prospectively; every
  grant change and every data access by a role view is written to
  an on-device audit log the wearer can read. What was shared
  during an emergency that has already happened cannot be unshared,
  and the copy says exactly that.
- **Data classes, not vibes:** location is shared only inside an
  active event (and 30 min after), never as a continuous feed, in
  v1, for any role. Raw accelerometer data never leaves the phone.
  Health-store readings leave the phone only into the wearer's
  FHIR record on the backend they (or the demo) point at.

## 7. Data model

Internal spine (app + backend, JSON):

```
Wearer        { id, displayName, locale, thresholds, policyId }
Device        { id, wearerId, kind: phone|store|ble|bridge|simulator,
                label, capabilities[], lastSeenAt }
Reading       { id, wearerId, type: hr|spo2|steps|sleep|temp|motion|weight,
                value, unit, recordedAt, ingestedAt, sourceDeviceId,
                freshnessSec (derived) }
Event         { id, wearerId, kind: fall|longlie|vitals|checkin|manual,
                state (state-machine), policyVersion, timeline[],
                signalSnapshot (readings + ages), createdAt, closedAt,
                outcome: cancelled|kin_handled|dispatched|undelivered }
Contact       { id, wearerId, role: kin|provider|nutritionist|delegate,
                name, channels[], escalationOrder }
Grant         { id, wearerId, contactId, dataClass, grantedAt,
                revokedAt? }
Dispatch      { id, eventId, provider: noonlight_sandbox|…,
                externalAlarmId, status, payloadSummary }
```

FHIR R4 mapping (the provider-facing truth; written via backend to
HAPI — local server in the demo, never real patient data on the
public test server):

- Wearer → `Patient`; phone/band → `Device`.
- Readings → `Observation` with LOINC codes (8867-4 heart rate;
  59408-5 / 2708-6 oxygen saturation; steps and sleep per standard
  profiles), `effectiveDateTime` = recordedAt, plus an extension
  carrying source + freshness so the record itself preserves the
  honesty labelling.
- Event → `Encounter` (class: emergency) + `Flag` while active;
  timeline steps → `Provenance` entries; Dispatch → a linked
  `Observation`/`Task` reference carrying the external alarm ID.
- Role views read through the grant layer, never directly from
  FHIR: the provider view is a FHIR query surface; kin and
  nutritionist views are projections built from Event + Reading
  under their grants.

## 8. Real vs simulated in the demo build (BlueKai precedent)

2025's winners shipped real artifacts beside labelled simulators
(BlueKai: real devices + a simulator, disclosed). Guardian follows
that rule exactly: **every simulated element is labelled on screen,
in the write-up, and in the data itself.** Nothing simulated wears a
"live" costume.

| Layer | Demo build: REAL | Demo build: SIMULATED (labelled) |
|---|---|---|
| Phone sensing | Accelerometer fall pipeline on a real phone; a real drop onto a cushion produces a real sensor trace and a real event | — |
| Health-store data | HealthKit / Health Connect reads on the demo phones, from whatever real sources are paired (builder's own watch/band if available) | If no wearable is on hand, a **Demo Trace Simulator** adapter replays recorded/public-dataset vitals traces, badged `SIMULATOR` in every view and in the FHIR extension |
| Fall from a band | — (no such data exists from cheap bands) | Never claimed. Band contributions are vitals/steps/sleep only |
| Detection + escalation engine | 100% real code, identical for live and simulated feeds; the state machine does not know which adapter fed it | Nothing |
| Kin cascade | Real Twilio SMS + voice calls to real demo phones, real acks | — |
| Dispatch | Real API call to **Noonlight sandbox**; real sandbox alarm ID returned and recorded | Production dispatch itself (no monitoring agreement exists; UI and docs say "sandbox") |
| Provider record | Real FHIR R4 resources POSTed to a **local HAPI server**, read back in the provider view | Hospital EHR delivery (SMART on FHIR registration-gated; not claimed) |
| Wearers | The builder / a consenting volunteer as demo wearer, named as such | No invented users, testimonials, or usage numbers anywhere |

## 9. Repository layout (target)

```
guardian-app/
  app/                 Flutter app (features: sensing, engine,
                       policy, views/{wearer,kin,provider,nutrition})
  app/platform/        Android foreground service, iOS motion glue
  backend/             Thin executor: twilio/, noonlight/, fhir/,
                       policy-store/ (keys server-side only)
  engine/              Node.js reference implementation of the
                       escalation state machine + transition table
                       (verified; the app integrates via exported
                       episode-log JSON, and the Dart port inside
                       app/ is held to test-parity against it)
  traces/              Labelled demo traces + trace format doc
  docs/                PRODUCT-SPEC.md, ARCHITECTURE.md, BUILD-PLAN.md
  .kiro/               Specs, steering, hooks (if entered in Kiroween)
```

Open-source notes: MIT license, as shipped in the repo's LICENSE
file, no analytics SDKs, no third-party trackers, secrets only via
environment/backend, and the safety-critical engine kept free of
non-deterministic dependencies so its behaviour is reproducible
from the repo alone.
