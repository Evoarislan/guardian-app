# Guardian: Design

## The body and its parts
Guardian is designed as one body (the escalation loop and the
wearer's record) animated by parts that were never built for each
other. The design's job is to make the seams explicit, labelled, and
safe — the Frankenstein stitch is visible in the architecture, not
hidden under it.

| Part (foreign body) | Native world | Guardian adapter |
|---|---|---|
| HealthKit | iOS, Apple permission model | HealthStoreAdapter (iOS) |
| Health Connect | Android, Google permission model | HealthStoreAdapter (Android) |
| BLE Heart Rate Profile 0x180D/0x2A37 | Bluetooth SIG standard | BleHeartRateAdapter |
| Gadgetbridge-class band bridges | Reverse-engineered BLE, Android | BridgeImportAdapter |
| Phone accelerometer / GPS / camera | OS sensor APIs, platform-asymmetric | PhoneSensorAdapter |
| Recorded trace replays | Demo data | TraceSimulatorAdapter (LABELLED) |
| Twilio SMS/voice | Telecom APIs | Notifier (cascade channel) |
| Noonlight Dispatch API | Monitored central station, US | Dispatcher (sandbox first) |
| FHIR R4 / HAPI | Clinical interoperability | FhirRecordWriter/Reader |

## Event spine
Every adapter emits the same normalized event shape, FHIR-shaped
from birth:

    Signal { id, wearerId, kind: hr|spo2|steps|sleep|accel|checkin|location,
             value, unit, source: adapterId, freshness: live|fetched|simulated,
             observedAt, receivedAt }
    Episode { id, trigger, state, timeline: [eventLogRefs], outcome }

A reading's `freshness` and `source` are never stripped. The UI, the
detection engine, and the FHIR writer all carry them through. This
is what makes the honesty steering enforceable in code rather than
in intentions.

## Escalation engine
The engine is a deterministic state machine, and it already
exists: engine/ (pre-existing, disclosed) is the COMPLETE, tested
implementation — engine.js (the state machine), eventlog.js
(hash-chained EventLog), scheduler.js (injected timing),
notifier.js (Notifier interface with console/mock
implementations), dispatcher.js (Dispatcher interface with a
Noonlight-sandbox payload builder, dispatch DISABLED by default).
Session work INTEGRATES and verifies it; it does not rebuild it.

    IDLE --trigger--> TRIGGERED (recorded) --immediately-->
    CANCEL_WINDOW (cancel window running, default 60s)
    CANCEL_WINDOW --wearer cancels--> IDLE [cancellation logged]
    CANCEL_WINDOW --window lapses--> CASCADE (one ordered pass,
      wearer order; per-contact ack timeout, default 120s)
    CASCADE --any kin ack--> RESOLVED [log, record]
    CASCADE --exhausted, no ack--> DISPATCH
    DISPATCH --dispatcher reference returned--> RESOLVED

Timing model: cancel window (default 60s) → one ordered cascade
pass with a per-contact acknowledgment timeout (default 120s) →
dispatch on cascade exhaustion. There is NO separate dispatch
window.

Invariants (also in steering/escalation-etiquette.md):
- The cancel window is always honoured, including a cancel that
  arrives late-but-before-dispatch; a cancel is never overridden.
- Cascade order and windows come from the wearer's policy, never
  hardcoded.
- Every transition is appended to the hash-chained event log
  BEFORE its side effect fires, so the log can prove the order of
  events in any demo or dispute.
- Dispatch is an interface seat. Demo build: Noonlight sandbox
  payload, sent only to the sandbox endpoint, only with a sandbox
  token from the environment, never a production credential.

## App shell
Stack: **Flutter**, CONFIRMED by docs/ARCHITECTURE.md §1 (single
codebase for Android + iOS; the `health` package wraps both
HealthKit and Health Connect behind one API — the
HealthStoreAdapter contract; foreground-service support on
Android). Stack reconciliation done Nov 13, 2026.

Layers:
- app/ (Flutter): four role views, cancel-window screen (one huge
  button, loud alarm, voice prompt), settings/consent screens.
- sensing/: PhoneSensorAdapter (accelerometer fall signature,
  inactivity windows, check-in scheduler), camera PPG spot check.
- adapters/: HealthStoreAdapter (both OS contracts), BleHeartRate,
  BridgeImport, TraceSimulator (demo only, labelled).
- engine/: the complete, tested escalation engine (pre-existing,
  disclosed) — state machine, hash-chained event log, scheduler,
  notifier/dispatcher interfaces. Interfaces are shaped so
  cascade/dispatch calls leave the device only through them. See
  the reconciliation section below for how it meets the Flutter
  app.
- record/: FHIR mapping (LOINC-coded Observations: 8867-4 heart
  rate, 59408-5/2708-6 SpO2; Patient; Device; Encounter/Flag per
  episode) and HAPI client (local HAPI preferred; public test
  server only with the synthetic demo wearer).

## Engine reconciliation (Node reference ↔ Flutter app)
The Node engine in engine/ is the VERIFIED REFERENCE
IMPLEMENTATION: its test suite defines correct escalation
behaviour. Integration happens through an artifact, not a
rewrite: the Session 1 proof runner drives the Node engine and
exports each proof episode's hash-chained event log to
proofs/episode-log.json; the Flutter shell renders THAT file
(the log bridge). A Dart port of the engine, held to test-parity
with the Node suite case-for-case, is Phase 2 work (tasks.md).
The adapters in adapters/ are likewise pre-existing contracts and
mocks: Phase 3 hardens them against real sources rather than
building them from scratch.

## Consent and routing policy
Policy is data, owned by the wearer: { roleGrants, cascadeOrder,
cancelWindowSec, cascadeAckTimeoutSec, checkinTimes }. Every share
checks the grant at send time, not at setup time. Revoking a grant
stops future shares immediately and is itself logged. Role views
render only what the current grants allow.

## Demo design (the flow the video and judges run)
One phone, held in the hand:
1. The phone is dropped onto a cushion: real accelerometer trigger.
2. Cancel window counts down on screen (nobody cancels).
3. Cascade fires to mock kin (Session 1) / Twilio trial numbers
   (later phases, real phones, real calls — reviewed separately).
4. The cascade pass ends with no acknowledgment: the Noonlight
   SANDBOX alarm fires, sandbox alarm ID returns and is shown.
5. The episode's FHIR record is read back from HAPI into the
   provider view; the event log verifies on screen.
Every screen labels its data live / fetched / simulated. The demo
never claims production dispatch, a medical capability, or a 911
call.

## Safety invariants in design
- No code path dials an emergency number. There is no dialer for
  911 anywhere in the design; dispatch is the monitored-partner
  interface or nothing.
- No credential lives in the repo. Tokens come from the
  environment at runtime; sandbox tokens only during the contest.
- The synthetic demo wearer is the only wearer whose data touches
  any shared/public service (HAPI public test server).
