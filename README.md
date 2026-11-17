# Guardian

**Protection gated on nothing but the phone already in their pocket.**

Guardian is an open-source health guardian for elderly people living
at home. It watches for the moments when a person cannot call for
help themselves — a fall, a long stillness on the floor, a missed
check-in, a heart pattern going wrong — and it escalates for them:
first a chance to say "I'm okay," then the people who love them, in
order, and only then a monitored dispatch service.

Nobody has to buy anything. The phone they already own is the base
device. Every wearable they may already own — any brand, at any price —
makes Guardian better. None is required.

## Why this exists

The number behind Guardian: in the studied cohorts, the large
majority of "long lies" — a senior on the floor for an hour or
more — happened to people who **owned an alarm button and never
pressed it**. (The often-quoted mortality figure attached to long
lies — half of those who lay over an hour dead within six months —
comes from one small historical study; Guardian cites it with
care, as context, not as a measured modern rate.) A button
you must press is not protection for someone who is unconscious,
injured, or confused. Detection has to be automatic, and the help has
to already be moving.

## How it works

```
 wearables (any brand) ──┐   (contract only — scaffold)
 health stores (HealthKit │   (contract only — scaffold)
  / Health Connect) ──────┤   (contract only — scaffold)
 BLE heart-rate straps ───┼──> ingestion (adapters/)
 phone sensors (accel,    │         │
  GPS, camera PPG) ───────┘         v
        (contract only — scaffold)
                        escalation engine (engine/)
                        IDLE → TRIGGERED → CANCEL_WINDOW
                             → CASCADE (kin, in order)
                             → DISPATCH (monitored service)
                             → RESOLVED
                                  │
                        hash-chained event log (every step)
                                  │
                        FHIR R4 record → provider view;
                        role-based views → nutritionist, kin, self
```

- **Cancel window first.** A trigger always gives the wearer a
  window to cancel. Most alarms are false; dignity and calm are
  design requirements, not afterthoughts.
- **Kin before sirens.** Family and neighbours are notified in a
  configured order. The first person to acknowledge stops the
  cascade. Dispatch happens only when nobody answers.
- **Monitored dispatch, never a robot 911 call.** Guardian never
  dials emergency numbers directly — automated dialing of emergency
  lines is prohibited, and real dispatch is a monitored
  central-station function. The dispatcher seat is an interface; a
  monitored service (Noonlight class) fills it under its own
  partnership. In this scaffold, dispatch is disabled by default.
- **A log nobody can quietly rewrite.** Every transition lands in a
  hash-chained event log. For a product families must trust with a
  parent's worst day, the record of what happened, when, and who
  responded has to be tamper-evident.
- **Vendor-neutral by design.** Open routes only: the OS health
  stores, standard Bluetooth profiles, local band bridges, phone
  sensors. No brand partnership is a dependency; premium brands are
  optional connectors behind the same contracts.

## Honest limits (read these)

Guardian will not oversell itself. These are true today and stated
on purpose:

- **Fall detection needs the phone on the person** (pocket or
  pouch). A phone on the kitchen table cannot feel a fall in the
  bathroom. Inactivity patterns and missed check-ins cover part of
  that gap, not all of it.
- **Cheap wrist bands do not give up their raw sensors.** Most
  bargain bands expose samples (heart rate, SpO2 spots, steps,
  sleep) through bridges, not live streams, and no raw
  accelerometer — so fall detection rides on the phone, not the
  band.
- **Most wearable data is batch, not live.** Health-store and band
  data arrive after syncs. The phone's own sensors are the real-time
  layer; everything else is honestly labelled with its freshness.
- **iOS restricts background sensing more than Android.** The two
  apps are not identical underneath; on iOS the health stores and
  check-ins carry more of the load.
- **Dispatch is partnership-gated in production.** The sandbox route
  is real; a live monitored-dispatch integration requires the
  dispatch provider's onboarding (US: measured in weeks) and, in
  Canada, a central-station arrangement. Guardian's engine is ready
  for it; the paperwork is not a code problem.
- **Guardian is not a medical device** and makes no diagnosis.
  It is an escalation and sharing layer.

## Status: scaffold

What exists now:

- `engine/` — the escalation state machine in plain Node.js
  (no build step, no dependencies): deterministic timing via an
  injected scheduler, hash-chained event log, notifier and
  dispatcher interfaces with console/mock implementations.
  Dispatch defaults OFF; no real external calls are made anywhere.
  Test suite: `cd engine && npm test` (6 tests, all passing at
  scaffold time — re-run to verify on your machine).
- `adapters/` — ingestion contracts (health store, BLE heart rate,
  phone sensors) with mock implementations. **Mock data is always
  labelled `source: "simulated"`**, in code and in any demo.

What does not exist yet: the mobile apps, the native bridges behind
the adapter contracts, the FHIR writer and audience views, the kin
cascade's real messaging, and any production dispatch integration.
Each lands behind its interface, in the open.

## License

MIT. See [LICENSE](LICENSE). Build on it, fork it, ship it for your
own parents — that is what it is for.
