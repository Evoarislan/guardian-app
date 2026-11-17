// Guardian Session 1 proof runner.
//
// Drives the EXISTING, unmodified engine (engine/) with mock adapters
// only, through both endings of the escalation loop, prints the
// evidence, verifies each event-log chain, and exports both episodes
// to proofs/episode-log.json (the log bridge the app shell renders).
//
//   node integration/run-proof.js
//
// What is real and what is not (printed again in the export):
//   - Engine, state machine, hash-chained log: the real engine code.
//   - Signals: SIMULATED (TraceSimulatorAdapter; source=simulator,
//     freshness=simulated).
//   - Kin notifications: the engine's MockNotifier. Nothing is sent.
//   - Dispatch: DISABLED. The Noonlight-sandbox payload is built and
//     logged, never sent. No credentials, no network calls.
//   - Time: the engine's FakeScheduler, so the DEFAULT windows
//     (cancel 60 s, per-contact ack 120 s) run unshortened on a
//     simulated clock. Wall-clock time for the run is milliseconds.

'use strict';

const fs = require('node:fs');
const path = require('node:path');

const {
  EscalationEngine,
  STATES,
  FakeScheduler,
  MockNotifier,
} = require('../engine');
const { TraceSimulatorAdapter, SOURCE, FRESHNESS } = require('../adapters/trace-simulator');
const { PayloadLoggingDispatcher } = require('./payload-logging-dispatcher');

const CANCEL_WINDOW_S = 60; // engine default, not shortened
const ACK_TIMEOUT_S = 120; // engine default, not shortened

// Synthetic kin, in the wearer's order. No phone numbers: nothing is
// ever sent, and no real person is represented.
const KIN = [
  { id: 'kin-1', name: 'Synthetic Kin 1 (first in wearer order)' },
  { id: 'kin-2', name: 'Synthetic Kin 2' },
  { id: 'kin-3', name: 'Synthetic Kin 3' },
];

const LABELS = { source: SOURCE, freshness: FRESHNESS };

let failures = 0;
function check(description, condition, detail) {
  if (condition) {
    console.log(`  CHECK ok    ${description}`);
  } else {
    failures += 1;
    console.log(`  CHECK FAIL  ${description}${detail ? ` -> ${detail}` : ''}`);
  }
}

function build() {
  const scheduler = new FakeScheduler(Date.now());
  const simulator = new TraceSimulatorAdapter({ now: () => scheduler.now() });
  const notifier = new MockNotifier();
  const dispatcher = new PayloadLoggingDispatcher({ labels: LABELS });
  const engine = new EscalationEngine({
    contacts: KIN,
    cancelWindowSeconds: CANCEL_WINDOW_S,
    cascadeAckTimeoutSeconds: ACK_TIMEOUT_S,
    notifier,
    dispatcher,
    scheduler,
    wearerName: 'Synthetic demo wearer',
    locationProvider: () => simulator.location(),
  });
  dispatcher.attachLog(engine.log);

  // Adapter -> engine wiring. The fall-pattern Signal, with its
  // simulated labels intact, becomes the trigger evidence in the log.
  simulator.onSignal((signal) => {
    if (signal.kind === 'accel' && signal.value && signal.value.type === 'fall_pattern') {
      engine.trigger('fall_pattern', { signal });
    }
  });
  return { scheduler, simulator, notifier, dispatcher, engine };
}

function summarize(entry) {
  const d = entry.data || {};
  switch (entry.type) {
    case 'transition':
      return `${d.from} -> ${d.to}` + (d.resolution ? ` (resolution=${d.resolution})` : '') +
        (d.reason ? ` (reason=${d.reason})` : '');
    case 'trigger_received':
      return `${d.triggerType}; signal ${d.details.signal.id} ` +
        `source=${d.details.signal.source} freshness=${d.details.signal.freshness}`;
    case 'wearer_cancelled':
      return `during ${d.duringState}`;
    case 'cascade_notify_pending':
    case 'cascade_notified':
    case 'cascade_no_response':
    case 'cascade_acknowledged':
      return d.contactId + (d.channel ? ` via ${d.channel}` : '') +
        (d.waitedMs ? ` after ${d.waitedMs / 1000}s` : '');
    case 'sandbox_payload_built':
      return `sent=${d.sent}; endpoint ${d.endpoint}; labels ${JSON.stringify(d.dataLabels)}`;
    case 'dispatch_pending':
      return 'dispatcher about to be invoked';
    case 'dispatch_result':
      return `status=${d.status} reference=${d.reference}`;
    default:
      return JSON.stringify(d);
  }
}

