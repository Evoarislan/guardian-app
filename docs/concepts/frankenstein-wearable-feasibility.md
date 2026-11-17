# Frankenstein Wearable Feasibility Audit — Elderly Health Guardian

Audited Nov 13, 2026, for a solo builder, demo due Dec 4, 2026 (Kiroween,
Frankenstein category: incompatible technologies stitched into one app).
Method: primary sources first (vendor developer pages, official docs,
statute text). Anything not confirmed on a primary source is labelled
UNVERIFIED. Research only; nothing was signed up for and nobody was
contacted.

Concept under audit: ingest wearable data across device tiers (top-line
Garmin down to the cheapest loop band), detect health emergencies,
automate escalation to emergency services and next of kin, and share data
with the healthcare provider, a nutritionist, family, and the wearer.

## Verdict summary

| Tier / claim | Verdict |
|---|---|
| Top tier (Garmin cloud data) | PARTNERSHIP-GATED. Evaluation access possible by Dec 4 only if Garmin approves a business-use application; a solo individual is likely ineligible. A personal-use route for the builder's own data is reported by integrators (UNVERIFIED on Garmin's own pages). |
| Budget mainstream (Fitbit / Pixel) | CHANGED UNDER US. The legacy Fitbit Web API was switched off Oct 30 / Nov 2, 2026. Its successor, the Google Health API, is buildable in test mode but every scope is restricted and production needs Google's verification review. |
| Bottom tier (Xiaomi / Amazfit / no-name) | POSSIBLE BY DEC 4, via Gadgetbridge on Android: periodic fetched samples (HR, SpO2, steps, sleep), not a live stream. Zepp has no public cloud API. Raw accelerometer and custom fall detection: NOT available. |
| Emergency automation | DEMO: honest and buildable (real Twilio calls/texts to contacts + Noonlight in SANDBOX). PRODUCTION DISPATCH: partnership-gated, US-only, 30-90 day implementation per Noonlight's own FAQ. Direct automated 911 dialing: prohibited / bylaw-banned in Canada; do not build it. |
| Provider sharing | DEMO-READY today: real FHIR R4 Observations on the public HAPI test server. Real EHR integration (SMART on FHIR into a hospital system) is registration-and-review gated, not a hackathon item. |

## 1. Top tier: Garmin

**What Garmin officially offers (primary: developer.garmin.com).**

- The **Health API** (Garmin Connect Developer Program) covers steps,
  heart rate, sleep, stress, pulse ox (SpO2), respiration, blood pressure,
  body composition, Body Battery, and second-level HR during activities.
  Delivery is push or ping/pull of JSON summaries **after the user syncs
  the device to Garmin Connect** (Program FAQ + Health API page). It is a
  batch, sync-based feed. It is not a real-time stream.
- **Business use only.** The Program FAQ states verbatim: "no licensing
  or maintenance fees for access to the Garmin Connect Developer Program,
  but it is only for business use. Access to some metrics may require a
  license fee payment or minimum device order quantity for commercial
  use." The Health API page's footnote: "Commercial use requires a
  license fee payment." Beat-to-beat interval data is the flagged
  license-fee metric.
- **Approval timeline (official):** Garmin "will confirm the status of
  your application within two business days"; if approved, evaluation
  environment first; "a typical integration takes between 1 and 4 weeks."
- Integrator documentation (open-wearables docs, secondary) is blunter:
  the program "does not support personal use. You must apply as a legal
  entity... Personal-use applications are rejected." Treat the
  legal-entity requirement as the operative risk: an individual
  hackathon entrant applying as a person is likely rejected, and
  evaluation apps "used for commercial/production purposes may be
  disabled without prior notification."

**Other Garmin routes.**

- **Connect IQ** (free SDK, separate program per the Garmin FAQ): apps
  and widgets run on the watch itself. A CIQ app can use the sensors
  while it is running, but it is not a channel for streaming a user's
  all-day health data to your server, and it exposes no third-party
  fall-event or raw-accelerometer feed. It cannot carry this concept.
- **Garmin Health SDK** (mobile SDK for Android/iOS): exists as part of
  Garmin's enterprise health offering; terms and access are sales-gated
  (details UNVERIFIED from primary pages in this pass).
- **Personal-use route:** multiple integrator sources (aifitnessapi,
  HealthLog) report an official Garmin "Personal API" / self-created key
  that reads the builder's OWN Connect data with no Developer Program
  approval. UNVERIFIED against Garmin's own documentation in this pass.
  If real, its honest scope is one person's data (the demo wearer's),
  which is exactly what a demo needs and all it can claim.

