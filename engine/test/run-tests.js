// Guardian escalation engine: test suite.
// Run: node test/run-tests.js   (or: npm test, from engine/)
// No framework beyond node:assert and a tiny runner. All engine timing
// is driven by FakeScheduler, so the suite is fully deterministic.

'use strict';

const assert = require('node:assert');
const {
  EscalationEngine,
  EventLog,
  STATES,
  FakeScheduler,
  MockNotifier,
  MockDispatcher,
  NoonlightSandboxDispatcher,
  buildNoonlightAlarmPayload,
} = require('../index');
const { MockHealthStoreAdapter } = require('../../adapters/health-store');
const { MockPhoneSensorsAdapter } = require('../../adapters/phone-sensors');

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

/** Let queued promise continuations run. */
async function flush(rounds = 10) {
  for (let i = 0; i < rounds; i++) {
    await new Promise((resolve) => setImmediate(resolve));
  }
}

function makeEngine(overrides = {}) {
  const scheduler = new FakeScheduler(1_000_000);
  const notifier = new MockNotifier();
  const dispatcher = new MockDispatcher();
  const engine = new EscalationEngine({
    contacts: [
      { id: 'kin-1', name: 'Daughter', phone: '+1-555-0101' },
      { id: 'kin-2', name: 'Son', phone: '+1-555-0102' },
      { id: 'kin-3', name: 'Neighbour', phone: '+1-555-0103' },
    ],
    cancelWindowSeconds: 30,
    cascadeAckTimeoutSeconds: 60,
    notifier,
    dispatcher,
    scheduler,
    wearerName: 'Test Wearer',
    ...overrides,
  });
  return { engine, scheduler, notifier, dispatcher };
}

// --- original behaviour ---

test('fall trigger reaches CASCADE after the cancel window lapses', async () => {
  const { engine, scheduler, notifier } = makeEngine();
  assert.strictEqual(engine.state, STATES.IDLE);
  assert.strictEqual(engine.trigger('fall_pattern', { peakG: 3.1 }), true);
  assert.strictEqual(engine.state, STATES.CANCEL_WINDOW);
  assert.strictEqual(notifier.calls.length, 0, 'no cascade during cancel window');

  await scheduler.advance(29_999);
  assert.strictEqual(engine.state, STATES.CANCEL_WINDOW, 'window has not lapsed yet');

  await scheduler.advance(1);
  assert.strictEqual(engine.state, STATES.CASCADE);
  assert.strictEqual(notifier.calls.length, 1, 'first kin contact notified');
  assert.strictEqual(notifier.calls[0].contact.id, 'kin-1');
});

test('wearer cancel during the window prevents the cascade and returns to IDLE', async () => {
  const { engine, scheduler, notifier, dispatcher } = makeEngine();
  engine.trigger('inactivity', { stillMinutes: 95 });
  await scheduler.advance(10_000);

  assert.strictEqual(engine.wearerCancel(), true);
  assert.strictEqual(engine.state, STATES.IDLE);

  await scheduler.advance(10 * 60_000); // far past window + all ack timeouts
  assert.strictEqual(engine.state, STATES.IDLE);
  assert.strictEqual(notifier.calls.length, 0, 'cascade never ran');
  assert.strictEqual(dispatcher.calls.length, 0, 'dispatch never fired');

  const types = engine.log.entries.map((e) => e.type);
  assert.ok(types.includes('wearer_cancelled'), 'cancel is in the log');
});

test('cascade stops at the first acknowledgment', async () => {
  const { engine, scheduler, notifier, dispatcher } = makeEngine();
  engine.trigger('missed_checkin', { missedByMinutes: 45 });
  await scheduler.advance(30_000); // cancel window lapses
  assert.strictEqual(engine.state, STATES.CASCADE);
  assert.strictEqual(notifier.calls.length, 1);

  // First contact does not respond; their ack timeout lapses.
  await scheduler.advance(60_000);
  assert.strictEqual(notifier.calls.length, 2, 'cascade moved to second contact');
  assert.strictEqual(notifier.calls[1].contact.id, 'kin-2');

  // Second contact acknowledges.
  assert.strictEqual(engine.acknowledge('kin-2'), true);
  await flush();
  assert.strictEqual(engine.state, STATES.RESOLVED);
  assert.strictEqual(notifier.calls.length, 2, 'third contact never notified');
  assert.strictEqual(dispatcher.calls.length, 0, 'no dispatch after acknowledgment');

  const ackEntry = engine.log.entries.find((e) => e.type === 'cascade_acknowledged');
  assert.ok(ackEntry, 'acknowledgment is logged');
  assert.strictEqual(ackEntry.data.contactId, 'kin-2');
});

