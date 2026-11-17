# Guardian: Session 2 Result

Scope: Phase 2 core task only. A Dart port of the escalation engine,
held to test parity against the Node reference suite. **The Flutter
shell is NOT rewired to the Dart engine.** It still renders the
recorded Node proof (`assets/episode-log.json`, identical to
`proofs/episode-log.json`, asserted by `test/shell_test.dart`). The
Node engine in `engine/` was not modified. Nothing in the other Phase 2
bullets (real sensors, foreground service, on-phone drop test, false
positive observation) was started.

No credentials, no network code, no direct emergency dialing. The
Dart dispatcher is disabled by default, has no transport implementation,
and `lib/engine/` imports neither `dart:io` nor any HTTP package.

## Layout

```
lib/engine/scheduler.dart    Scheduler, RealScheduler, FakeScheduler
lib/engine/event_log.dart    EventLog (SHA-256 / HMAC), anchor, verify, JS-compatible JSON encoder
lib/engine/notifier.dart     Notifier, ConsoleNotifier, MockNotifier, Contact, Location, Alert
lib/engine/dispatcher.dart   Dispatcher, Disabled/Mock/NoonlightSandbox dispatchers, dispatcherFromEnv
lib/engine/engine.dart       EscalationEngine, States
lib/engine/guardian_engine.dart  barrel export
lib/adapters/                health_store.dart, phone_sensors.dart (simulated mocks, see "Adapter scenarios")
test/engine_parity_test.dart 21 scenarios mirroring engine/test/run-tests.js
test/export_parity_test.dart 7 export-format checks against proofs/episode-log.json
```

ARCHITECTURE.md §9 targets `app/` for the Flutter app, but the Flutter
project actually lives at the repo root (Session 1 layout), so the port
is under `lib/engine/` as the task allowed. Only new dependency:
`crypto` (SHA-256/HMAC), added to `pubspec.yaml`/`pubspec.lock`.

## Timing model (unchanged)

Cancel window 60 s default, ONE ordered cascade pass, 120 s per-contact
acknowledgment timeout default, dispatch only when the pass exhausts
with no acknowledgment, no separate dispatch window, wearer cancel
accepted until `dispatcher.dispatch()` is invoked (then logged as
`wearer_cancel_rejected`, `beyond_recall`). Log-before-side-effect is
kept (`cascade_notify_pending`, `dispatch_pending`).

## Parity evidence

| Suite | Result |
|---|---|
| Node reference, `node test/run-tests.js` (in `engine/`) | **21 passed, 0 failed, 21 total** |
| Dart mirror, `flutter test test/engine_parity_test.dart` | **21 passed, 0 failed** (`+21: All tests passed!`) |
| Dart export cross-check, `flutter test test/export_parity_test.dart` | **7 passed** (`+7: All tests passed!`) |
| Whole Dart project, `flutter test` | 36 passed (21 + 7 + 8 existing shell tests) |
| `flutter analyze` | No issues found |

The 21 Dart tests have the same names, same order, same setups
(contacts, 30 s / 60 s windows, `FakeScheduler(1000000)`), and the same
expectations as the Node tests.

### Adapter scenarios (FIX9, FIX11): honest note

Two of the Node suite's 21 scenarios test the mock adapters
(`adapters/phone-sensors.js`, `adapters/health-store.js`), not the
engine. To mirror all 21, minimal Dart ports of those two simulated mocks
were added under `lib/adapters/`. They are mocks only (`source` is
`simulated` on every row), carry no real sensor or health-store access,
and are not the Phase 2/3 adapters. `MockPhoneSensorsAdapter` omits
`currentLocation()` because no Node scenario exercises it. These two
tests check the mocks' own contract; they are not engine evidence.
The engine-only count is 19 of 21.

## Export-format cross-check (task item 4)

`test/export_parity_test.dart` replays both Session 1 proof scenarios
on the Dart engine with the Node runner's setup (three synthetic kin,
default 60 s / 120 s, cancelled run first then escalated so instance tags
`i1`/`i2` and episode IDs match; trigger evidence and location taken from
the Node export; a Dart port of the payload-logging dispatcher wrapper,
disabled, no token, no transport). Results:

- Dart `verify()` and `verify(anchor)` accept the Node-exported chains for
  both runs. The hash input is therefore byte-compatible.
- Event types and order are identical for the cancelled run (5 entries,
  final state `IDLE`) and the escalated run (19 entries, final state
  `RESOLVED`).
- Every entry (`seq`, `ts`, `type`, `data`, `prevHash`, `hash`) of both
  runs is equal to the Node export, including hashes. Escalated anchor
  equals Node's: count 19, headHash
  `299594c009236cbb4ce03ab4c12194b0ca25ab847dd09121e114f1e26170a82f`.