**Honest Garmin answer for Dec 4:** apply immediately as a business if
an entity exists (2-business-day status answer; evaluation keys could
plausibly land inside the window) — but the demo must not depend on it.
Design Garmin as a pluggable adapter with sample/evaluation data, and
label it that way. The live-data hero of the demo has to come from a
lower tier.

## 2. Bottom tier: cheap bands

**The standard path that actually exists: BLE Heart Rate Profile.**
The Bluetooth SIG Heart Rate Service (0x180D) with the Heart Rate
Measurement characteristic (0x2A37, notify, ~1 notification/sec) is an
adopted standard: any app on Android/iOS can subscribe with no vendor
permission. In practice it is exposed reliably by chest straps and some
watches. Most cheap wrist bands do **not** expose standard 0x180D to
third-party apps outside workout mode; their HR flows over proprietary
protocols to the vendor app. So "any app reads any band's heart rate
live" is FALSE as a general claim.

**Gadgetbridge (open source, primary: gadgetbridge.org).** An Android
app that talks to the bands directly over BLE using reverse-engineered
protocols, no vendor cloud. Documented coverage for Zepp OS devices
(Amazfit line, Mi Band 7) and Xiaomi protobuf devices (Mi Band 8/9/10
class): heart rate (stored samples + real-time on supported devices),
SpO2 (fetched samples; all-day SpO2 must be enabled on device; sleep
SpO2), steps/activity, sleep (incl. stages, respiratory rate), stress,
body/skin temperature on supported models, resting HR, HRV on supported
devices. Documented limits (Gadgetbridge's own Zepp OS page): "3rd party
realtime heart rate access is not working, even with the vendor app";
SpO2 sync on some families is periodic fetch, not a stream. Pairing
Amazfit/Xiaomi devices in Gadgetbridge requires a one-time auth key
obtained via the vendor app/account.

Signal reality table (bottom tier, third-party access):

| Signal | Available? | How |
|---|---|---|
| Heart rate | YES, samples; near-live on some devices | Gadgetbridge fetch / vendor app; 0x180D if a strap or workout mode |
| SpO2 | YES, spot/periodic samples | Gadgetbridge fetch (device support varies) |
| Steps | YES | Gadgetbridge / vendor sync |
| Sleep + stages | YES, after the fact | Gadgetbridge sync |
| Skin/body temperature | PARTIAL, supported models only, deviation-style readings | Gadgetbridge |
| Raw accelerometer | NO | No third-party raw stream from cheap bands |
| Fall detection (custom) | NO | No raw accel = no own algorithm; vendor on-device fall alerts, where a model has them, do not reach third-party apps (exposure UNVERIFIED) |

**Vendor APIs.**
- **Zepp / Amazfit:** no public cloud REST API for health data (Zepp's
  open platform documents Zepp OS Mini Programs that read sensors on the
  watch and can POST to your server via a phone-side service — a real
  but watch-app-shaped path). An official OAuth partner API exists for
  sanctioned partners (e.g., Intervals.icu); access is partner-gated.
  The widely used Huami cloud endpoints are undocumented and
  reverse-engineered.
- **Fitbit (the budget-mainstream case) — status changed in 2026:**
  the legacy Fitbit Web API's support ended Sep 30, 2026 and the API was
  switched off Oct 30 (dev.fitbit.com) / Nov 2, 2026 (Google docs),
  returning HTTP 410. The successor **Google Health API**
  (health.googleapis.com) covers Fitbit + Pixel data via Google OAuth;
  all scopes are RESTRICTED: an unverified app is capped (reported at
  100 users) and a public/production app requires Google's OAuth
  verification plus a periodic CASA security assessment. Granularity:
  daily summaries broadly; spot HR, HRV, SpO2, sleep stages available;
  skin temperature only as a nightly deviation. Personal-mode
  single-user testing is feasible by Dec 4; a multi-user production
  claim is not.

## 3. Emergency automation: what it can honestly mean

**Direct automated dialing of 911: do not build it.**
- US: the TCPA/FCC rules (47 CFR 64.1200(a)(1)(i)) prohibit autodialed
  or prerecorded-voice calls "to any emergency telephone line, including
  any 911 line" except calls "made for emergency purposes." Even where a
  genuine-emergency carve-out can be argued, PSAPs answer voice calls
  from humans; an automated call delivers no structured data, cannot
  answer the call-taker's questions, and ties up a line. No serious
  product does this; alarm systems route through monitoring centers.
- Canada: Quebec's Civil Protection Act, s. 20 (LegisQuebec, primary):
  "It is prohibited to automatically connect an alarm system to the
  9-1-1 emergency service." Municipal bylaws repeat the pattern
  (Vancouver Bylaw 7111 s. 24 bans automatic calling devices to police
  numbers; Edmonton fines the use of an automatic calling device to dial
  911). The legal Canadian architecture is a monitored central station.

**What IS buildable and real:**
- **The contact cascade (real, today):** detection → countdown/"I'm OK"
  cancel window on the wearer's phone → Twilio SMS + voice calls to
  next of kin and caregivers (Twilio list prices per third-party reads
  of Twilio's pricing pages: SMS ~$0.0083/segment US/CA, outbound voice
  ~$0.014/min; trial credit covers a demo). This is a genuine, working
  escalation, and it is the layer most real PERS products automate
  first.
- **Noonlight (verified real, primary: docs.noonlight.com,
  noonlight.com FAQ):** a Dispatch API exists with a public developer
  portal and a SANDBOX (api-sandbox.noonlight.com; POST
  /dispatch/v1/alarms). Triggering an alarm puts a Noonlight agent in
  text contact with the user; if emergency services are needed the agent
  pushes location + event data to local dispatchers. Constraints,
  verbatim from Noonlight: the Dispatch API "is only supported in the US
  (all 50 states)"; pricing is NOT published (official FAQ: volume tiers
  by alarm-initiation type, "contact our sales team"; third-party
  directories list partner plans starting at $0.25/user/month,
  UNVERIFIED as current terms); implementation "typically take[s]
  somewhere between 30 and 90 days" with a dedicated implementation
  manager. Verdict: sandbox integration is demoable by Dec 4; live
  production dispatch is partnership-gated and outside the window, and
  it does nothing for a Canadian wearer.
