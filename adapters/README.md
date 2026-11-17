# Guardian adapters

Adapters are the seams between Guardian and the outside world. Each
file in this folder defines one **contract** (a small duck-typed
interface, documented with JSDoc typedefs) plus a **mock
implementation** for development and demos.

## Why plain JS + JSDoc instead of TypeScript

The whole project is plain Node/JavaScript with no build step, so the
engine and its tests run anywhere with `node` alone. TypeScript would
add a compile step and a toolchain dependency for zero runtime benefit
at scaffold stage. JSDoc typedefs keep the contracts explicit (and
editor-checkable) without the build. If the app grows native bridges
in a typed codebase later, these contracts port 1:1.

## The honesty rule (binding)

Every record an adapter returns carries a `source`. Real routes label
themselves (`healthkit`, `health_connect`, `ble-hr`). **Mock data is
always labelled `source: "simulated"`** — never presented as a real
reading, in any demo, screenshot, or write-up. This matters most for a
health product: staged vitals dressed up as real ones would be a lie
about the exact thing Guardian exists to be trusted with.

## The three contracts

| Adapter | File | Real route (on device) | Mock |
|---|---|---|---|
| Health store | `health-store.js` | Apple HealthKit / Android Health Connect read bridge: the vendor-neutral aggregation layer (Watch, Garmin, Fitbit, Samsung, most bands land here via the phone) | `MockHealthStoreAdapter` |
| BLE heart rate | `ble-hr.js` | Bluetooth Heart Rate Profile 0x180D / 0x2A37 subscription. Reliable on chest straps and some watches; most cheap wrist bands do not expose it outside workout mode | `MockBleHrAdapter` |
| Phone sensors | `phone-sensors.js` | Raw accelerometer stream + on-device fall-pattern detector + GPS. The real-time layer; only works with the phone on the person; iOS background limits apply | `MockPhoneSensorsAdapter` (with a `simulateFall()` rehearsal helper) |

## Deliberately not here yet

- Gadgetbridge-class band bridge (samples from Xiaomi/Amazfit-class
  bands): planned adapter, same Observation shape.
- Google Health API route for the Fitbit/Pixel mainstream.
- Camera PPG spot heart-rate: a stitch, not a foundation.
- The FHIR R4 writer (provider view): Observations map to FHIR R4
  `Observation` resources (LOINC-coded); lands with the provider
  surface, against a local/test HAPI server first.