function printTimeline(log) {
  const t0 = log.entries[0].ts;
  for (const e of log.entries) {
    const offset = String(((e.ts - t0) / 1000).toFixed(0)).padStart(4);
    console.log(
      `  #${String(e.seq).padStart(2)}  t+${offset}s  ${e.type.padEnd(24)} ${summarize(e)}  [${e.hash.slice(0, 10)}]`
    );
  }
}

function verifyAndPrint(engine) {
  const anchor = engine.log.anchor();
  const plain = engine.log.verify();
  const anchored = engine.log.verify(anchor);
  console.log(`  verify()        => ${JSON.stringify(plain)}`);
  console.log(`  verify(anchor)  => ${JSON.stringify(anchored)}  anchor=${JSON.stringify(anchor)}`);
  check('event log verify() ok', plain.ok === true, JSON.stringify(plain));
  check('event log verify(anchor) ok', anchored.ok === true, JSON.stringify(anchored));
  return { plain, anchored, anchor };
}

function exportRun(label, ctx, verification) {
  const snapshot = ctx.engine.log.toJSON(); // verbatim from the engine's EventLog
  return {
    label,
    finalState: ctx.engine.state,
    keyedLog: snapshot.keyed,
    verify: verification.plain,
    verifyAnchored: verification.anchored,
    anchor: verification.anchor,
    dataLabels: LABELS,
    signals: ctx.simulator.emitted,
    notifierCalls: ctx.notifier.calls.map((c) => ({
      contactId: c.contact.id,
      message: c.alert.message,
      location: c.alert.location,
    })),
    dispatchSent: false,
    entries: snapshot.entries,
  };
}

// ---------------------------------------------------------------- (a)
async function runCancelled() {
  console.log('\n=== RUN (a): fall -> wearer cancels inside the cancel window ===');
  const ctx = build();
  const { engine, scheduler, simulator, notifier, dispatcher } = ctx;

  simulator.playFall();
  check('state is CANCEL_WINDOW after the fall trigger', engine.state === STATES.CANCEL_WINDOW, engine.state);

  await scheduler.advance(20 * 1000); // 20 s into the 60 s window
  check('still CANCEL_WINDOW at t+20s (no cascade yet)', engine.state === STATES.CANCEL_WINDOW, engine.state);

  const accepted = engine.wearerCancel();
  check('wearerCancel() accepted', accepted === true);
  check('engine returned to IDLE', engine.state === STATES.IDLE, engine.state);

  // Run the clock well past every window: nothing downstream may fire.
  await scheduler.advance((CANCEL_WINDOW_S + 3 * ACK_TIMEOUT_S + 60) * 1000);
  check('engine still IDLE after all windows would have lapsed', engine.state === STATES.IDLE, engine.state);
  check('no kin were notified', notifier.calls.length === 0, String(notifier.calls.length));
  check('no payload built, no dispatch call', dispatcher.built.length === 0 && dispatcher.dispatchCalls === 0);
  check(
    'cancellation is in the log',
    engine.log.entries.some((e) => e.type === 'wearer_cancelled'),
  );
  check(
    'no cascade or dispatch entries in the log',
    !engine.log.entries.some((e) => /^cascade_|^dispatch_|^sandbox_/.test(e.type)),
  );

  console.log('  timeline:');
  printTimeline(engine.log);
  const verification = verifyAndPrint(engine);
  return exportRun('cancelled', ctx, verification);
}