- **RapidSOS:** real emergency-data platform (data delivery to 911
  centers; partners include Apple, Google, MedicAlert, wearable and
  PERS companies). Integration is via enterprise partnership/API
  agreements, not self-serve signup; no public pricing or sandbox found
  (self-serve availability UNVERIFIED; treat as partnership-gated).

**The honest claim split.**
- Demo claim: "Guardian detects a fall or a dangerous vital-sign pattern,
  gives the wearer a cancel window, then automatically calls and texts
  the family cascade with live location, and fires a dispatch alarm
  through Noonlight's monitored sandbox — the same API whose production
  tier puts a human dispatcher in the loop."
- Production claim (future, requires contracts): "with a Noonlight (US)
  or central-station (Canada) monitoring agreement in place, a verified
  alarm is handed to professional dispatchers who send emergency
  services." Never claim the software dials 911 itself.

## 4. Provider data: FHIR without a hospital

- **FHIR R4** is the exchange standard: wearable readings become
  `Observation` resources with LOINC codes (e.g., 8867-4 heart rate,
  59408-5 / 2708-6 oxygen saturation), the wearer is a `Patient`, the
  device a `Device`, an emergency becomes an `Encounter`/`Flag`. This
  mapping is a day of work and is fully real.
- **Demo target that works today:** the public HAPI FHIR test server
  (https://hapi.fhir.org/baseR4) accepts creates/searches with no auth.
  A judge can watch the app POST an Observation and read it back.
  Honesty requirements: it is a SHARED public sandbox, data is
  periodically purged, and it must never receive real patient data.
  Running your own local HAPI JPA server (open source, Apache 2.0) is
  the safer demo and equally real.
- **SMART on FHIR** is the authorization layer (OAuth 2.0 + OIDC, HL7
  SMART App Launch IG) that real EHRs (Epic, Oracle Health) require,
  with per-EHR app registration and review. A demo can demonstrate the
  SMART launch flow against a public SMART sandbox, but "shares data
  with their healthcare provider" in production means the provider's
  EHR must accept the app — partnership-gated, period.
- **Nutritionist and family:** there is no standard API on the other
  end. The honest implementation is role-based views of the same record
  (family dashboard, nutritionist summary view, exportable report) —
  genuinely buildable, and it should be described as exactly that, not
  as "integration with their nutritionist's system."

## 5. Demo feasibility without owning the hardware

The 2025 winner pattern (winners-research.md) is the guide: BlueKai
shipped to real devices PLUS a simulator and said so; rumorNet
disclosed a dormant agent rather than fake its output. Labelled
simulation beside one genuinely live path is the winning shape;
simulated data wearing a "live" costume is the losing one.

| Layer | Genuinely live by Dec 4 | Simulated (label it) |
|---|---|---|
| Vital stream | Gadgetbridge on one real cheap band (Mi Band / Amazfit class) if purchased or already owned; otherwise a standard BLE HR strap over 0x180D; phone carried as the "device" for GPS + accelerometer-driven fall input | A labelled "device simulator" replaying recorded/derived traces (e.g., a public dataset trace or a scripted vitals scenario) for the Garmin tier and for SpO2/temperature signals |
| Fall event | Phone accelerometer: a real drop/shake can drive a true sensor-triggered event on stage | Band-side fall (no raw accel exists) — the fall is injected via the simulator or the phone |
| Detection engine | REAL: thresholds/state machine run on whatever stream arrives; the code path is identical for live and simulated feeds | Nothing about the logic needs faking |
| Escalation | REAL: Twilio actually calls/texts the demo phones; Noonlight SANDBOX actually accepts the alarm and returns its ID/webhooks | Production dispatch (contract-gated, US-only) |
| Provider view | REAL: Observations actually POST to (local or public) HAPI FHIR R4 and are read back in a provider-shaped dashboard | Hospital EHR delivery (registration-gated) |

Minimum viable honest demo shopping list: one Android phone (Gadgetbridge
host + wearer device), one cheap supported band OR one generic BLE HR
strap, a Twilio trial account, a Noonlight developer sandbox token, a
local HAPI server. Purchase prices were not verified against primary
retailers in this pass (band/strap prices UNVERIFIED).

**Recommended demo architecture:** a Frankenstein stitch that leans
into the category: five incompatible data worlds (Garmin cloud shape,
Gadgetbridge BLE samples, a standard 0x180D strap, phone sensors, a
labelled trace simulator) normalized by Kiro-built adapters into one
FHIR-shaped event spine, one detection/escalation engine, four role
views (wearer, family, provider, nutritionist). The stitching IS the
Frankenstein claim, and every source is labelled live, fetched, or
simulated on screen.

## The single hardest technical blocker

**There is no live wire.** Every tier's data reaches a third party in
batches, not as a stream: Garmin's Health API delivers summaries after
the wearer syncs to Garmin Connect; cheap bands surrender periodic
fetched samples through a reverse-engineered bridge and no raw
accelerometer at all; the Google Health API is a sync API with
restricted scopes. An emergency detector fed on minutes-old, sync-gated
samples is a notification system with good intentions, not the
real-time guardian the concept pitches — and no partnership available
before Dec 4 changes that, because even Garmin's approved feed is
sync-based by design. The demo must therefore be built (and narrated)
as detection on the freshest data each tier can honestly give, with the
phone — the one device that has live sensors, GPS, and a voice line —
carrying the real-time layer.

## Sources (primary first)

- Garmin Health API + Program FAQ: developer.garmin.com/gc-developer-program
  (business use only; status within two business days; typical integration
  1-4 weeks; "Commercial use requires a license fee payment").
- Fitbit Intraday reference (case-by-case intraday; Personal type
  auto-granted): dev.fitbit.com/build/reference/web-api/intraday/.
- Google Health API and Fitbit Web API shutdown (turned off Oct 30 /
  Nov 2, 2026; restricted scopes; successor API): developers.google.com/health
  via integrator summaries of Google's pages (dates corroborated across
  multiple integrator docs; Google's own page states 410 Gone behavior).
- Gadgetbridge device/feature documentation: gadgetbridge.org (Zepp OS
  gadget page; Sleep as Android integration matrix; release notes).
- Bluetooth SIG Heart Rate Service 0x180D / 0x2A37 (adopted GATT profile).
- Zepp: no public cloud API; Zepp OS Mini Programs + partner API
  (zepp.com developer docs via integrator guide, developers.anpheros.com).
- Noonlight: docs.noonlight.com (Dispatch API quick start, sandbox
  endpoints, US-only coverage note); noonlight.com/resources/faq
  (pricing via sales; 30-90 day implementation).
- RapidSOS: rapidsos.com (partner/API model; no self-serve tier found).
- 47 CFR 64.1200(a)(1)(i) (autodialed/prerecorded calls to 911 lines).
- Quebec Civil Protection Act s. 20, LegisQuebec (prohibition on
  automatically connecting an alarm system to 9-1-1); Vancouver Bylaw
  7111 s. 24; Edmonton Alarm Systems Bylaw 10922 (fine for auto-calling
  devices dialing 911).
- HAPI FHIR public test server: hapi.fhir.org/baseR4 (open, shared,
  periodically purged); HL7 SMART App Launch IG (build.fhir.org).
