# Steering: Verification Protocol (Guardian — binding)

No phase is done because code exists. A phase is done when its
claims survive verification, in order, with evidence.

## The gate (every phase in tasks.md)
1. **Tests green.** The phase's tests run and pass: engine state
   transitions (including cancel-at-every-stage), adapter contract
   tests with labelled fixtures, consent enforcement tests
   (revoked grant → share stops), FHIR write/read round trip.
2. **Log verifies.** After any end-to-end run, the hash-chained
   event log's verify() passes and the run's timeline is shown.
   A broken chain fails the gate regardless of what else worked.
3. **Live reproduction.** The phase's demo claim is performed
   once, start to finish, exactly as a judge would: drop test →
   window → cascade → sandbox payload/alarm → record read-back.
   "Worked in the unit test" is not the claim; the claim is the
   flow.
4. **Labels audited.** Every value shown in the run is checked for
   its source/freshness label (live / fetched + age / simulated).
   One unlabelled simulated value fails the gate.
5. **Prohibitions grepped.** The codebase is searched for direct
   emergency-number dialing, hardcoded credentials, and medical
   claim language. Any hit fails the gate until removed and
   explained in the result file.

## Evidence rules
- Result files (SESSION-N-RESULT.md) quote real command output and
  real IDs (sandbox alarm ID, FHIR resource IDs, log verify
  output). Paraphrase is not evidence.
- Failures stay in the record: a phase that failed its first gate
  says so, with the failure and the fix. Deleting a failure from
  the record is a protocol violation.
- Thresholds and demo tuning are committed in the open. A
  threshold adjusted to make the demo fire is disclosed in the
  result file with its before/after values.

## Stop-and-report triggers (any one: stop, write it up, tell John)
- A gate cannot be passed without faking a label, a log entry, or
  a result.
- A library or API seems to require a production credential, a
  real person's data, or a direct emergency call.
- Credit burn approaches the session guard (see SESSION-1.md and
  the pack README: one shared 4,000-credit grant, two entries).
