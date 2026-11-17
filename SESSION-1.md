# Guardian: Kiro Session 1 (paste-ready)

Goal of this session, and only this: the escalation loop proven end
to end against mock adapters, inside a real repo with the app shell
standing around it. One synthetic wearer, one simulated fall, both
endings (cancelled, and escalated), and an event log that verifies.
Roughly one sitting. Sensors, real channels, and FHIR polish are
later sessions.

Shared-credit warning before anything else: ONE 4,000-credit grant
funds BOTH Kiroween entries (GhostBridge flagship + Guardian).
Note the Kiro credit balance when you start and when you stop, and
put both numbers in SESSION-1-RESULT.md. Guardian's Session 1
guard: if this session's burn would push the COMBINED known burn
across both entries toward ~1,000 credits, stop at the next clean
checkpoint and flag it to Muse before continuing.

## Before you start (5 minutes, no Kiro yet)

- [ ] Kiro IDE or CLI open and signed in on your machine; credit
      balance screenshotted or noted (see the warning above).
- [ ] Node (current LTS), git, and the Flutter SDK installed
      (`node --version`, `git --version`, `flutter --version` all
      answer). Stack is Flutter, CONFIRMED by
      docs/ARCHITECTURE.md §1 — reconciliation done, no hedge.
- [ ] This pack (kiro-pack) on your machine, plus the Guardian
      project folder (guardian-app) complete: docs/, engine/,
      adapters/, LICENSE, README.md. The engine is COMPLETE and
      tested, pre-existing and DISCLOSED; do not rewrite it —
      integrate and verify it.
- [ ] NO Twilio account, NO Noonlight account, no credentials of
      any kind for this session. Session 1 is mock/sandbox-shape
      only (stop conditions below).

## Step 1: work in place in guardian-app (10 minutes)

Work IN PLACE in the existing `guardian-app` folder — the one
that already contains docs/, engine/, adapters/, LICENSE, and
README.md. Do NOT recreate the folder, and do not copy a subset
into a new one; pack, docs, and code already live together. In a
terminal inside guardian-app:

    git init            (skip if it is already a repo)
    git branch -M main

Session 1 ends at a LOCAL commit. Creating the public GitHub
repo is a separate step, taken only if John has pre-authorized
it; do not create it from inside this session.

(If a fresh clone or a rebuilt folder is ever used instead, the
copy list is exhaustive — nothing less counts as "the project":
docs/, engine/, adapters/, LICENSE, README.md, plus
kiro-pack/.kiro/ copied to ./.kiro/ at the root.)

## Step 2: install the /.kiro pack at the repo root

Copy the pack's .kiro directory to the REPO ROOT of guardian-app.
The working directory for the whole session is guardian-app/
(the repo root), and when this step is done it contains:

    guardian-app/               <- working directory / repo root
      .kiro/specs/guardian/       (from kiro-pack/.kiro/specs/guardian/)
      .kiro/steering/             (from kiro-pack/.kiro/steering/)
      .kiro/hooks/                (from kiro-pack/.kiro/hooks/)
      docs/  engine/  adapters/  LICENSE  README.md

Also copy kiro-pack/SESSION-1.md to the project root (reference),
and adapt .kiro/hooks/test-gate.json from its DRAFT shape to
Kiro's installed hook schema (tasks.md Phase 0).

Confirm `.kiro` is NOT in .gitignore. It must be committed: for
Kiroween judging, the /.kiro directory is evidence, not decoration.

## Step 3: orient Kiro (paste this first)

Paste into Kiro exactly:

> Read .kiro/specs/guardian/requirements.md,
> .kiro/specs/guardian/design.md, .kiro/specs/guardian/tasks.md,
> and all three files in .kiro/steering/ before writing any code.
> This project is Guardian: a free, open-source health guardian
> app (Android + iOS) for elderly people living at home, and our
> Kiroween 2026 Frankenstein entry. Binding rules from steering:
> Guardian NEVER dials 911 or any emergency number — dispatch is a
> monitored-partner interface (Noonlight class), sandbox only in
> the demo build. Simulated data is always labelled simulated.
> The wearer owns every share; the cancel window is always
> honoured. The escalation engine in engine/ is COMPLETE and
> tested (engine.js state machine, hash-chained event log,
> scheduler, notifier interface with mock implementations,
> dispatcher with a Noonlight-sandbox payload builder, dispatch
> disabled): it is disclosed pre-existing code — integrate and
> verify it, do not rewrite it. Confirm back to me: the
> components you will build in this session, in order, and the one
> design decision you are least sure about. Do not write code yet.

Check the reply names the engine integration and its test-suite
verification, the mock adapters, the app shell, and the log
verification. If it proposes
a direct emergency-call feature, real Twilio/Noonlight wiring, or
unlabelled demo data, point it back at steering once; if it
insists, stop the session and tell Muse (stop conditions below).

## Step 4: integrate and verify the existing engine, prove both endings (paste this second)

