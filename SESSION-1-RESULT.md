# Guardian: Session 1 Result

Scope of this session: the escalation loop proven end to end against
mock adapters, inside a real repo, with the app shell standing around
it. Both endings (cancelled, escalated), an event log that verifies,
a Flutter shell that renders the exported log.

**No real Twilio or Noonlight account, credential, token, or network
call was used anywhere in this session.** No production or trial
account exists for either service. The Noonlight dispatcher was never
enabled (no token, no transport). The Notifier was the engine's
`MockNotifier`; nothing was sent to anyone. No code path in the repo
dials an emergency number.

## Credit record

Shared grant: 4,000 credits, funds BOTH Kiroween entries.

| Point | Kiroween bonus bucket (`kiroween-20-26`) |
|---|---|
| Session start | 0.00 of 4,000 used |
| Measured immediately before the close-out call | 26.64 of 4,000 used |
| Session stop | Not measured. This close-out call adds a small increment on top of 26.64. |

The 26.64 figure covers session work for BOTH Kiroween projects today,
not Guardian alone. There is no Guardian-only split and none is
invented here. Far below the ~1,000-credit guard.

## What was built and verified

### 1. Engine integrated, unmodified: 21/21

`engine/` (pre-existing, disclosed) was not edited. Baseline, run
before any other work and again at the end of each stage:

```
$ cd engine && npm test
...
21 passed, 0 failed, 21 total
```

### 2. Hook adapted

`.kiro/hooks/test-gate.json` was converted from its DRAFT shape to
Kiro's installed hook schema (`version: v1`, trigger `Stop`, a
`command` action running `npm test` in `engine/`).

Limit: the installed schema cannot block task completion on a failing
command. The draft's "block marking the task complete" intent is NOT
reproduced. The hook shows the test output at the end of each agent
run; it does not enforce the gate. The gate is enforced by this
document and by running the tests by hand.

### 3. TraceSimulatorAdapter (`adapters/trace-simulator.js`)

Emits `Signal` records in the design.md event-spine shape. The labels
`source: "simulator"` and `freshness: "simulated"` are applied in one
place and each emitted Signal is frozen. No timers, no I/O, no
randomness.

### 4. Payload-logging dispatcher wrapper (`integration/payload-logging-dispatcher.js`)

Wraps the engine's own `NoonlightSandboxDispatcher`, constructed with
`enabled: false`, no token, no transport. Why it exists: the engine
calls `buildAlarmPayload()` and then logs only `dispatch_pending` with
the episode id, so the payload itself never reached the log. The
wrapper appends a `sandbox_payload_built` entry (with `sent: false`)
through the public `EventLog.append()` BEFORE the engine logs
`dispatch_pending`. The chain stays valid, as the verify results below
show. The engine was not touched.

### 5. Proof runner (`integration/run-proof.js`)

`node integration/run-proof.js` runs both endings with 23 inline
checks, prints each timeline, calls `verify()` and `verify(anchor)`,
and exports `proofs/episode-log.json`. Exit 0 on all checks passing.

### 6. Flutter shell

| Check | Result |
|---|---|
| `flutter analyze` | `No issues found!` |
| `flutter build web` | `✓ Built build/web`, exit 0 |
| `flutter test` | 8 of 8 passed |

Screens: wearer home (huge "I'm OK" and "I need help", large type,
high contrast), cancel-window screen (60 s countdown, one huge
"I'm OK" button, no confirmation dialog, still operable after the
countdown ends), episode timeline (renders the bundled export, titled
and bannered as a recorded proof run, SIMULATED). The honest-limits
line `Demo build — dispatch is a sandbox; Guardian never calls 911
directly.` is on every screen; the home screen also carries the
not-a-medical-device and phone-on-person / platform-asymmetry lines.

## Proof output: both endings

Source: the CURRENT `proofs/episode-log.json` (`generatedAt`
`2026-11-17T14:30:19.380Z`). The proof was re-run during stage 3 and once more, by
mistake, during close-out (an extra `node integration/run-proof.js`
issued while checking the check count), so these hashes differ from
the stage-2 and stage-3 runs. Entry counts (5 and 19) did not change. The Flutter asset
was re-copied afterwards and is identical to this file (a test checks
it). Timelines are printed from that file; offsets are seconds on the
simulated clock.

### (a) CANCELLED: 5 entries, final state IDLE

```
# 0  t+  0s  trigger_received         fall_pattern; signal sig-sim-6 source=simulator freshness=simulated  [e98cebb93e]
# 1  t+  0s  transition               IDLE -> TRIGGERED  [c9bd1259c5]
# 2  t+  0s  transition               TRIGGERED -> CANCEL_WINDOW  [172ed87140]
# 3  t+ 20s  wearer_cancelled         during CANCEL_WINDOW  [e060b5b980]
# 4  t+ 20s  transition               CANCEL_WINDOW -> IDLE (reason=wearer_cancelled)  [5d6b6fb1d2]
```

