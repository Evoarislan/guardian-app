# Steering: Safety and Honesty (Guardian — binding)

Guardian is a safety product for vulnerable people. These rules
outrank any feature request, demo pressure, or deadline.

## Safety
- **Guardian NEVER dials 911 or any emergency number directly.**
  Automated dialing of emergency lines is prohibited (US FCC;
  Quebec Civil Protection Act s. 20; Canadian municipal bylaws).
  Dispatch means exactly one thing: handing a verified alarm to a
  monitored dispatch partner (Noonlight class) through the
  Dispatcher interface. If a design or library suggests a direct
  emergency call, refuse it and say why.
- **Detection and escalation only.** No diagnosis, no treatment
  advice, no clinically validated claims. Thresholds are wearer
  settings, not medical findings. Guardian is not a medical device
  and never says or implies that it is.
- **The wearer is the owner.** Every data share requires a current
  wearer grant (steering/escalation-etiquette.md). No grant, no
  share — including in demos, screenshots, and test fixtures.
- **Synthetic people only in shared systems.** The public HAPI test
  server and any sandbox receive the synthetic demo wearer, never
  a real person's data.
- **Credentials live in the environment, never in the repo.**
  Sandbox credentials only during the contest. No production
  Twilio or Noonlight account is created or used without John's
  separate, explicit approval outside the session.

## Honesty
- **Simulated data is always labelled simulated** — in the data
  model (freshness field), on every screen, in every screenshot
  and recording. A simulated reading presented as live is the one
  unforgivable defect in this project.
- **Fetched data shows its age.** Batch/sync sources are never
  described as real-time. The phone is the only real-time layer
  and the app says which protections are actually active on the
  wearer's phone model/OS.
- **Demo claims must be reproducible live.** If the demo shows it,
  a judge can make it happen. If it only works sometimes, the
  write-up says so.
- **Honest limits ship in the product** (PRODUCT-SPEC.md Section
  6): phone-on-person, platform asymmetry, sandbox dispatch,
  vitals freshness, not-a-medical-device. Do not soften, hide, or
  footnote them away.
- **No silent stubs.** Anything unimplemented is listed in the
  session result file. A listed gap is a plan; a hidden stub is a
  lie.