- `verify` = `{ok: true, failedAt: null}` and `verifyAnchored` identical.
- Entry key order is `seq, ts, type, data, prevHash, hash`, as in Node.
- The tests are sensitive: changing one logged field in the replay
  (`sent: false` to `true`) made the escalated entry-equality test fail;
  it was reverted.

Field differences, listed rather than hidden:

1. The engine's `EventLog` export is `{keyed, entries}` in both
   implementations. The per-run wrapper fields of `proofs/episode-log.json`
   (`label`, `finalState`, `verify`, `anchor`, `dataLabels`, `signals`,
   `notifierCalls`, `dispatchSent`, schema/banner/generatedAt) are built by
   `integration/run-proof.js`, not by the engine. The Dart test builds
   `label`, `finalState`, `keyedLog`, `verify`, `verifyAnchored`, `anchor`
   and `entries` and compares them. `signals` (from the Node
   `TraceSimulatorAdapter`, not ported) and `generatedAt`/`banner` are not
   produced by the Dart side. There is no Dart proof runner yet; the shell
   reads the Node file only.
2. `serialize()` pretty-prints with Dart's `JsonEncoder` (2-space indent).
   Content is equal after parsing; whitespace for empty or nested
   structures is not guaranteed byte-identical to Node's.
3. The timeline screen needs no change for entries: every field it reads
   is present with the same type and key.

## Other divergences from the Node code

- **Log key.** Node reads `GUARDIAN_LOG_KEY` from `process.env` implicitly.
  Dart takes an explicit `key` (`EventLog(now, key)`, `EscalationEngine(logKey:)`)
  and reads no process environment, keeping the library web-compatible.
  Keyed-mode HMAC semantics are tested (FIX8).
- **`dispatcherFromEnv`** takes the env map as a required argument for the
  same reason. Same gate: `GUARDIAN_DISPATCH_ENABLED == '1'` and a token,
  otherwise `DisabledDispatcher`. The injected transport is typed
  (`DispatchTransport`); none is implemented.
- **`engine_error.message`.** Node uses `err.message`. Dart strips a leading
  `Exception: ` from `toString()`, so the tested text matches
  (`dispatch boom`, `notify boom`), but messages of other error types may
  read differently from Node's.
- **`locationProvider`** is a function only (Node also accepts a plain
  object). `Location` carries optional `source`/`freshness` labels.
- **Typing.** Contacts, alerts, notifier/dispatcher results are classes
  rather than duck-typed objects, so Node's `result && result.delivered`
  null guards have no Dart counterpart; a notifier returning nothing is not
  expressible.
- **Hashing.** Node hashes `JSON.stringify(...)`. Dart uses a small
  `jsJsonEncode` that mimics it (integral doubles as integers, control-char
  escapes, null kept). Untested edge cases: lone UTF-16 surrogates and
  numbers beyond ±1e21 (not produced by the engine).
- `EventLog.append` copies the top-level `data` map (shallow); Node stores
  the caller's object. Not observable in the suite.

## Prohibitions grep (verification protocol, gate 5)

Searched `lib/engine/` and `lib/adapters/` for direct dialing (`tel:`,
`911`, `dial`), network code (`http`, `dart:io`), hardcoded credentials,
and medical-claim language (`diagnos`, `clinical`, `medical device`,
`treat`). Only hits: the word "dials" in a "Guardian NEVER dials emergency
numbers" comment and the `medical: true` service flag in the alarm
payload shape, which mirrors the Node reference. No hardcoded
credentials: the only token in the code is a fake test string
(`tok-secret-123`) in `test/`, copied from the Node suite.

## Gate status

1. Tests green: yes (above).
2. Log verifies: yes, both replayed runs, plain and anchored.
3. Live reproduction (drop test on a phone): **not done and not claimed.**
   This session ran the engine on a simulated clock only.
4. Labels audited: no new displayed values; the shell is unchanged. The
   adapter mocks label every row `simulated`.
5. Prohibitions grepped: yes (above).

## Honest gaps

- Shell not wired to the Dart engine (by instruction). No Dart proof
  runner exports `episode-log.json`; the replay lives in a test.
- Only `ConsoleNotifier`/`MockNotifier` exist; no Twilio code.
- No real sensors, foreground service, or iOS limits screen (rest of
  Phase 2 stays unchecked).
- The Dart scheduler's "drain" is a zero-delay timer, tested under
  `flutter test` on the VM only; behaviour on web and on device is
  untested.
- `RealScheduler` and `ConsoleNotifier` have no tests (the Node suite has
  none for them either).
- tasks.md: only the first Phase 2 bullet (the Dart port) is checked off.
- Credit usage was not measured this session.
