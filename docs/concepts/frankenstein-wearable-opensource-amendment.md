# Amendment — Nov 13, 2026 (John): no Garmin required; open source, any wearable

John's direction supersedes the tier framing in frankenstein-wearable-*.md:
the platform is VENDOR-NEUTRAL and OPEN SOURCE. No brand is required and
no partnership is a dependency. Any wearable that can surrender data
through an open route is a first-class citizen.

## Architecture (open routes only)
- Standard BLE profiles where exposed (Heart Rate 0x180D/0x2A37, battery,
  device info) — chest straps and workout-mode bands work today.
- Gadgetbridge-class local bridges for Xiaomi/Amazfit/no-name bands
  (HR, SpO2 spot, steps, sleep; samples, honestly labelled).
- Google Health API for the Fitbit/Pixel mainstream (restricted scopes;
  demo/personal use now, production verification later).
- Phone as the real-time layer (live sensors, GPS, voice line) and as a
  zero-cost "wearable" for people who own no band at all.
- Garmin and Apple become OPTIONAL future connectors behind the same
  ingestion contract, never requirements.
- Outputs stay as designed: FHIR R4 Observations for the provider view,
  role-based views/exports for nutritionist and kin, Twilio cascade,
  Noonlight sandbox dispatch (production partnership is a deployment
  step, not a build dependency).

## What this fixes
- The Garmin partnership wall and license fee: GONE from the critical path.
- The Frankenstein stitch gets MORE load-bearing: incompatible open
  protocols (BLE profiles, a reverse-engineered bridge, a sync API,
  phone sensors) unified into one body is a real chimera, not plumbing.
- Demo honesty improves: a real bargain band + phone can produce real
  data in the judging window; no tier needs a simulator except
  optional-brand connectors.

## What it does not fix
- Incumbents: OVURA is already cross-vendor commercially; our
  differentiation becomes open-source + the escalation-policy/consent
  routing layer (the surviving wedge from the market lane).
- No raw accelerometer from cheap bands: fall detection still rides on
  the phone or vendor alerts; the long-lie problem is addressed via
  inactivity/vitals patterns + check-in escalation, stated honestly.
- Automated 911 remains prohibited; monitored dispatch (Noonlight
  class) remains the legal architecture, US production still gated.
- Effort and pool math for Kiroween are unchanged: still a full build
  in GhostBridge's window, in a one-slot category.

Status: amendment recorded against the PARKED product concept
(post-Kiroween candidate). If John directs a Kiroween re-evaluation
under this architecture, re-run the fit lane only; market and legal
findings stand.

## Amendment 2 — Nov 13, 2026 (John): an app for Android and Apple; no purchase required

The product is a PHONE APP first (Android + iOS). Nobody has to buy
anything: the phone they already own is the base device. Wearables of
any brand are optional signal boosters, never the entry ticket.

- AGGREGATION LAYER: Apple HealthKit (iOS) and Health Connect
  (Android) are the vendor-neutral layer — they already collect from
  Apple Watch, Garmin, Fitbit, Samsung and most bands whose owners
  sync to the phone. The app reads one contract per OS instead of
  chasing vendor APIs; BLE/Gadgetbridge routes remain for bands that
  never touch the health stores.
- PHONE AS THE SENSOR: phones expose RAW accelerometer (unlike cheap
  bands), plus GPS and a voice line — so on-phone fall detection,
  inactivity/long-lie patterns, and missed-check-in escalation are
  real on the base tier. Camera PPG (fingertip heart rate) is an
  available spot-check stitch. Honest limits, to be stated in the
  product: fall detection only works when the phone is on the person
  (pocket/pouch), and iOS restricts background sensor work more than
  Android (foreground-service design on Android; on iOS the health
  stores + check-ins carry more of the load).
- DEMO CONSEQUENCE: the demo device is a phone the judge can hold.
  A drop onto a cushion triggers the real flow — cancel window,
  Twilio cascade to real phones, Noonlight sandbox alarm, FHIR
  record written. Performable proof, no staged vitals needed.
- EQUITY LINE (the concept's spine): protection gated on nothing but
  the phone already in their pocket; every wearable they may already
  own makes it better, none is required.