test('dispatch fires only after cascade exhaustion (no-response timeouts)', async () => {
  const { engine, scheduler, notifier, dispatcher } = makeEngine();
  engine.trigger('manual_sos', {});
  await scheduler.advance(30_000); // cancel window
  assert.strictEqual(engine.state, STATES.CASCADE);
  assert.strictEqual(dispatcher.calls.length, 0, 'no dispatch while cascade is live');

  // Contacts 1 and 2 time out; contact 3 is still within their window.
  await scheduler.advance(60_000);
  await scheduler.advance(60_000);
  assert.strictEqual(notifier.calls.length, 3);
  assert.strictEqual(engine.state, STATES.CASCADE, 'third contact still has time');
  assert.strictEqual(dispatcher.calls.length, 0, 'dispatch waits for full exhaustion');

  // Third contact's no-response timeout lapses -> DISPATCH -> RESOLVED.
  await scheduler.advance(60_000);
  assert.strictEqual(engine.state, STATES.RESOLVED);
  assert.strictEqual(dispatcher.calls.length, 1, 'dispatch fired exactly once');
  assert.strictEqual(dispatcher.calls[0].episodeId,
    engine.log.entries.find((e) => e.type === 'trigger_received').data.episodeId);

  const dispatchEntry = engine.log.entries.find((e) => e.type === 'dispatch_result');
  assert.ok(dispatchEntry, 'dispatch result is logged');
  assert.strictEqual(dispatchEntry.data.status, 'mock-dispatched');
});

test('event log verifies intact and detects tampering', async () => {
  const { engine, scheduler } = makeEngine();
  engine.trigger('fall_pattern', { peakG: 2.8 });
  await scheduler.advance(30_000);
  engine.acknowledge('kin-1');
  await flush();
  assert.strictEqual(engine.state, STATES.RESOLVED);

  const intact = engine.log.verify();
  assert.strictEqual(intact.ok, true, 'untouched chain verifies');
  assert.strictEqual(intact.failedAt, null);

  // Tamper: rewrite history (pretend the trigger was something else).
  engine.log.entries[1].data.triggerType = 'manual_sos';
  const tampered = engine.log.verify();
  assert.strictEqual(tampered.ok, false, 'edited entry breaks the chain');
  assert.strictEqual(tampered.failedAt, 1);
});

test('trigger is rejected while an episode is active; bad types throw', async () => {
  const { engine } = makeEngine();
  assert.throws(() => engine.trigger('earthquake', {}), /unknown trigger type/);
  assert.strictEqual(engine.trigger('fall_pattern', {}), true);
  assert.strictEqual(engine.trigger('fall_pattern', {}), false, 'second trigger ignored mid-episode');
});

// --- LOOP FIX 1 ---

test('FIX1: wearer cancel during CASCADE stops the episode and prevents dispatch', async () => {
  const { engine, scheduler, notifier, dispatcher } = makeEngine();
  engine.trigger('fall_pattern', { peakG: 3.4 });
  await scheduler.advance(30_000); // -> CASCADE, kin-1 notified
  await scheduler.advance(60_000); // kin-1 times out, kin-2 notified
  assert.strictEqual(engine.state, STATES.CASCADE);
  assert.strictEqual(notifier.calls.length, 2);

  assert.strictEqual(engine.wearerCancel(), true, 'cancel accepted during cascade');
  assert.strictEqual(engine.state, STATES.IDLE);

  await scheduler.advance(10 * 60_000); // far past every remaining timeout
  assert.strictEqual(engine.state, STATES.IDLE);
  assert.strictEqual(notifier.calls.length, 2, 'cascade stopped; kin-3 never notified');
  assert.strictEqual(dispatcher.calls.length, 0, 'dispatch never fired after cancel');

  const cancel = engine.log.entries.find((e) => e.type === 'wearer_cancelled');
  assert.ok(cancel, 'late cancel is logged');
  assert.strictEqual(cancel.data.duringState, STATES.CASCADE);
});