// ---------------------------------------------------------------- (b)
async function runEscalated() {
  console.log('\n=== RUN (b): fall -> window lapses -> one ordered cascade pass -> DISPATCH ===');
  const ctx = build();
  const { engine, scheduler, simulator, notifier, dispatcher } = ctx;

  simulator.playFall();
  check('state is CANCEL_WINDOW after the fall trigger', engine.state === STATES.CANCEL_WINDOW, engine.state);

  await scheduler.advance(CANCEL_WINDOW_S * 1000);
  check('window lapsed -> CASCADE', engine.state === STATES.CASCADE, engine.state);
  check('first kin notified (kin-1), and only kin-1 so far', notifier.calls.length === 1 && notifier.calls[0].contact.id === 'kin-1');

  for (let i = 0; i < KIN.length; i += 1) {
    await scheduler.advance(ACK_TIMEOUT_S * 1000);
  }
  check('cascade pass exhausted -> engine RESOLVED', engine.state === STATES.RESOLVED, engine.state);
  check(
    'kin notified exactly once each, in wearer order',
    JSON.stringify(notifier.calls.map((c) => c.contact.id)) === JSON.stringify(KIN.map((k) => k.id)),
    JSON.stringify(notifier.calls.map((c) => c.contact.id)),
  );
  const types = engine.log.entries.map((e) => e.type);
  const iBuilt = types.indexOf('sandbox_payload_built');
  const iPending = types.indexOf('dispatch_pending');
  const iResult = types.indexOf('dispatch_result');
  check(
    'sandbox payload logged BEFORE dispatch_pending, then dispatch_result',
    iBuilt >= 0 && iBuilt < iPending && iPending < iResult,
    `built=${iBuilt} pending=${iPending} result=${iResult}`,
  );
  const dispatchEntry = engine.log.entries.find((e) => e.type === 'transition' && e.data.to === STATES.DISPATCH);
  check('DISPATCH state entered with reason cascade_exhausted', !!dispatchEntry && dispatchEntry.data.reason === 'cascade_exhausted');
  const result = engine.log.entries[iResult];
  check('dispatch NOT sent: status=disabled, no reference', !!result && result.data.status === 'disabled' && result.data.reference === null, JSON.stringify(result && result.data));
  check('payload entry records sent=false', engine.log.entries[iBuilt].data.sent === false);
  check('no kin acknowledgment occurred', !types.includes('cascade_acknowledged'));

  console.log('  timeline:');
  printTimeline(engine.log);
  console.log('  built sandbox payload (never sent):');
  console.log(JSON.stringify(dispatcher.built[0], null, 2).replace(/^/gm, '    '));
  const verification = verifyAndPrint(engine);
  return exportRun('escalated', ctx, verification);
}

// ---------------------------------------------------------------- main
(async () => {
  console.log('Guardian Session 1 proof run');
  console.log('Engine: engine/ (pre-existing, unmodified). Signals: SIMULATED. Notifier: MockNotifier.');
  console.log('Dispatch: DISABLED; sandbox payload built + logged, never sent. No credentials, no network.');
  console.log(`Windows: cancel ${CANCEL_WINDOW_S}s, per-contact ack ${ACK_TIMEOUT_S}s (engine defaults, on a simulated clock).`);

  const cancelled = await runCancelled();
  const escalated = await runEscalated();

  const out = {
    schema: 'guardian.episode-log/1',
    generatedAt: new Date().toISOString(),
    banner: 'Recorded proof run. SIMULATED signals (source=simulator, freshness=simulated). ' +
      'Mock kin notifier, dispatch disabled: nothing was sent. Simulated clock, default windows.',
    dataLabels: LABELS,
    runs: [cancelled, escalated],
  };
  const dir = path.join(__dirname, '..', 'proofs');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'episode-log.json');
  fs.writeFileSync(file, JSON.stringify(out, null, 2) + '\n');
  console.log(`\nExported both episodes -> ${path.relative(process.cwd(), file) || file}`);

  console.log(failures === 0 ? '\nPROOF RESULT: all checks passed' : `\nPROOF RESULT: ${failures} CHECK(S) FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})().catch((err) => {
  console.error('proof runner crashed:', err);
  process.exit(2);
});
