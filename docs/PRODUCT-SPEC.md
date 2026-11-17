# Guardian — Product Spec

**Working name:** Guardian (repo: `guardian-app`)
**Status:** Approved by John, Nov 13, 2026. Open source.
**Mission:** *Do some greater good.* Guardian is a free, open-source
health guardian for elderly people living at home. Protection is gated
on nothing but the phone already in their pocket. Every wearable they
may already own makes it better; none is required, and nobody has to
buy anything.

Guardian watches for the moments an elderly person cannot call for
help themselves — a fall they cannot get up from, the long lie that
follows, a dangerous vital-sign pattern, a check-in that never comes —
and moves help toward them automatically: family first, then
professional dispatch, with a clinical record written for their care
team either way.

---

## 1. Why this exists (the problem, in numbers)

- 1 in 4 adults 65+ falls every year (US CDC); ~43,000 US fall deaths
  in 2024; non-fatal falls cost ~$80B/year, about 67% paid by
  Medicare. In Canada, falls cause 85% of seniors' injury
  hospitalizations and cost ~CAD $5.6B/year.
- The killer is not the fall, it is the wait. In the BMJ Cambridge
  over-90s cohort, 80% of fallers could not get up unaided at least
  once, 30% lay on the floor an hour or more ("long lie"), and **97%
  of long lies happened to people who owned an alarm button but never
  pressed it.** Half of those who lay more than an hour died within
  six months (historical study, cited in the literature). The outcome
  variable is **time-to-assistance**, and the proven failure mode is
  the manual button.
- Smartwatch screening finds new atrial fibrillation in 9.6% of
  high-risk seniors vs 2.3% under standard care (EQUAL trial, JACC
  2025), 57% of it asymptomatic. Home detection is the front of the
  stroke clock.
- Incumbents each solve a slice: PERS pendants ($35-55/mo, rented
  hardware, human call center), Apple Watch (fall detection inside
  one ecosystem, $249+ entry), cross-vendor dashboards (family views,
  no emergency dispatch). **Nobody open-source bundles automatic
  escalation + whatever device the senior already owns + one
  consent-based view for family and clinician. That intersection is
  Guardian.**

## 2. Users and consent-based role views

One wearer record, four audiences. **The wearer controls every share.**
Each recipient sees only what the wearer (or their designated
delegate) granted, at the granularity granted, and any grant can be
revoked from the wearer's phone. Consent state is part of the record
and is shown, not buried.

| Role | Who they are | What they see (when granted) | What they never see by default |
|---|---|---|---|
| **Wearer** | The elderly person | Everything: their signals, alerts, history, who has access, one-tap "I'm OK" and "I need help" | Nothing hidden from the wearer |
| **Next of kin** | Adult child, spouse, neighbour — the first responders | Emergency alerts with live location the moment an event fires; daily "all quiet" digest; check-in status | Raw continuous vitals, unless the wearer grants the full view |
| **Healthcare provider** | Family doctor, clinic, home-care nurse | FHIR R4 record: vitals Observations, fall/event history, trend summaries; exportable report | Live location streaming; family chat or notes |
| **Nutritionist / dietitian** | Dietitian, meal-service coordinator | Event-linked summaries: post-event activity decline, weight/appetite trend proxies, sleep disruption after events — the signals relevant to nutrition follow-up | Live alerts (unless also kin), raw sensor streams |

The nutritionist is a first-class **recipient**, not a marketing
claim: there is no nutritionist system to integrate with, and Guardian
says so. Their view is a role-based view/export of the same record,
designed around concrete events (a fall is also a nutrition event:
appetite, weight, and activity all move afterwards).

## 3. The core loop

```
SENSE → DETECT → CANCEL WINDOW → CASCADE → DISPATCH → RECORD
```

1. **Sense.** Signals flow in from whatever the wearer has: the
   phone's own sensors, the OS health stores (HealthKit / Health
   Connect, which already aggregate most wearables), open BLE
   devices, and bridged budget bands. Every reading is labelled by
   source and freshness.