test('FIX1: wearer cancel after dispatch is invoked is refused and logged beyond recall', async () => {
  let engineRef = null;
  let cancelDuringDispatch = null;
  const dispatcher = {
    calls: [],
    async dispatch(alarm) {
      this.calls.push(alarm);
      cancelDuringDispatch = engineRef.wearerCancel();
      return { status: 'sent', reference: 'ref-1' };
    },
  };
  const { engine, scheduler } = makeEngine({ dispatcher });
  engineRef = engine;

  engine.trigger('manual_sos', {});
  await scheduler.advance(30_000 + 3 * 60_000); // full cascade -> dispatch
  assert.strictEqual(dispatcher.calls.length, 1);
  assert.strictEqual(cancelDuringDispatch, false, 'cancel refused once dispatch is invoked');
  assert.strictEqual(engine.state, STATES.RESOLVED);

  const rejected = engine.log.entries.find((e) => e.type === 'wearer_cancel_rejected');
  assert.ok(rejected, 'refused cancel is logged');
  assert.strictEqual(rejected.data.reason, 'beyond_recall');
  const resolved = engine.log.entries.find(
    (e) => e.type === 'transition' && e.data.to === STATES.RESOLVED
  );
  assert.strictEqual(resolved.data.resolution, 'dispatched');
});

test('FIX2: late ack from kin-1 during kin-2 window resolves without dispatch', async () => {
  const { engine, scheduler, notifier, dispatcher } = makeEngine();
  engine.trigger('fall_pattern', {});
  await scheduler.advance(30_000); // kin-1 notified
  await scheduler.advance(60_000); // kin-1 timed out; kin-2 notified, window open
  assert.strictEqual(notifier.calls.length, 2);
  assert.strictEqual(engine.state, STATES.CASCADE);

  // kin-1 finally responds while the pending wait belongs to kin-2.
  assert.strictEqual(engine.acknowledge('kin-1'), true, 'late ack from a notified contact is consumed');
  await flush();
  assert.strictEqual(engine.state, STATES.RESOLVED);
  assert.strictEqual(notifier.calls.length, 2, 'cascade stopped by the late ack');
  assert.strictEqual(dispatcher.calls.length, 0, 'no dispatch after late ack');

  const ackEntry = engine.log.entries.find((e) => e.type === 'cascade_acknowledged');
  assert.ok(ackEntry);
  assert.strictEqual(ackEntry.data.contactId, 'kin-1', 'the acking contact is credited');
  assert.strictEqual(ackEntry.data.pendingContactId, 'kin-2');
});

test('FIX2: ack from a contact never notified is refused', async () => {
  const { engine, scheduler } = makeEngine();
  engine.trigger('fall_pattern', {});
  await scheduler.advance(30_000); // only kin-1 notified so far
  assert.strictEqual(engine.acknowledge('kin-3'), false, 'kin-3 has not been notified yet');
  assert.strictEqual(engine.state, STATES.CASCADE);
});

test('FIX4: ack slot is registered before notify, so an ack during notify is captured', async () => {
  let engineRef = null;
  let ackResult = null;
  const notifier = {
    calls: [],
    async notify(contact, alert) {
      this.calls.push({ contact, alert });
      // The contact acknowledges synchronously, inside the notify call.
      ackResult = engineRef.acknowledge(contact.id);
      return { delivered: true, channel: 'mock' };
    },
  };
  const { engine, scheduler, dispatcher } = makeEngine({ notifier });
  engineRef = engine;

  engine.trigger('fall_pattern', {});
  await scheduler.advance(30_000); // cancel window only; no ack timeout elapses
  assert.strictEqual(ackResult, true, 'ack during notify was consumed, not lost');
  assert.strictEqual(engine.state, STATES.RESOLVED, 'episode resolved without waiting out the ack timeout');
  assert.strictEqual(dispatcher.calls.length, 0);
});

test('FIX3: throwing dispatcher recovers to RESOLVED(error) and a new trigger works', async () => {
  const dispatcher = {
    calls: [],
    async dispatch(alarm) {
      this.calls.push(alarm);
      throw new Error('dispatch boom');
    },
  };
  const { engine, scheduler } = makeEngine({ dispatcher });
  engine.trigger('manual_sos', {});
  await scheduler.advance(30_000 + 3 * 60_000);
  assert.strictEqual(dispatcher.calls.length, 1);
  assert.strictEqual(engine.state, STATES.RESOLVED);

  const errEntry = engine.log.entries.find((e) => e.type === 'engine_error');
  assert.ok(errEntry, 'engine_error is logged');
  assert.match(errEntry.data.message, /dispatch boom/);
  const resolved = engine.log.entries.find(
    (e) => e.type === 'transition' && e.data.to === STATES.RESOLVED
  );
  assert.strictEqual(resolved.data.resolution, 'error');

  // Episode cleared: the engine accepts a fresh cycle without restart.
  assert.strictEqual(engine.reset(), true);
  assert.strictEqual(engine.state, STATES.IDLE);
  assert.strictEqual(engine.trigger('fall_pattern', {}), true, 'new trigger works after error');
  assert.strictEqual(engine.state, STATES.CANCEL_WINDOW);
});

