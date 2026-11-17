# Session 3 Result: Dart proof runner + live rehearsal wired to the Dart engine

## Baseline (confirmed before any change)

- `flutter test`: 36/36. Node engine suite (`cd engine && npm test`): 21/21.
  `flutter analyze`: no issues. HEAD was the Session 2 commit `44c3a91`.
- The tree was not strictly clean: one untracked file, `SESSION-3-PROMPT-1.txt`
  (this session's prompt). Sessions 1 and 2 committed their prompt files, so it
  is committed here too.

## What was built

Part 1, Dart proof runner
- `tool/run_proof.dart` (run: `dart run tool/run_proof.dart`). Replays both
  episodes through `lib/engine`, prints each timeline, runs `verify()` and
  `verify(anchor)`, and writes `proofs/episode-log.dart.json` in the same shape
  as `proofs/episode-log.json` (which it never touches). `dart:io` is used there
  only to write that file.
- `lib/rehearsal/proof_episodes.dart`: the two episodes with the same inputs as
  `integration/run-proof.js` (3 synthetic kin, default 60 s / 120 s windows,
  `FakeScheduler`, same cancel at t+20 s, same advances). Shared by the runner
  and the app, so the app runs the same code the runner proves.
- `lib/adapters/trace_simulator.dart`: Dart port of the Node
  TraceSimulatorAdapter. Labels are fixed by the `Signal` type
  (`source=simulator`, `freshness=simulated`); they are not constructor args.
- `lib/rehearsal/payload_logging_dispatcher.dart`: Dart port of the Node
  wrapper. Disabled, no token, no transport; logs `sandbox_payload_built`
  before the engine logs `dispatch_pending`.
- Every record carries source=simulator / freshness=simulated, as in the Node
  proof (checked by a test over signals, notifier locations, trigger evidence,
  payload labels, run labels).

Part 2, shell wiring
- Home screen: new "Live rehearsal (Dart engine, simulated)" button. The
  "Recorded proof run (simulated)" button is kept. The two now sit side by side
  in one row; stacking them made the big buttons shorter than the existing
  120 px test floor.
- `LiveTimelineScreen` (in `timeline_screen.dart`): runs both episodes on the
  Dart engine in-process (simulator, MockNotifier, disabled dispatcher,
  FakeScheduler fast-forward; windows are the defaults, unshortened, on a
  simulated clock). The banner states real elapsed time. It then renders that
  log with the same row renderer as the recorded view, so the label rules,
  UNLABELLED red state, DISABLED / NOT SENT dispatch wording and the
  "dispatched" suppression are the same code path, now test-enforced on the
  live view too.
- In-app chain verification: each live run is checked with the Dart
  `EventLog.verify()` and `verify(anchor)` at render time. The timeline shows
  "chain verified: N entries, head …" or "CHAIN VERIFICATION FAILED at entry #k"
  (red). The recorded view still says it does not re-verify (unchanged).
- The recorded Node proof view is unchanged and still labelled as a recorded
  replay of a file.

## One change inside lib/engine (disclosed)

`lib/engine/notifier.dart`: `ConsoleNotifier` used Flutter's `debugPrint`,
which pulled `dart:ui` into the engine and made `dart run` impossible. It now
uses `print` (with an `ignore: avoid_print`). Behaviour is the same (console
output). `lib/engine/guardian_engine.dart`: header comment updated (the "not
wired into the shell" line was no longer true). The Node `engine/` directory
is untouched (`git diff` on it is empty).

## Test counts

| | flutter test | Node engine suite | flutter analyze |
|---|---|---|---|
| Before | 36 | 21/21 | clean |
| After | 49 (36 + 13 new) | 21/21 | clean |

New: `test/dart_proof_parity_test.dart` (5), `test/live_rehearsal_test.dart` (8).

## Structural cross-check: PASSED

Compared Dart replay vs `proofs/episode-log.json`, twice: the in-process replay
and the committed artifact `proofs/episode-log.dart.json`. Equal on: episode
list and order (cancelled, escalated), entry types in the same order (5 and 19
entries), every transition's from/to/reason/resolution/dispatchStatus, final
states, verify results, anchor count, data labels, dispatchSent=false,
notifier calls (ids, messages, labelled locations), simulated signals, and the
full `data` of every entry (including the sandbox payload). Excluded by design:
`ts`, `observedAt`, `receivedAt`, `generatedAt`, hashes. Episode ids are
normalized (`ep-iN-M`).

Extra check, not a committed test: Node's own `engine/eventlog.js` loaded the
Dart artifact's entries and verified both chains, plain and anchored (both
`{"ok":true,"failedAt":null}`). Hash compatibility holds in the direction
Dart -> Node, on real output.

## Discrepancies between the Dart and Node replays

- None behavioural. Every compared field matched.
- Cosmetic: the Dart export writes whole-number doubles as `0.0` where Node
  writes `0` (e.g. accelerometer samples). The hashed form is the JS form, so
  hashes are unaffected and Node verifies the artifact.
- Expected, not a discrepancy: timestamps and hashes differ (different clock
  start), so they were not compared.

## Gate status

1. Tests green: yes (49/49; Node 21/21).
2. Log verifies: yes. Runner prints `{ok: true, failedAt: null}` for both
   chains, plain and anchored; the app shows "chain verified" for both live
   runs. Tampered (edited entry) and truncated logs are tested to fail in-app.
3. Live reproduction: the live rehearsal runs in the widget-test harness and
   the Dart runner was run from the CLI. It has NOT been run on a phone, an
   emulator or a built app in this session. The trigger is a simulated clock,
   not a real drop test, and is not claimed as one.
4. Labels audited: all 24 rows on the live timeline read
   `source: simulator · freshness: simulated` (test); no UNLABELLED; the
   missing-label path renders UNLABELLED (test).
5. Prohibitions grepped: no `dart:io`/`dart:html`/http/dio/socket imports in
   `lib/` (a test enforces it; the only `dart:io` is in `tool/run_proof.dart`,
   for the output file). No direct dialing (`tel:`, `911` only in the
   "never calls 911" strings). No credentials (the dispatcher reads its token
   from an env map only; none is supplied). Medical-claim language: only
   "not a medical device" and the `medical: true` service flag in the alarm
   payload shape, same as the Node reference.

## Still NOT done

- Real adapters: no real sensors, health store, BLE or Twilio/Noonlight
  transport. Everything in the live rehearsal is simulated.
- Alarm audio and voice prompt on the cancel screen (the cancel affordance is
  a big button only).
- Android build / APK, and any run on a device or emulator.
- Drop test on a real phone, PhoneSensorAdapter, foreground service, iOS
  limits screen.
- The live rehearsal runs both fixed scenarios; the wearer cannot cancel or
  kin acknowledge interactively in it.
- `RealScheduler` and `ConsoleNotifier` still have no tests.
- Credit usage was not measured this session.