2. **Detect.** A deterministic rules/state engine watches for: a
   hard-fall signature (phone accelerometer), an inactivity /
   long-lie pattern (no movement + no response after a motion
   anomaly), a dangerous vital-sign pattern (heart rate or SpO2
   outside the wearer's personal thresholds), and a missed check-in
   (the wearer did not confirm "I'm up and OK" by their usual time).
   Detection logic is identical regardless of which source fed it.
   One freshness rule binds the vitals triggers: a vitals-based
   trigger requires readings inside the freshness bound (default
   30 minutes). Older readings are downgraded to digest items and
   never start a cascade (see ARCHITECTURE.md §4).
3. **Cancel window.** The phone alarms loudly and shows one huge
   button: **"I'm OK."** Default window 60 seconds, configurable.
   Most false alarms die here, by the wearer's own hand. No response
   is itself the signal.
4. **Cascade.** On an uncancelled event: SMS + voice calls to next of
   kin in the wearer's chosen order, with live location and a plain
   description ("Possible fall at home, no response to the alarm").
   Any kin member can acknowledge, which pauses escalation and tells
   the others help is aware.
5. **Dispatch.** The cascade makes one ordered pass through the kin
   list, with a per-contact acknowledgment timeout (default
   120 seconds). If the pass finishes and nobody has acknowledged,
   Guardian fires a dispatch alarm to a monitored-dispatch partner
   (Noonlight class), whose human agents verify and route to local
   emergency services. See the honest limits: Guardian never dials
   911 itself.
6. **Record.** Whatever happened — cancelled, kin handled, dispatched
   — is written to the wearer's record as FHIR R4 resources
   (Observations, event Encounter/Flag) and shown in every role view
   at its granted granularity. In v1, the record does two concrete
   things: it gives the provider context (event history and vitals
   trends around each event, in the provider view and the exported
   report), and it gives the wearer and kin a shared timeline of
   what happened, who was contacted, and who responded. It does
   not feed back into detection in v1.

## 4. Feature set

### v1 (demo-able build; see BUILD-PLAN.md)

- Phone-first sensing: accelerometer fall detection, inactivity /
  long-lie pattern, missed check-in escalation — all on-device.
- Health-store aggregation: reads heart rate, SpO2, steps, and sleep
  from HealthKit (iOS) and Health Connect (Android) behind one
  contract; any wearable already syncing to the phone contributes.
- Vitals guardrails: per-wearer thresholds on the freshest available
  heart-rate/SpO2 readings, with source and age shown on every value.
- The full core loop: cancel window, Twilio SMS/voice kin cascade
  with acknowledgement, Noonlight **sandbox** dispatch, FHIR R4
  record written to a local HAPI server and read back.
- Consent & routing policy: wearer-controlled per-role grants
  (kin alerts, kin full view, provider record, nutritionist summary),
  escalation order and windows configurable by the wearer/delegate.
- Four role views: wearer (big-button, high-contrast), kin (alerts +
  digest), provider (FHIR-backed record + export), nutritionist
  (event-linked summary). **The nutritionist view is v1 — first on
  the Nov 27 cut line** (tied with camera PPG, below): if it is
  cut, the demo script's fallback shape is an export-only
  nutritionist summary (a generated report, no dedicated view),
  and every demo reference to the view is replaced by the export.
- Camera PPG spot check: fingertip heart-rate check from the phone
  camera, labelled as a spot check, never a continuous monitor.
  **Camera PPG is v1 — first on the Nov 27 cut line** (tied with
  the nutritionist view, above): if it is cut, v1 ships without
  the spot check and no demo beat depends on it.
- Source labelling everywhere: every signal on every screen is
  marked **live**, **fetched** (with its age), or **simulated**
  (demo traces, see §6).

### Later (post-v1, in rough priority)

- BLE direct tier: standard Heart Rate Profile (0x180D) devices and
  chest straps read live by the app; Gadgetbridge-class bridge
  import for Xiaomi/Amazfit/no-name bands that never touch the
  health stores.
- Google Health API connector (Fitbit/Pixel mainstream) once OAuth
  verification is worthwhile; Garmin/Apple-direct connectors behind
  the same ingestion contract, optional forever.
- Production dispatch partnerships (Noonlight production, US;
  central-station monitoring, Canada) — contracts, not code.
- Caregiver delegate mode (a kin member manages settings for a
  wearer who cannot), multi-wearer family accounts.
- Clinician trend reports (weekly PDF/FHIR bundle), SMART on FHIR
  launch against real EHR sandboxes.
- On-device personal baselines (thresholds learned from the wearer's
  own history instead of fixed defaults), fully on-device.
- Localization, starting with English + French (Canadian context).

## 5. The equity spine

This is the product's reason to exist, stated as design law:

1. **$0 hardware.** The base device is the phone already in their
   pocket. No pendant to rent, no watch to buy, no subscription
   required for the core loop.
2. **Any wearable helps, none is required.** A $15 band, a chest
   strap, a flagship watch — if it can reach the phone through an
   open route, it is a first-class citizen. Protection scales with
   what a family already owns, not with what they can afford.
3. **Open source.** The detection and escalation code is inspectable
   by the families, clinicians, and community groups who rely on it.
   Safety logic that cannot be read cannot be trusted.
4. **The wearer is the owner.** Their data, their grants, their
   escalation policy. Family and clinicians are guests the wearer
   invited.
5. **Designed for the actual user.** Huge touch targets, one-button
   answers, high contrast, voice prompts, no accounts-with-passwords
   gymnastics for the wearer. A guardian a senior cannot operate is
   a dashboard, not a guardian.

## 6. Honest limits (product copy — these ship in the app and docs)

Guardian's credibility is its honesty. These limits appear in the
product itself, not just in this spec:

- **"Fall detection needs the phone on you."** Guardian can only
  detect a fall when the phone is on the wearer's person (pocket,
  belt, pouch). A phone on the kitchen table cannot feel a fall in
  the bathroom. The inactivity and missed-check-in layers exist
  precisely to cover the phone-left-behind case, more slowly.