test('FIX3: throwing notifier recovers to RESOLVED(error)', async () => {
  const notifier = {
    calls: [],
    async notify(contact, alert) {
      this.calls.push({ contact, alert });
      throw new Error('notify boom');
    },
  };
  const { engine, scheduler, dispatcher } = makeEngine({ notifier });
  engine.trigger('fall_pattern', {});
  await scheduler.advance(30_000);
  assert.strictEqual(engine.state, STATES.RESOLVED);
  const errEntry = engine.log.entries.find((e) => e.type === 'engine_error');
  assert.ok(errEntry, 'engine_error is logged');
  assert.match(errEntry.data.message, /notify boom/);
  assert.strictEqual(dispatcher.calls.length, 0);
});

test('FIX5: one-shot FakeScheduler advance reaches the same end state as stepped advance', async () => {
  const stepped = makeEngine();
  stepped.engine.trigger('manual_sos', {});
  await stepped.scheduler.advance(30_000);
  await stepped.scheduler.advance(60_000);
  await stepped.scheduler.advance(60_000);
  await stepped.scheduler.advance(60_000);
  await flush();

  const oneShot = makeEngine();
  oneShot.engine.trigger('manual_sos', {});
  await oneShot.scheduler.advance(30_000 + 3 * 60_000); // single advance, no flush between firings
  await flush();

  assert.strictEqual(oneShot.engine.state, STATES.RESOLVED);
  assert.strictEqual(oneShot.engine.state, stepped.engine.state);
  assert.strictEqual(oneShot.dispatcher.calls.length, 1);
  assert.strictEqual(oneShot.dispatcher.calls.length, stepped.dispatcher.calls.length);
  assert.deepStrictEqual(
    oneShot.engine.log.entries.map((e) => e.type),
    stepped.engine.log.entries.map((e) => e.type),
    'same log event sequence via one-shot and stepped advance'
  );
});

test('FIX6: intent entries are logged before each notify/dispatch side effect', async () => {
  const { engine, scheduler } = makeEngine();
  engine.trigger('manual_sos', {});
  await scheduler.advance(30_000 + 3 * 60_000);
  const types = engine.log.entries.map((e) => e.type);

  for (let i = 0; i < types.length; i++) {
    if (types[i] === 'cascade_notified') {
      assert.strictEqual(types[i - 1], 'cascade_notify_pending',
        'cascade_notify_pending immediately precedes cascade_notified');
    }
    if (types[i] === 'dispatch_result') {
      assert.strictEqual(types[i - 1], 'dispatch_pending',
        'dispatch_pending immediately precedes dispatch_result');
    }
  }
  assert.strictEqual(types.filter((t) => t === 'cascade_notify_pending').length, 3);
  assert.strictEqual(types.filter((t) => t === 'dispatch_pending').length, 1);
});

test('FIX8: verify(anchor) fails after truncation; serialize exports the entries', async () => {
  const log = new EventLog(() => 42);
  log.append('a', { n: 1 });
  log.append('b', { n: 2 });
  log.append('c', { n: 3 });

  const anchor = log.anchor();
  assert.strictEqual(anchor.count, 3);
  assert.strictEqual(anchor.headHash, log.entries[2].hash);
  assert.strictEqual(log.verify(anchor).ok, true, 'chain matches its own anchor');

  // Truncate: drop history. The remaining prefix is internally
  // consistent, so a bare verify() passes -- the anchor must catch it.
  log.entries.pop();
  log.entries.pop();
  assert.strictEqual(log.verify().ok, true, 'prefix alone still verifies (the honest limit)');
  const anchored = log.verify(anchor);
  assert.strictEqual(anchored.ok, false, 'truncation fails against the anchor');

  const exported = JSON.parse(log.serialize());
  assert.strictEqual(exported.entries.length, 1);
  assert.strictEqual(exported.entries[0].type, 'a');
  assert.deepStrictEqual(log.toJSON().entries.length, 1);
});

test('FIX8: keyed mode (GUARDIAN_LOG_KEY) chains with HMAC and fails without the key', async () => {
  const plain = new EventLog(() => 7); // constructed before the key is set
  process.env.GUARDIAN_LOG_KEY = 'unit-test-key';
  try {
    const keyed = new EventLog(() => 7);
    assert.strictEqual(keyed.keyed, true);
    keyed.append('x', { v: 1 });
    keyed.append('y', { v: 2 });
    assert.strictEqual(keyed.verify().ok, true, 'keyed chain verifies under its key');
    assert.strictEqual(keyed.verify(keyed.anchor()).ok, true);

    plain.entries = keyed.entries.map((e) => ({ ...e }));
    assert.strictEqual(plain.verify().ok, false,
      'an HMAC chain cannot be recomputed/verified without the key');
  } finally {
    delete process.env.GUARDIAN_LOG_KEY;
  }
});

