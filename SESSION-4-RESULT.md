# Session 4 Result: interactive live rehearsal + FHIR R4 export

## Baseline (confirmed before any change)

- `flutter test`: 49/49. `flutter analyze`: no issues. Node engine suite
  (`cd engine && npm test`): `21 passed, 0 failed, 21 total`.
- HEAD was the Session 3 commit `33d56ca`. The tree was not strictly clean: one
  untracked file, `SESSION-4-PROMPT-1.txt` (this session's prompt). Earlier
  sessions committed their prompt files, so it is committed here too.

## What was built

### Part 1: interactive live rehearsal

- `lib/rehearsal/scaled_scheduler.dart`: `ScaledScheduler`, a `Scheduler`
  decorator. A timer for N episode-ms fires after N/scale real ms on an inner
  scheduler; `now()` reports episode time. Default inner is `RealScheduler`;
  tests inject `FakeScheduler`. The engine is unchanged and still configured
  with the canonical 60 s cancel window and 120 s per-contact ack timeout
  (a test asserts `cancelWindowMs == 60000`, `cascadeAckTimeoutMs == 120000`
  under the scale). One ordered cascade pass; dispatch only on exhaustion.
- `lib/rehearsal/interactive_rehearsal.dart`: `InteractiveRehearsal`
  (`ChangeNotifier`) owns one real `EscalationEngine`, `TraceSimulatorAdapter`,
  `MockNotifier` and the disabled `PayloadLoggingDispatcher`.
  - "I'm OK" calls `engine.wearerCancel()`; the engine itself accepts it in the
    cancel window and in the cascade, and refuses it once the dispatcher is
    invoked. Nothing is re-implemented in the UI.
  - Simulated kin ack calls `engine.acknowledge()` for the contact the cascade
    is waiting on (found from the log's last `cascade_notify_pending`).
  - Outcome is derived from the log, not from UI state.
- `lib/screens/interactive_rehearsal_screen.dart`: the screen. Home has a new
  "Interactive rehearsal" button.
  - Start: "Simulate a fall (SIMULATED)". During the window and cascade: a
    180 px "I'M OK" button, a countdown in episode and real seconds, and (in
    the cascade only) an outlined control labelled "SIMULATED kin ack: kin-N
    acknowledges (simulation control, not a real person)".
  - Then the same timeline card as the other live views (each row labelled),
    outcome text, and chain verification (`Dart EventLog.verify()` and
    `verify(anchor)` once the episode ends; "verified so far" while running).
- `RunCard` (was private `_RunCard`) gained optional `outcome` and `timeNote`
  so interactive runs do not reuse the proof-run wording. `toProofRun` is now
  public. The acknowledgment row reads "Acknowledged by kin-N (SIMULATED kin
  acknowledgment; no real person was contacted)".
- Home: the four destinations now share one compact row (Interactive
  rehearsal, Auto live rehearsal, Recorded proof run, Provider view). Adding
  the new buttons as extra rows shrank the big "I'm OK" / "I need help" buttons
  below the existing 120 px test floor, so the floor was kept and the layout
  changed instead (see "Failures" below).

### Rehearsal timing scale and how it is disclosed

- Scale: **1 real second = 10 episode seconds** (`defaultRehearsalScale`).
  Cancel window = 6 real seconds; each contact's ack timeout = 12 real
  seconds; full unacknowledged run (60 + 3 x 120 episode seconds) = **42 real
  seconds**.
- On screen, always visible above the controls (orange box, key
  `scale-disclosure`): "REHEARSAL TIME IS SCALED: 1 real second = 10 episode
  seconds. The engine still uses the canonical windows in episode time (60s
  cancel window, 120s per-contact acknowledgment timeout), so here they last 6
  and 12 real seconds. A full unacknowledged run takes about 42 real seconds.
  Timeline t+ offsets are episode seconds." The timeline card repeats "t+
  offsets are EPISODE seconds (scaled clock, 1 real second = 10 episode
  seconds)". The text is generated from the scale, so it cannot drift from it.
  Tests assert it.
- Real-clock evidence (scale 10, `RealScheduler`, run once from a temporary
  test that was deleted before commit; output kept below):

```
=== FULL UNACKNOWLEDGED: real 42071 ms, episode 420700 ms
  t+0s #0 Trigger: fall pattern (signal sig-sim-6)
  t+60s #3 Cancel window lapsed with no cancel
  t+60s #6 Mock notification handed to kin-1 (channel: mock). Nothing was really sent.
  t+180s #7 No acknowledgment from kin-1 after 120 s
  t+300s #10 No acknowledgment from kin-2 after 120 s
  t+420s #13 No acknowledgment from kin-3 after 120 s
  t+420s #14 DISPATCH step reached (CASCADE → DISPATCH, reason: cascade_exhausted). Dispatch is DISABLED in this build.
  t+420s #15 Sandbox alarm payload built and logged. NOT SENT (sent=false; ...)
  t+420s #17 Dispatch DISABLED: nothing sent (status: disabled, partner reference: none)
  t+420s #18 DISPATCH → RESOLVED. Dispatch DISABLED: nothing was sent (dispatcher status: disabled).
  state=RESOLVED outcome=dispatchStepDisabled dispatchCalls=1 verify={ok: true, failedAt: null} verifyAnchor={ok: true, failedAt: null}
=== CANCEL MID-CASCADE (kin-2 notified): real 18037 ms, episode 180380 ms
  t+180s #9 Mock notification handed to kin-2 (channel: mock). Nothing was really sent.
  t+180s #10 Wearer cancelled ("I'm OK") during CASCADE. Good outcome; escalation stopped.
  t+180s #11 State: CASCADE → IDLE (reason: wearer_cancelled)
  state=IDLE outcome=wearerCancelled dispatchCalls=0 verify={ok: true, failedAt: null} verifyAnchor={ok: true, failedAt: null}
=== CANCEL IN WINDOW (after ~2 real s): real 2007 ms, episode 20070 ms
  t+20s #3 Wearer cancelled ("I'm OK") during CANCEL_WINDOW. Good outcome; escalation stopped.
  t+20s #4 State: CANCEL_WINDOW → IDLE (reason: wearer_cancelled)
  state=IDLE outcome=wearerCancelled dispatchCalls=0 verify={ok: true, failedAt: null} verifyAnchor={ok: true, failedAt: null}
=== SIMULATED KIN ACK (kin-1): real 6083 ms, episode 60840 ms
  t+60s #7 Acknowledged by kin-1 (SIMULATED kin acknowledgment; no real person was contacted)
  t+60s #8 State: CASCADE → RESOLVED (resolution: acknowledged)
  state=RESOLVED outcome=acknowledged dispatchCalls=0 verify={ok: true, failedAt: null} verifyAnchor={ok: true, failedAt: null}
```

  (Rows trimmed here for length; every row printed was labelled
  `source: simulator · freshness: simulated`.)

### Part 2: FHIR R4 export (offline)

- `lib/fhir/fhir_export.dart`: `buildFhirBundle(...)` returns a Dart `Map`;
  `fhirBundleToJson` pretty-prints it. Pure data in, data out: no I/O, no
  transport. `ExportObservation.fromHealthStore` labels a mock-store reading
  `simulated`, a `healthkit`/`health_connect` reading `fetched` with its age in
  seconds, and refuses unknown sources. `live` is expressible only by passing
  an explicit `FhirLabel` (the health stores are batch/sync and are never
  labelled live). `FhirEpisodeLog.fromProofRun` (Node-recorded log; chain
  result is Node's, stated as "not re-verified by this export") and
  `fromEpisodeRun` (Dart engine run; chain verified at export).
- `lib/screens/provider_screen.dart`: Provider view with "Export FHIR
  (simulated)". It shows the recorded `escalated` proof episode, the simulated
  observations (each with source/freshness), then the Bundle JSON in a
  `SelectableText` under an orange banner: "SIMULATED FHIR R4 BUNDLE. Built
  offline in this app: nothing was posted to any server. It was not checked by
  a FHIR server or the official validator."
- `tool/export_fhir.dart` (`dart run tool/export_fhir.dart`): writes the same
  Bundle to `proofs/fhir-bundle.simulated.json`
  (bundle id `guardian-export-badd6b2ebbcc`; 1 Patient, 6 Observation,
  1 Provenance; 37,163 bytes). `dart:io` is used there only for the two file
  operations. To let this run under plain `dart`, `ProofLog.loadAsset` moved
  out of `lib/proof_log.dart` into `lib/proof_log_asset.dart`
  (`loadProofLogAsset`); behaviour is the same.

### FHIR resource map

| Resource | Content | Required R4 elements present | Coding / labels |
|---|---|---|---|
| Bundle | `type: collection`, `timestamp`, `entry[].fullUrl` = `urn:uuid:` (deterministic) | `type` | `meta.security` HTEST, `meta.tag` freshness, `meta.extension`: data-label + export-notice (Bundle has no top-level `extension` in R4) |
| Patient | id `guardian-synthetic-wearer`, `name[0] = {use: anonymous, text: "Synthetic demo wearer"}`, `active: true`. No identifier, birthDate, gender, address, telecom | none required | data-label (source "synthetic placeholder", freshness simulated), HTEST, SIMULATED narrative |
| Observation x6 | `status: final`, `category`, `code`, `subject` -> Patient, `effectiveDateTime` (UTC), `valueQuantity`, `device.display` | `status`, `code` | LOINC: heart_rate 8867-4; spo2 59408-5; resting_heart_rate 40443-4; steps 55423-8; sleep 93832-4; skin_temperature 61008-9. UCUM: `/min`, `%`, `{steps}`, `min`, `Cel`. Category `vital-signs` or `activity` (observation-category system). Per-resource data-label (source, freshness, `ageSeconds` when fetched), `meta.tag`, HTEST + SIMULATED narrative when simulated |
| Provenance x1 | `target` = Patient + 6 Observations; `recorded` = Bundle timestamp; `agent[0]` type `assembler` (provenance-participant-type), `who.display`; `entity` role `source` for the episode log (identifier = chain head hash) and for the health-store observations | `target`, `recorded`, `agent` (with `who`) | data-label = worst case of its inputs; `episode-summary` extension (run label, final state, log label, head hash, chainVerified + who verified, "DISABLED: NOT SENT", entry count); one `episode-log-entry` extension per log entry (seq, type, time, one-line summary, entry hash). No raw log payloads are exported |

How the labels survive:

- simulated: every resource and the Bundle carry freshness `simulated`, HTEST
  (v3-ActReason "test health data"), a `meta.tag` reading "SIMULATED: not a
  real reading", and a narrative starting "SIMULATED". The Bundle also carries
  the notice "SIMULATED DATA. Synthetic wearer ... not a medical device".
- fetched: the Observation keeps `freshness: fetched` and `ageSeconds`
  (tested: ages 60..360 s), with no HTEST.
- live: keeps `freshness: live`, no age, no HTEST (tested with an explicit
  label, because no live source is wired into the exporter yet).
- Derived resources never look fresher than their inputs. The Patient
  placeholder is always simulated, so in this build the Provenance and the
  Bundle are always `simulated`, even when every Observation is fetched or
  live (tested).
- A missing episode label, a `fetched` label without age, an unknown source, a
  unit that does not match the type, an unsupported type or a duplicate
  observation makes the export throw. The provider view shows "Export
  refused: ..." and no JSON.

### What validation was done, and what was not

Done (offline, `test/fhir_export_test.dart`, `test/provider_view_test.dart`):

- Fixtures written by hand from the R4 (4.0.1) definitions in
  `test/fixtures/fhir_r4/`: `r4_definitions.json` (element lists, required
  elements, required bindings, primitive regexes, extension rules),
  `r4_codings.json` (expected LOINC/UCUM/category per observation type),
  `valid_minimal.json` and `invalid_minimal.json`.
- `test/support/fhir_r4_check.dart` checks: unknown elements, required
  elements (Observation `status`/`code`, Provenance `target`/`recorded`/
  `agent.who`, Bundle `type`), required bindings (Observation.status,
  Bundle.type, Provenance.entity.role, Patient.name.use, Narrative.status),
  primitive formats (id, instant, dateTime, code), extension shape,
  narrative div, `urn:uuid` fullUrl uniqueness and that every `urn:uuid`
  reference resolves inside the Bundle. The checker is itself tested: 4 valid
  fixtures accepted, 12 invalid fixtures each rejected for the stated reason.
- The exporter's Bundle passes the checker, for simulated, fetched, live and
  mixed inputs, for the Node-recorded log and for a Dart-engine run, and the
  committed `proofs/fhir-bundle.simulated.json` passes it too.
- The LOINC codes/displays, the UCUM codes (including `{steps}`), the
  observation-category codes, `provenance-participant-type#assembler`,
  `provenance-entity-role#source` and `v3-ActReason#HTEST` were each looked up
  once during development against the public terminology server
  (`tx.fhir.org/r4`, `CodeSystem/$lookup`). That was a one-off developer
  lookup from the shell. No app code calls it, and no Guardian data was sent.

NOT done:

- The official HL7 FHIR validator was not run (it needs Java and package
  downloads). The checker above is a small structural subset, not a
  conformance claim. Slicing, invariants (`obs-*`, `prv-*`), profile checks
  and terminology binding validation are not covered.
- No server round trip: nothing was POSTed to HAPI or any server, nothing was
  read back. Phase 5's `FhirRecordWriter` and read-back stay unchecked.
- The `.invalid` extension and code-system URLs (`guardian.invalid`) are
  placeholders with no published StructureDefinitions, so a strict validator
  will report unknown extensions.
- No consent grants exist yet, so the "no grant, no share" rule cannot be
  enforced on the export. The export holds only the synthetic demo wearer, and
  the provider screen says consent is not implemented.

## Test counts

| | flutter test | Node engine suite | flutter analyze |
|---|---|---|---|
| Before | 49 | 21/21 | clean |
| After | 92 (49 + 43 new) | 21/21 (engine/ untouched) | clean |

New: `test/interactive_rehearsal_test.dart` (15), `test/fhir_export_test.dart`
(24), `test/provider_view_test.dart` (4).

Interactive widget tests (the four required cases):
- cancel inside the window (`wearer_cancelled` during CANCEL_WINDOW, transition
  to IDLE reason `wearer_cancelled`, no `cascade_`/`dispatch_`/`sandbox_`
  entries, no kin notified, nothing happens after all windows would lapse);
- cancel mid-cascade (during CASCADE after kin-2 was notified; kin-3 never
  contacted; no dispatch entries; timers stopped);
- simulated kin ack resolving the episode (`cascade_acknowledged` by kin-2,
  resolution `acknowledged`, cascade stops);
- full unacknowledged run reaching the disabled dispatch (one ms short is
  still CASCADE; at 42,000 real ms on the scaled clock: payload logged before
  `dispatch_pending` before `dispatch_result`, status `disabled`, reference
  null, `sent=false`, `dispatchCalls == 1`).
Each one also asserts: no on-screen text contains "dispatched", no UNLABELLED,
the honest-limits line is present, every timeline row reads `source:
simulator · freshness: simulated` (count equals the number of log entries), and
the chain line starts "chain verified". Further tests: tampering with the
interactive log makes the chain line FAIL, `ScaledScheduler` unit tests, two
real-timer tests (`RealScheduler` at scale 100: full run and cancel/ack), run
again, leaving mid-episode stops all timers, home entry points.

## Failures along the way (kept on the record)

1. `dart format lib` (run to tidy my new files) reformatted existing files,
   including `lib/engine/*`. I caught it from `git status` before any commit,
   reverted every file I had not meant to change with `git checkout`, and
   reapplied only my intended edits. Final diff of `engine/` and `lib/engine/`
   against HEAD is empty.
2. First full run: `shell_test` "home: two big buttons" failed (big button
   74.5 px, floor 120 px) after I added two rows of buttons. I did not lower the
   floor; I put the four destinations in one compact row instead.
3. My first exporter put the label `extension` on the Bundle root. R4 `Bundle`
   has no top-level `extension`; I found it while writing the element lists
   for the fixtures. The label and notice are now in `Bundle.meta.extension`.
4. First interactive-widget run: the countdown assertion saw a stale value
   (UI only refreshes from a 250 ms ticker in the app); fixed by adding
   `InteractiveRehearsal.refresh()` and calling it from the test helper. Also
   `FakeScheduler` needs the engine's futures in the real zone, so UI actions
   in those tests are invoked inside `tester.runAsync`.
5. `dart run tool/export_fhir.dart` initially failed to compile because
   `proof_log.dart` imported `flutter/services.dart`; fixed by the
   `proof_log_asset.dart` split above.

## Gate status

1. Tests green: yes. 92/92, `flutter analyze` clean, Node 21/21 re-run.
2. Log verifies: yes. The runs above print `{ok: true, failedAt: null}` for
   both `verify()` and `verify(anchor)` on all four interactive scenarios, and
   the app shows "chain verified ..." for them. A tampered interactive log
   shows "CHAIN VERIFICATION FAILED" (test).
3. Live reproduction: performed on the real Dart engine with the real clock at
   scale 10 (output above) and through the widget tests. It has NOT been run
   by a person tapping a built app on a phone or emulator in this session, and
   no drop test was done.
4. Labels audited: every timeline row in every interactive state is labelled
   (counted by test); the export labels were audited per resource (tests above).
   No unlabelled simulated value was found.
5. Prohibitions grepped (`lib/`, `tool/`): no `tel:`/dial/`url_launcher`; "911"
   appears only in the "never calls 911 directly" line; no credentials (the only
   "Twilio" hit is a comment in `lib/engine/notifier.dart`); "medical" appears
   only in "not a medical device" strings and the pre-existing
   `'medical': true` service flag in the sandbox alarm payload shape (unchanged
   since Session 2; it is a payload field, not a claim by the app). A test
   scans `lib/` for network/socket/`dart:io` imports and fails on any hit
   (verified once by planting `import 'dart:io';` in a temp file).

## Still NOT done

- Real health-store reads (Health Connect / HealthKit); the export only ever
  sees the mock store's simulated series, timestamped at read time and not
  tied to the recorded episode's time.
- Alarm audio and voice prompt on the cancel affordance (button and countdown
  only; the cancel screen from Session 1 and the new rehearsal screen have
  neither).
- Android build / APK; no run on a device or emulator; no real drop test.
- PhoneSensorAdapter, foreground service, iOS limits screen.
- Consent grants and revocation (Phase 5); kin and nutritionist views.
- FHIR: server round trip (HAPI), the official validator, published
  extension definitions, Device/Encounter/Flag resources.
- The original auto-run "Auto live rehearsal" view (both fixed scenarios on a
  fake clock) is kept unchanged.
- Credit usage was not measured this session.