```
verify()        => {"ok":true,"failedAt":null}
verify(anchor)  => {"ok":true,"failedAt":null}
anchor          => {"count":5,"headHash":"5d6b6fb1d28f1db265f9fea49f933486dbfaaa2c1ab725a8e65aaac5d6662f3b"}
```

After the cancel the clock was advanced past every window: engine
stayed IDLE, zero kin notified, no payload built, no dispatch call.

### (b) ESCALATED: 19 entries, final state RESOLVED

```
# 0  t+  0s  trigger_received         fall_pattern; signal sig-sim-6 source=simulator freshness=simulated  [9c8ddd6fb3]
# 1  t+  0s  transition               IDLE -> TRIGGERED  [f139f8936e]
# 2  t+  0s  transition               TRIGGERED -> CANCEL_WINDOW  [ea6e0b7cb9]
# 3  t+ 60s  cancel_window_lapsed     {"episodeId":"ep-i2-1"}  [d8a5f70496]
# 4  t+ 60s  transition               CANCEL_WINDOW -> CASCADE  [31d45880ed]
# 5  t+ 60s  cascade_notify_pending   kin-1  [3d49816468]
# 6  t+ 60s  cascade_notified         kin-1 mock  [e83f067ac9]
# 7  t+180s  cascade_no_response      kin-1 after 120s  [debd2e67b8]
# 8  t+180s  cascade_notify_pending   kin-2  [d8f2f45f94]
# 9  t+180s  cascade_notified         kin-2 mock  [37afdd925d]
#10  t+300s  cascade_no_response      kin-2 after 120s  [5130176168]
#11  t+300s  cascade_notify_pending   kin-3  [38b98979ec]
#12  t+300s  cascade_notified         kin-3 mock  [576bed945e]
#13  t+420s  cascade_no_response      kin-3 after 120s  [20efbf0aca]
#14  t+420s  transition               CASCADE -> DISPATCH (reason=cascade_exhausted)  [7821316e1a]
#15  t+420s  sandbox_payload_built    sent=false; endpoint https://api-sandbox.noonlight.com/dispatch/v1/alarms; labels {"source":"simulator","freshness":"simulated"}  [84f7d6aa03]
#16  t+420s  dispatch_pending         {"episodeId":"ep-i2-1"}  [dc040d2029]
#17  t+420s  dispatch_result          status=disabled reference=null  [f00ffc5f4b]
#18  t+420s  transition               DISPATCH -> RESOLVED (resolution=dispatched)  [299594c009]
```

```
verify()        => {"ok":true,"failedAt":null}
verify(anchor)  => {"ok":true,"failedAt":null}
anchor          => {"count":19,"headHash":"299594c009236cbb4ce03ab4c12194b0ca25ab847dd09121e114f1e26170a82f"}
```

Both chains were also loaded from the exported file into a fresh
`EventLog` and re-verified: `{"ok":true,"failedAt":null}` for each.
Kin were notified once each, in the wearer's order (kin-1, kin-2,
kin-3), each with the engine's default 120 s timeout. `sent=false` and
`status=disabled reference=null`: nothing was sent and there is no
partner reference ID because no alarm was created anywhere.

Labels audit: every signal in both runs is `source=simulator`,
`freshness=simulated`. The timeline screen shows that label on all 24
rows (a test asserts 24); an entry with missing labels would render as
UNLABELLED in red.

## Disclosures

1. **Steering timing correction.** `escalation-etiquette.md` still
   carried a superseded 3-minute separate dispatch window, which
   contradicted requirements.md, design.md, and the engine. John
   confirmed the canonical model (settled Nov 13, 2026: cancel
   window, then ONE ordered cascade pass with a per-contact
   acknowledgment timeout of 120 s default, then dispatch only on
   exhaustion with no acknowledgment; no separate dispatch window)
   and corrected the file in both the repo copy and the pack copy.
   Both copies were confirmed identical at close-out.
2. **Payload-logging wrapper.** See "What was built" item 4. The
   engine's payload builder also drops unknown fields, so the
   simulated labels are recorded beside the payload in the log
   entry, not inside the payload.
3. **Misleading engine wording.** The engine records
   `resolution: dispatched` even when the dispatcher answered
   `disabled`. The engine was not changed. The shell never prints
   that word as an outcome: the dispatch rows read "Dispatch is
   DISABLED", "NOT SENT", and "Dispatch DISABLED: nothing sent". A
   test fails if "resolution: dispatched" or "Dispatched" appears.
   The raw engine log in the export still contains the engine's
   wording, unaltered.