test('FIX7: Noonlight transport receives the Authorization header and a body without _guardian', async () => {
  const captured = [];
  const transport = async (req) => {
    captured.push(req);
    return { status: 'ok', reference: 'nz-1' };
  };
  const d = new NoonlightSandboxDispatcher({
    enabled: true,
    token: 'tok-secret-123',
    transport,
  });
  const payload = buildNoonlightAlarmPayload(
    { id: 'ep-x', triggerType: 'fall_pattern', wearerName: 'Wearer One' },
    { lat: 43.7, lng: -79.4, accuracyM: 10 }
  );
  assert.ok(payload._guardian, 'built payload keeps _guardian for inspection');

  await d.dispatch(payload);
  assert.strictEqual(captured.length, 1);
  assert.strictEqual(captured[0].method, 'POST');
  assert.strictEqual(captured[0].headers.Authorization, 'Bearer tok-secret-123');
  assert.strictEqual(captured[0].headers['Content-Type'], 'application/json');
  assert.strictEqual(captured[0].body._guardian, undefined, '_guardian stripped from the sent body');
  assert.strictEqual(captured[0].body.name, 'Wearer One');
  assert.strictEqual(captured[0].body.services.medical, true);
  assert.ok(payload._guardian, 'the built payload object itself is not mutated');
});

test('FIX9: phone-sensors emits accelerometer samples via the currently registered callback', async () => {
  const sensors = new MockPhoneSensorsAdapter();
  const first = [];
  const second = [];
  sensors.onAccelerometer((s) => first.push(s));
  sensors.onAccelerometer((s) => second.push(s)); // replaces the first
  await new Promise((resolve) => setTimeout(resolve, 350));
  sensors.stop();
  assert.ok(second.length >= 1, `second subscriber received samples (got ${second.length})`);
  assert.strictEqual(first.length, 0, 'only the currently registered callback receives samples');
  assert.strictEqual(second[0].source, 'simulated');
});

test('FIX11: health-store readObservations respects sinceTs honestly (no re-stamping)', async () => {
  const adapter = new MockHealthStoreAdapter();
  const all = await adapter.readObservations({});
  assert.strictEqual(all.length, 6, 'one simulated sample per type');
  const hr = all.find((r) => r.type === 'heart_rate');
  assert.ok(hr);

  const again = await adapter.readObservations({ types: ['heart_rate'] });
  assert.strictEqual(again.length, 1);
  assert.strictEqual(again[0].ts, hr.ts, 'timestamps are stable across reads, never re-stamped');

  const atTs = await adapter.readObservations({ types: ['heart_rate'], sinceTs: hr.ts });
  assert.strictEqual(atTs.length, 1, 'a sample at sinceTs is inside the window (at/after)');

  const afterTs = await adapter.readObservations({ types: ['heart_rate'], sinceTs: hr.ts + 1 });
  assert.deepStrictEqual(afterTs, [], 'nothing is fabricated into a later window');

  const beyond = await adapter.readObservations({ sinceTs: Date.now() + 60_000 });
  assert.deepStrictEqual(beyond, [], 'a window beyond the series is honestly empty');
});

test('FIX10: two engine instances mint distinct episode IDs', async () => {
  const a = makeEngine();
  const b = makeEngine();
  a.engine.trigger('fall_pattern', {});
  b.engine.trigger('fall_pattern', {});
  const idA = a.engine.log.entries.find((e) => e.type === 'trigger_received').data.episodeId;
  const idB = b.engine.log.entries.find((e) => e.type === 'trigger_received').data.episodeId;
  assert.ok(idA && idB);
  assert.notStrictEqual(idA, idB, `episode IDs must differ across instances (${idA} vs ${idB})`);
});

// --- tiny runner ---
(async () => {
  let passed = 0;
  let failed = 0;
  for (const { name, fn } of tests) {
    try {
      await fn();
      passed += 1;
      console.log(`PASS  ${name}`);
    } catch (err) {
      failed += 1;
      console.error(`FAIL  ${name}`);
      console.error(`      ${err && err.message ? err.message : err}`);
    }
  }
  console.log(`\n${passed} passed, ${failed} failed, ${tests.length} total`);
  process.exit(failed === 0 ? 0 : 1);
})();