> Work Phase 1 of .kiro/specs/guardian/tasks.md. The engine in
> engine/ is complete and tested: integrate and verify it — do
> NOT build a new state machine.
> 1. First run the engine's own test suite (engine/test/) and
>    confirm it passes unmodified. Its states are the vocabulary
>    of this project: IDLE → TRIGGERED → CANCEL_WINDOW → CASCADE
>    → DISPATCH → RESOLVED. Every transition is already appended
>    to the hash-chained event log BEFORE its side effect.
> 2. Mock adapters only: a TraceSimulatorAdapter that emits a
>    simulated fall trigger (every record labelled
>    source=simulator, freshness=simulated), the engine's
>    MockNotifier for the cascade, and the engine's Dispatcher
>    with dispatch still DISABLED — the Noonlight-sandbox payload
>    is built and written to the log, never sent. No accounts, no
>    credentials, no network calls to Twilio or Noonlight.
> 3. A runnable end-to-end proof runner that executes BOTH
>    endings and prints the evidence:
>    (a) fall → wearer cancels inside the cancel window → the
>        engine returns to IDLE, the cancellation is in the log;
>    (b) fall → window lapses → one ordered cascade pass over
>        the kin contacts (per-contact acknowledgment timeout,
>        default 120s) → cascade exhausted with no acknowledgment
>        → DISPATCH: sandbox payload built and logged, never
>        sent → RESOLVED.
>    After each run, call the event log's verify and print its
>    result. The runner also EXPORTS both episodes' event logs
>    to guardian-app/proofs/episode-log.json (one JSON file,
>    both runs, each labelled cancelled / escalated, exported
>    from the engine's event log) — the app shell in Step 5
>    renders THAT file; that export is the log bridge. Create
>    proofs/ if it does not exist.
> Check off the tasks.md Phase 1 bullets you complete, in
> tasks.md itself.

## Step 5: stand up the app shell (paste this third)

> Scaffold the app shell per design.md (Flutter, CONFIRMED by
> docs/ARCHITECTURE.md §1): a wearer home screen with one huge
> "I'm OK" button and a "I need help" button, a cancel-window
> screen with a visible countdown, and an episode timeline
> screen that renders guardian-app/proofs/episode-log.json —
> the file the Step 4 proof runner exported from the engine's
> event log — showing the two proof episodes (cancelled and
> escalated) with every value labelled by source and freshness.
> Wire the shell to the engine through the mock adapters only.
> Screens must render the honest-limits line from the spec:
> "Demo build — dispatch is a sandbox; Guardian never calls 911
> directly." Keep it a shell: no sensor code, no health store
> code, no real channels yet.

## Step 6: close out (paste this last)

> Commit everything, including .kiro, with a message summarizing
> session 1, and write a short SESSION-1-RESULT.md: what was
> built, the end-to-end proof output verbatim (both endings, with
> the event-log verify results), which tasks.md bullets are
> checked, the Kiro credit balance at session start and stop
> (Guardian shares one 4,000-credit grant with the GhostBridge
> entry), and every gap or stub you already know about. No silent
> stubs: list them. State explicitly that no real Twilio or
> Noonlight account, credential, or network call was used.

## What "done" looks like for Session 1
- Repo with .kiro committed (specs + steering + adapted hook)
  and NOT gitignored; the existing engine integrated and its
  test suite passing unmodified, not rewritten.
- Both proof endings run and print: cancelled episode returns the
  engine to IDLE with the cancellation logged; escalated episode
  runs one cascade pass in wearer order, exhausts it, and reaches
  DISPATCH with the sandbox payload built (never sent) before
  resolving.
- Event log verify passes after both runs, output quoted in
  SESSION-1-RESULT.md; proofs/episode-log.json exported.
- App shell renders the wearer home, cancel-window countdown, and
  episode timeline (from proofs/episode-log.json) with
  source/freshness labels and the honest-limits line.
- SESSION-1-RESULT.md written: gaps listed, credit start/stop
  balances recorded, no-credentials statement present.
- Then: the session ends at a LOCAL commit (push only if John
  pre-authorized creating the GitHub repo), and send Muse the
  result file (paste it in chat). Muse reviews before Session 2.

## Stop conditions (any one: stop, save, tell Muse)
- **Any real Twilio or Noonlight account, credential, or network
  call is proposed or needed.** Session 1 is mock/sandbox-shape
  only. Production or trial wiring is a later, separately
  reviewed step.
- **Any direct emergency-number dialing appears** — a feature, a
  library default, a code path. That is prohibited by design and
  by law; remove it and report it, do not route around it.
- Kiro proposes unlabelled simulated data, a medical/diagnostic
  claim, or a share that bypasses wearer consent, and does not
  correct after one pointer back to steering.
- The cancel window can be bypassed or overridden by any code
  path Kiro writes. That invariant is the product; stop and
  report rather than patch quietly.
- **Credit burn:** this session's usage would push the combined
  known burn across BOTH entries toward ~1,000 of the shared
  4,000 grant, or the session runs past one sitting: commit what
  exists, write the result file with the balances, stop.
- Anything asks you to edit a test, a log entry, or a label to
  make a run pass. That is never the fix in this project.