4. **FakeScheduler.** The runner uses the engine's `FakeScheduler`.
   The full-length 60 s cancel window and 120 s per-contact timeouts
   ran unshortened on a simulated clock, in milliseconds of wall
   time. No window was shortened. A real-time run (about 7 minutes)
   is not built.
5. **Label vocabulary difference.** The older mock adapters in
   `adapters/` label data `source: "simulated"` with no `freshness`
   field. The new trace adapter uses `source: "simulator"` plus
   `freshness: "simulated"`, per the design.md Signal shape. The
   older adapters were not changed. The vocabularies should be
   reconciled before any of them feed the shell.
6. **Duplicated asset.** `assets/episode-log.json` is a copy of
   `proofs/episode-log.json`. `proofs/` stays the canonical export
   location. Re-running the proof runner regenerates `proofs/` with
   new timestamps and hashes and leaves the asset stale: this
   happened once during stage 3 (`cmp` showed them differing) and the
   asset was re-copied. `test/shell_test.dart` fails whenever the two
   differ.
7. **No Dart engine yet.** The cancel-window screen is a visual
   rehearsal with no engine behind it, and says so on screen. "I'm
   OK" on the home screen records nothing, and says so. The Dart
   port with test parity is Phase 2.
8. **No alarm audio.** escalation-etiquette.md requires a loud alarm
   and a voice prompt on the cancel affordance. Neither is
   implemented. Gap, not a stub.
9. **Log chain not re-verified in the app.** The timeline shows the
   result the Node engine recorded at export and states that the app
   does not re-verify. Re-verifying in Dart is possible later.
10. **Android and iOS builds not attempted.** No Android SDK on this
    machine (instructed not to install it), and iOS cannot build on
    Linux. The only compile proof is `flutter analyze` plus
    `flutter build web`.
11. **Template package IDs unchanged.** `flutter create` defaults
    stand (`org.guardian.guardian_app`). Only the web description text
    was edited.
12. **Hook cannot block.** See "Hook adapted" above.
13. **Layout check.** One test failed on its first run: the home
    buttons measured 103 px tall on flutter_test's default 800x600
    landscape surface, against a 120 px floor. The test was moved to
    a phone-shaped 411x891 portrait surface. The threshold was not
    lowered. On short or landscape screens the buttons will be
    smaller; check on real devices.
14. **Gate status for Phase 1.** Tests green: yes (engine 21/21,
    Flutter 8/8). Log verifies: yes, both runs. Labels audited: yes
    for the shell and export. Prohibitions grepped: yes (below).
    Live reproduction: only on the simulated clock with mock
    adapters. The real flow (a physical drop, real windows, real
    channels, FHIR read-back) is Phase 2 and later work, so this
    session claims the engine-integration and shell portion of the
    gate only.
15. **Pack drift.** `kiro-pack/.kiro/hooks/test-gate.json` was
    overwritten with the adapted hook. `kiro-pack/.kiro/specs/guardian/tasks.md`
    still shows the older unchecked state; it was not touched.

## Prohibitions grep (verification gate step 5)

Searched `engine/`, `adapters/`, `integration/`, `lib/` for emergency
dialing, `tel:`, credentials, token/secret/key strings, network
modules, and medical-claim language.

- Emergency dialing: no code path. The only hits are the honest-limits
  string in `lib/widgets/honest_limits.dart` and prohibition comments
  in `engine/dispatcher.js` and `engine/engine.js`.
- Credentials: none hardcoded. Hits are variable and env-var names in
  the pre-existing `engine/dispatcher.js` (`GUARDIAN_NOONLIGHT_TOKEN`,
  read from the environment only, not set in this session) and
  comments saying "no token".
- Network: no `http`, `https`, `net`, `fetch`, `HttpClient`, or
  `dart:io` use in `lib/`, `adapters/`, or `integration/`.
- Medical claims: the only hits are the line "not a medical device"
  and its constant name.
- No match for Twilio code beyond a pre-existing comment in
  `engine/notifier.js`.

## Gaps and open items (no silent stubs)

- Dart engine port with Node test parity (Phase 2).
- Alarm audio and voice prompt on the cancel screen.
- Real-time (non-simulated-clock) proof run.
- In-app log verification.
- Android and iOS builds; install on a real device.
- Sensors, health stores, BLE, bridge import: not started (Phases 2 and 3).
- Twilio and Noonlight sandbox wiring: not started, by design (Phase 4,
  separately reviewed).
- FHIR record and the kin, provider, and nutritionist role views: not
  started (Phase 5). Consent grants are not implemented in the shell.
- Hook cannot enforce the gate (see above).
- Label vocabulary reconciliation between old and new adapters.
- Public GitHub repo: not created. Open as John's decision.