- **"iPhone and Android do not sense the same way."** iOS restricts
  background sensor work more than Android. On Android, Guardian
  runs a foreground service for continuous fall sensing. On iPhone,
  continuous accelerometer sensing is limited; the health-store
  signals and check-ins carry more of the load. The app tells each
  wearer which protections are active on their phone.
- **"Guardian never calls 911 directly."** Automated systems are
  prohibited from dialling 911 (US FCC rules; Quebec law prohibits
  automatically connecting an alarm system to 9-1-1, and Canadian
  municipalities ban autodialers to emergency lines). Guardian's
  dispatch step hands a verified alarm to a **monitored dispatch
  partner** (Noonlight class) whose human agents contact local
  emergency services. That partnership is the legal architecture
  everywhere this problem is solved seriously.
- **In the demo build, dispatch is a sandbox.** The Noonlight
  integration runs against Noonlight's developer sandbox: the alarm
  is real API traffic and returns a real sandbox alarm ID, but no
  emergency services are contacted. Production dispatch requires a
  monitoring agreement (Noonlight's own onboarding runs 30-90 days,
  US only; Canada requires a central-station partner). The demo
  says so on screen.
- **Vitals are only as fresh as their source.** Health-store and
  band data arrive in batches and syncs, not streams. Guardian
  shows the age of every reading and never presents a stale value
  as live. Continuous real-time sensing comes from the phone
  itself.
- **Guardian is not a medical device.** It is a consumer safety
  aid. It does not diagnose, its thresholds are not clinically
  validated, and it does not replace a monitored medical-alert
  service for people whose clinician recommends one. (This is also
  why Guardian is not Medicare-RPM billable: that lane requires
  FDA-cleared, auto-uploading devices under a billing practitioner.
  Guardian does not claim it.)

## 7. What success looks like

A daughter in another city gets a call that says her mother may have
fallen, taps "I'm handling it" or watches a dispatcher take over —
on a phone her mother already owned, with a band her brother bought
her two Christmases ago quietly contributing its data, and her
mother's doctor reading the same event in Guardian's provider
view / the exported report a week later.
No new hardware was purchased. No button had to be pressed.
