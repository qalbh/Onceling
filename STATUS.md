# Onceling — Status

**Phase 2 of 4 · Last updated: 2026-07-31**

**Now:** P2-10 / P2-11 — the remaining Security Rules and their emulator tests

---

## How to maintain this file

Read this before editing. Applies to Claude Code and to me.

- **Update this file in the same change that completes the work**, not afterwards.
  A task is not done until its box is ticked here.
- Tick `- [ ]` → `- [x]`. Do not delete completed tasks — the record is useful.
- Update **Last updated**, the **Phase** line, and **Now** whenever you tick anything.
- When a task turns out to be bigger than one line, split it into sub-tasks rather
  than leaving it half-ticked.
- If work reveals a new task, add it under the right section with the next free ID.
- **Task IDs freeze at first commit.** Never renumber after that. Retired tasks move
  to **Cut** with their ID intact.
- Move an item out of **Built on mock data** only when it is backed by real
  persistence, not when the UI merely looks right.
- Do not mark a **Decision** resolved on the user's behalf. Those are theirs alone.
  If the code implies an answer, note it — don't tick it.
- Scope decided *against* goes in **Cut** with a one-line reason, not ticked as done.

---

## Phase status

- [x] **Phase 1 — UI with mock data**
- [ ] **Phase 2 — Firebase, auth, pairing, persistence** ← current
- [ ] **Phase 3 — Cloud Functions, deletion, streaks, push, onboarding**
- [ ] **Phase 4 — Home widget, polish, store submission**

> **Gate:** no external testers — TestFlight or Play internal — until **PI-02** ships.
> Brief §10 requires the honesty disclosure before anyone outside uses the app.

---

## Decisions — blocked on the owner

Nothing below is code. Each one changes what gets built. Phase 3 should not start
until Q1, Q2 and Q3 are answered.

- [ ] **Q1** Hard delete or short encrypted retention for opened secrets?
      *Code currently assumes hard delete — `markOpened()` drops the body.*
- [ ] **Q2** Are streaks in, and if in, are they forgiving?
      *Currently in and unforgiving. Brief §12 flags coercion risk.*
- [ ] **Q3** One couple timezone, or per-device? *Blocks the streak Function.*
- [ ] **Q4** Any monetisation intent? *Decides whether trademark checks matter.*
- [ ] **Q5** Export on unpair, or destroy? *Unpair copy promises total erasure.*

---

## Product integrity

Flagged in review. Small, keeps getting deferred because none of it is code.

- [ ] **PI-01** Resolve the "Screenshot alerts" toggle — it implies a detection
      capability the product cannot deliver. Rename or remove. See brief §10.
- [ ] **PI-02** Write the §10 honesty disclosure into onboarding. The brief requires
      stating plainly that the one-time open is a trust ritual, not a guarantee.
      It does not currently exist anywhere in the app. **Gates external testing.**
- [ ] **PI-03** Decide whether "Mood nudges" stays — it is not in brief §6.
- [ ] **PI-04** Re-upload the updated brief to the Claude project.
- [ ] **PI-05** A declined request must never tell the sender they were refused. It
      surfaces as 'expired' — the same status the 7-day timeout writes. The sender
      learns the answer is no; they are never told a person said no.
      *Reconsidered after the P2-09 audit: this is a kindness rule, not a security
      one. `requestPairing` returns a distinct error for a non-existent code, so an
      enumerator learns a code is real the moment a request succeeds — decline
      silence adds nothing. Rate limiting (P2-27) is the whole defence. The competing
      harm is leaving a sender waiting 7 days on an answer that arrived in 30
      seconds.*
      *Timing is not hidden and that is deliberate: 'expired' arriving in 30 seconds
      versus 7 days does imply a decline. The trade is accepted — leaving a sender
      waiting a week on an answer that arrived in seconds is the worse harm, and the
      security rationale for silence does not survive P2-09 returning a distinct error
      for a non-existent code.*

---

## Built on mock data

Looks finished, backed by nothing. This is the real Phase 2 worklist.

- [ ] **M-01** Feed — `sampleThread()` hardcoded → Firestore collection
- [ ] **M-02** Users — `Person` enum (`maya`, `devon`) → real accounts and profiles
- [ ] **M-03** Pairing — `myCode = 'MK4Q7B'`, `_canPair` only checks `length == 6`
- [ ] **M-04** Share link — toast stub → deep link generation and handling
- [ ] **M-05** Secrets — `markOpened()` deletes client-side; must move to a Function
- [ ] **M-06** Streaks — hardcoded `47` in two places
- [ ] **M-07** Mood — local state only, no push to partner
- [ ] **M-08** Reactions — singular `reaction` on two types; brief §9 wants plural on all
- [ ] **M-09** Auth — none

---

## Phase 2 — Firebase

Order matters. Pairing before feed: the feed is easier and will tempt you first, but
pairing is the invariant the product rests on and is far cheaper to get right before
there is data.

- [x] **P2-01** Enable Firestore on dev — `asia-south1`, production mode
- [x] **P2-02** Enable Email/Password auth
      *Google provider also enabled; public-facing name set to Onceling.*
- [x] **P2-03** Add `lib/firebase_options*.dart` to `.gitignore` **before** generating
      *`google-services.json` and `GoogleService-Info.plist` gitignored too.*
- [x] **P2-04** `flutterfire configure --project=qalb-coupleapp-dev`
      *Android and iOS apps registered; `lib/firebase_options_dev.dart` generated
      (gitignored).*
- [x] **P2-05** Install and run the Local Emulator Suite (Firestore, Auth, Functions)
      *Auth 9099, Functions 5001, Firestore 8080, UI 4000. Functions scaffolded in
      TypeScript. `firestore.rules` and `firestore.indexes.json` created and
      registered.*
- [x] **P2-06** Mapper layer — sealed `FeedItem` ⟷ flat `items` document (brief §9)
      *`time: String` → `createdAt: DateTime`; `Person` deleted in favour of
      `senderId`; `placeholder` → `mediaUrl`; singular `reaction` → `reactions`
      map on all five types; `SecretMessage.body` and `markOpened()` removed —
      bodies live in `secretBodies/`, deletion is **P3-01**. No `isSecret` field:
      `type` carries that fact alone.*
- [x] **P2-07** Add Riverpod (no codegen initially); auth and couple providers
      *`firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions`,
      `flutter_riverpod` added. `main()` initialises Firebase and wraps the app in
      `ProviderScope`; `_connectToEmulators()` points the SDKs at the suite under
      `kDebugMode` only. `lib/common/providers.dart` has auth, Firestore and
      `authStateProvider` — the couple provider waits for the pairing model.
      iOS deployment target 13.0 → 15.0, required by the Firebase iOS SDK.*
- [x] **P2-29** Email/password sign-in and sign-up flow. Wire the existing sign-in
      screen to `FirebaseAuth`. Loading, error and empty states on every path.
      *`EmailAuthSheet` behind "Use email or phone"; sign-in and sign-up in one
      sheet. Apple and Google now render disabled — the UI stays, the providers
      wait for P2-19/P2-20. Sign-out sits in settings. Nothing navigates on
      success; auth gating is P2-14. `AuthFailure` carries a human message, never
      a FirebaseAuthException code.*
- [x] **P2-30** Create `users/{uid}` on first sign-in — `displayName`, `avatarUrl`,
      `coupleId: null`, `favoriteEmojis`, `accentColor` (brief §9).
      *Check-then-create, so signing in again never clobbers. `currentUserProvider`
      streams the document off `authStateProvider`. Rules for `users/{uid}` shipped
      in the same change; auditor scored 4.*
      *Client write, protected by rules — not an Auth trigger. The rule preventing a
      user from setting their own `coupleId` is required either way, since P2-09b's
      transaction is the only thing allowed to set it. Once that rule exists the
      trigger buys nothing, and it would need Blaze (P2-16) to deploy, meaning
      development against something unshippable.*
      ***Superseded by P2-35.** The write is now the `ensureUserProfile` callable —
      neither a client write nor an Auth trigger. The reasoning above still holds
      against an Auth trigger, but "protected by rules" no longer describes this
      path: `allow create` is closed and the Admin SDK bypasses rules, so the
      function is the only validator. The headline's `coupleId: null` is also only
      true for a genuinely new account — a recreated profile restores the real one.*
      *Precedes P2-08 — the code generator needs somewhere to write.*
- [x] **P2-08** Six-character code generation with a uniqueness lookup document
      *`ensurePairingCode()` callable, idempotent — returns the existing code
      rather than regenerating. Alphabet drops 0/O/1/I/L because codes get read
      aloud and typed by hand. Claims `pairingCodes/{code}` with transaction
      create semantics so a collision fails instead of stealing an owner;
      retries up to 10, then resource-exhausted.*
- [x] **P2-09** `requestPairing(code)` callable — validates the code exists, refuses
      self-pairing and already-paired users, creates a `pairingRequests` document with
      status 'pending'. Rate limited (see **P2-27**).
      *Six rejections, each with a distinct `details.reason`; success returns
      `{requestId}` and nothing else, so B learns nothing about A (**P2-23**).*
- [x] **P2-09b** `respondToPairing(requestId, accept)` callable — the transaction that
      matters. On accept: creates the couple, sets `coupleId` on both users, rejects
      every other pending request for both users, deletes both pairing codes. Atomic,
      idempotent, safe against two accepts landing simultaneously.
      *One transaction, all reads before all writes; the stale-request sweep uses
      `transaction.get(query)`. Five preconditions with distinct `details.reason`,
      plus a self-pair guard `requestPairing` already covers but a forged document
      would not. Double tap returns the existing `coupleId` instead of throwing.
      `couples/{coupleId}` rules landed in the same change — members read, no client
      write at all; auditor scored 5/5.*
      *`anniversaryDate` and `timezone` are written null and left open: neither has an
      owner decision, and inventing a default would bake in an answer nobody chose.
      `timezone` is **Q3**, which blocks **P3-02**.*
      *Neither expire path writes `settledAt`. A timestamp on an expired request is a
      timing oracle — 'expired' seven days after `createdAt` is **P2-28**'s sweep,
      'expired' twenty minutes after is a person having decided, which is exactly what
      **PI-05** withholds. A sender holding a live listener still sees the moment it
      changes; that much is unavoidable.*
      *Auditor minor from P2-09: a declined request must not become a read
      oracle. Rules let the sender read their own request, so writing
      `status: 'rejected'` would tell them they were declined — exactly what
      **PI-05** forbids.*
      Decline must not write `'rejected'` — the sender can read their own request and
      would learn they were refused. Write `'expired'`, the same status the 7-day
      timeout (**P2-28**) writes, and surface it to the sender immediately. Do not use
      `'cancelled'` — **P2-09c** writes that, so a sender who did not cancel would
      infer a decline.
- [x] **P2-09c** `cancelPairingRequest(requestId)` callable — sender-initiated,
      supports **P2-24**.
      *Only `fromUid`, only while pending; sets status to 'cancelled'.*
- [ ] **P2-10** Security Rules — all reads/writes scoped to the requester's `coupleId`.
      `pairingRequests` and `pairingCodes` both need rules in the same change that
      introduces them. The `users` rule must allow a user to create and update their
      own document while forbidding any client write to `coupleId` — that field is set
      only by the **P2-09b** transaction and cleared only by unpair.
      The `coupleId` restriction cannot be a flat field-level deny. Firestore rules
      evaluate whole-document writes, so the rule must compare incoming against
      existing: permit an update where `coupleId` is unchanged, reject one where it
      differs. On create it must be null. A flat deny blocks legitimate profile edits
      that happen to include the field, and `displayName` updates silently stop
      working.
- [ ] **P2-11** Security Rules unit tests — negative cases on every collection: user A
      cannot read couple B's items, cannot read another user's document in
      `pairingCodes`, and cannot read another user's pending `pairingRequests`.
      A signed-in user writing `coupleId` to their own document must be **rejected**,
      not merely absent from the happy path. Same for clearing it — an unrestricted
      clear lets a client orphan a couple, leaving one partner paired to nobody and
      the other paired to a ghost. Both directions need a failing-write test.
      Include a **passing** case alongside the two failing writes: a user updating
      their own `displayName` while `coupleId` is present and unchanged must succeed.
      Without it, an over-strict rule passes the negative tests and breaks the app.
- [ ] **P2-12** Feed persistence with a real-time listener and pagination
- [ ] **P2-13** Photo upload to Cloud Storage. *Enable the Storage emulator first —
      until it is on, Functions calls to Cloud Storage hit the real dev bucket.*
- [x] **P2-14** Migrate named routes → `go_router` with a single auth redirect
      *`resolveRedirect()` in `lib/common/app_router.dart` is the whole gate, a
      pure function: loading → splash (never a sign-in flash), signed-in with no
      profile document → still splash (the sign-up write race), then coupleId
      routes pairing vs feed. Splash owns a 6s timeout with retry. Riverpod
      drives `refreshListenable`, so setting `coupleId` in the Emulator UI moves
      the app live. Sheets stayed sheets; the secret reveal became a route.
      Unpair's mock path now lands on pairing, not sign-in — a signed-in user
      cannot reach sign-in, the gate bounces them.*
- [ ] **P2-15** Loading / empty / error states on every read
- [ ] **P2-16** Upgrade **dev** to Blaze; set a $5 budget alert.
      *Needed to deploy Functions. The emulator runs them locally on Spark, so
      build and test the P2-09 family (P2-09/09b/09c) first and upgrade only when you
      deploy.*
- [x] **P2-17** Unit tests for the mapper layer — round-trip every `FeedItem` subtype
      *21 tests: every subtype, null `mediaUrl`/`caption`, empty and multi-person
      reactions, until-closed duration, sealed vs opened, count > 1, unknown type
      and unknown duration both throw.*
- [x] **P2-18** Unit tests for the pairing transaction — concurrent claim, double tap,
      self-pair, already-paired user. Plus the handshake races:
      two users accepting requests from each other simultaneously;
      accepting one request while another is being accepted for the same user;
      accepting a request whose sender paired with someone else in between;
      the same request accepted twice (double tap).
      *Highest-value test in the project.*
      *`rules-tests/pairing_concurrency.test.mjs`, 15 tests. Each race loops 20 rounds
      against fresh Firestore state. Every test ends in `assertPairingInvariant()`:
      no user's `coupleId` points at a couple whose `memberIds` omit them, and no
      couple lists a member whose `coupleId` points elsewhere.*
      *All four races were proven sharp by sabotage — neutering a precondition in
      `functions/src/` and confirming the matching race fails. Races 1 and 2 are
      backstopped by contention on the sweep query's read set, so they only fail once
      that is removed too; race 4 needs the not-pending guard gone as well. Worth
      recording: the preconditions are not the only thing holding the invariant up.*
- [x] **P2-33** *(done in this change)* Emulator seed script — five test users with
      profiles and pairing codes, idempotent, `--reset` supported, refuses to run
      against a non-emulator target.
      *`tools/seed-emulator.mjs`, run with `cd tools && npm run seed`. Codes are
      claimed by calling `claimPairingCode` — the same function `ensurePairingCode`
      wraps — so seeded state is indistinguishable from a real user's.*
- [ ] **P2-19** Google sign-in wiring — SHA-1 and SHA-256 fingerprints registered in
      Firebase (Android), reversed client ID as URL scheme in `Info.plist` (iOS),
      `google_sign_in` package. The provider is already enabled in the console with
      the public-facing name set to Onceling; only the platform config and client
      code remain.
- [ ] **P2-20** Sign in with Apple — required by App Store Review Guideline 4.8 once
      Google sign-in ships. Needs a paid Apple Developer Program membership for the
      Services ID and key. The sign-in screen already has the button.
- [ ] **P2-21** Platform-branch the emulator host — Android emulators need `10.0.2.2`,
      not `localhost`. Blocks any Android testing against the emulator.
- [ ] **P2-22** Replace the duck-typed `toDate()` in `feed_item_mapper.dart` with a
      real `Timestamp` cast now that `cloud_firestore` has landed. Update mapper tests.
- [x] **P2-23** Send-confirmation sheet — after entering a valid code, confirm before
      sending. Echoes the code back so a typo is catchable. Shows nothing about the
      code's owner: B must learn nothing about A before A accepts.
      *`code-not-found`, `owner-already-paired` and `rate-limited` share one
      sentence, asserted by a test. Giving them distinct copy would rebuild in the
      UI the enumeration oracle the callable deliberately removed.*
- [x] **P2-24** Waiting state on the pairing screen — who the request went to, when,
      and a Cancel action. Until push lands (**P3-04**) it must say plainly that the
      partner sees it next time they open the app.
      *`outgoingRequestProvider` is unfiltered by status on purpose: filtering to
      pending would make a settled request vanish rather than answer. The expired
      copy is "No answer yet"; a test asserts the words declined/reject/refused
      never reach the screen (**PI-05**).*
- [x] **P2-25** Incoming request sheet — shows the sender's display name and avatar.
      Accept / Not now. Multiple pending requests render as a list; accepting one
      dismisses the others.
      *The name is denormalised onto the request by `requestPairing`
      (`fromDisplayName`, `fromAvatarUrl`) rather than read from the sender's
      profile. Widening the users read rule was considered and rejected: rules
      cannot run queries, so "anyone with a pending request to me" is inexpressible
      and the only rule that compiles is "any signed-in user reads any profile" —
      an enumerable account directory. Both fields are bounded and defaulted
      server-side: they are user-controlled text crossing to another person.
      The name is a **snapshot** from send time and does not follow a later
      rename — that is what the request was sent under.*
- [x] **P2-26** Paired confirmation moment — full-screen, both sides, before the feed
      opens. Activation is brief §11's single most important metric.
      *A `/paired` route the gate permits, armed by `pairingCelebrationProvider`
      watching the profile stream for coupleId going null → non-null. A transition
      detector rather than a flag on the Accept button, because only one partner
      taps anything — B's coupleId changes with no local action, and watching the
      stream is the one mechanism that fires for both sides. "Once and never again"
      rests on *did this session watch coupleId appear*, not *is there a coupleId*,
      so a cold start on a paired account routes straight to the feed. A missing
      profile document is explicitly not treated as unpaired, or every cold start
      would arm it.*
- [x] **P2-27** Rate limiting on `requestPairing`. Moved forward from **P3-05** because
      **P2-23**'s asymmetry means an attacker spraying requests at guessed codes learns
      a real user exists on every accept. **PI-05** covers the sender's side; only rate
      limiting covers the guessing. This is a **P2-09** dependency, not a later polish.
      *5 requests per uid per hour, fixed window, counted in `rateLimits/{uid}`
      with no client access. Budget is spent *before* validation, so failed
      probes are not free and an exhausted caller gets the same
      resource-exhausted answer whether the code exists or not — no oracle.*
- [ ] **P2-28** Expire pending requests after 7 days. Scheduled Function. Expiry is
      timezone-independent — 7 days is 7 days — so this is **not** blocked by Q3 or by
      **P3-02**. It can share **P3-02**'s schedule if convenient, but does not require
      one.
- [x] **P2-34** The splash error state has no escape. A signed-in user whose profile
      document is missing sees only a retry, and retry cannot help if the P2-30 write
      never landed — the document does not exist to appear. The user is stuck until
      they delete the app. Add a sign-out action to that screen, and consider offering
      to re-run the profile write. Encountered twice during development with a working
      write path; a user whose write actually failed has no recovery.
      *Both actions shipped. "Set up my profile" calls `AuthService.recoverProfile()`,
      which re-runs `_settleProfile` for the current user — the same write `signIn`
      already performs on every sign-in, and `ensureProfile` returns an existing
      document untouched rather than clobbering it. Sign-out is always present as the
      fallback, because it is the only recovery that does not depend on the server
      doing anything.*
      *Copy branches on the actual failure: a resolved-but-absent profile reads
      "We couldn't finish setting up your account", not "Check your connection",
      which is wrong and misleading when the network is fine.*
- [x] **P2-35** `ensureProfile` recreates a missing profile with `coupleId: null`,
      which is wrong for a user who is still a member of a couple. The result is the
      exact incoherent state `assertPairingInvariant` exists to catch: `couples/{id}`
      lists them, their own `coupleId` is empty. Worse, it is recoverable-looking —
      the gate routes them to pairing, `ensurePairingCode` succeeds because their
      profile now reads unpaired, and they can join a *second* couple. Every
      precondition passes because each reads the profile that is lying.
      Not client-reachable (rules deny profile deletes) and not new — sign-in has
      always done this — but **P2-34** put a button on it.
      *The fix could not go where it was first scoped. `ensureProfile` was
      client-side Dart, and probes showed a client can neither query `couples`
      (`list` is false, so it cannot discover its own membership) nor write
      `coupleId` — the rule CLAUDE.md calls non-negotiable. So the write moved:
      `ensureUserProfile` in `functions/src/profile.ts` is now the only writer of a
      profile document, for new accounts as well as recovery.*
      *Three cases: in a couple restores that `coupleId`; in none writes null; in
      more than one logs the uid and both couple ids and refuses, because picking
      one would turn a detectable inconsistency into a permanent invisible wrong
      answer. Existing profiles return before the couples query, so the extra read
      is only paid on the create path — proven by a test that would throw
      `multiple-couples` if the query ran.*
      *`allow create` on `users` is now closed (auditor 5/5, 11 red-team probes).
      That moved three create-only guarantees onto the function, which satisfies
      them by construction rather than validation — it writes a fixed literal, so
      no caller-supplied key reaches the document. Nine tests pin them.*
      *No index needed: a single `array-contains` filter with no other filter or
      `orderBy` uses the automatic single-field index. `firestore.indexes.json` is
      untouched.*
- [ ] **P2-36** Unpair. The settings screen has an unpair sheet with typed
      confirmation (Phase 1 UI), but nothing behind it. A paired user currently cannot
      separate. Needs a callable that clears `coupleId` on both users server-side —
      per CLAUDE.md, an unrestricted clear is as dangerous as an unrestricted set,
      because it orphans a couple. Must be atomic and idempotent, and must decide what
      happens to `couples/{id}`, `items`, and `secretBodies`. Blocked on **Q5**
      (export or destroy).
- [ ] **P2-31** Validate `favoriteEmojis` element contents. The rule bounds the list
      to 8 entries but Firestore rules have no per-element expression — a 200KB string
      in one entry was accepted under probe. Self-scoped and capped by the 1MiB
      document limit, so it only damages the writer's own row. Mitigate in the client
      and in a Function. *Auditor minor, P2-29.*
- [ ] **P2-32** Email verification flow. `firestore.rules` deliberately does not
      require `email_verified` — there is no verification flow, so requiring it would
      break sign-up. Revisit before **P2-19** and **P2-20**. *Auditor minor, P2-29.*
      Sequencing matters: **P2-19** and **P2-20** bring providers that verify email
      addresses themselves, so Google and Apple accounts arrive with `email_verified`
      already true. Shipping either one creates two classes of account — provider
      accounts verified, email/password accounts not — while `firestore.rules` treats
      them identically. That is the moment the deliberate omission stops being
      harmless. Resolve P2-32 before whichever of P2-19/P2-20 ships first.

---

## Phase 3 — Functions, push, onboarding

- [ ] **P3-01** Secret deletion Function — hard delete `secretBodies`, keep the
      tombstone in `items`
- [ ] **P3-02** Streak calculation Function *(needs Q3)*
- [ ] **P3-03** Milestone triggers — day 100, 365, 500, 1000 *(needs Q2)*
- [ ] **P3-04** FCM fan-out — secret payloads carry no body and no preview
- [ ] **P3-05** Rate limiting on any future secret-bearing check. *The pairing half
      moved forward to **P2-27** — it is a **P2-09** dependency, not later polish.*
- [ ] **P3-06** Composite indexes; keep `firestore.indexes.json` in sync
- [ ] **P3-07** Onboarding flow *(includes PI-02 — gates external testing)*

---

## Phase 4 — Ship

- [ ] **P4-01** Home screen widget (native, both platforms)
- [ ] **P4-03** Store submission prep — app icon, launch screen, listings,
      screenshots, privacy policy
- [ ] **P4-05** Crashlytics
- [ ] **P4-06** Upgrade **prod** to Blaze; set a budget alert
- [ ] **P4-07** TestFlight → Play internal test *(gated on PI-02)*
- [ ] **P4-08** Enable App Check (Play Integrity + App Attest) before store
      submission. Attests requests come from the genuine app binary. Complements
      Security Rules; does not replace them.

---

## Known debt

Non-blocking. Fix when convenient.

- [ ] **D-01** `PlusJakartaSans-SemiBold.ttf` bundled but never bound — ~200KB dead
      weight; `labelSmall` asks `w600` and gets synthetic-on-Regular
- [ ] **D-02** 20 distinct font sizes across six near-duplicate clusters
      (12/12.5, 13/13.5, 14/14.5, 15/15.5, 16/16.5) — parked for a design pass
- [ ] **D-03** ~1% residual on button label glyphs vs pre-refactor baseline
- [ ] **D-04** `assets/images/` declared in `pubspec.yaml`, contains only `README.md`
- [x] **D-05** `dart format` drift on 16 files from the theming refactor
- [ ] **D-06** `delivered` dropped from `TextMessage` and `SecretMessage` during
      **P2-06**. The "· Delivered" suffix no longer renders. Restore as real server
      state at **P2-12**.
- [ ] **D-07** `flutter_riverpod` resolved to 2.6.1; 3.x reports incompatible with
      current constraints. The 2.x API covers everything needed, but investigate the
      constraint before the codebase gets large.
- [ ] **D-08** `@firebase/app` pinned in `functions/` to work around a broken peer
      dependency in `firebase-admin@13.6.0`. Recheck on the next upgrade.
- [ ] **D-09** `rules-tests/` carries its own Node toolchain (86 packages).
      `@firebase/rules-unit-testing` peer-requires `firebase@^11`, not 12. Working,
      but the mismatch will surface on upgrade.
- [ ] **D-10** The `fromUid`+`toUid`+`status` composite index for the duplicate-check
      query is declared in `firestore.indexes.json` but untested — the emulator does
      not enforce indexes. Verify against dev before **P2-16**.
- [ ] **D-11** The accept transaction's correctness rests partly on incidental
      mechanisms. Sabotage testing at **P2-18** showed the stale-request sweep's
      `transaction.get(query)` provides the contention that aborts concurrent
      accepts, and the not-pending guard independently catches double-tap. Neither
      was designed for that. Any refactor that moves the sweep out of the transaction
      removes a correctness mechanism while leaving every test green. Warning comment
      is at the call site.
- [ ] **D-12** `ensureUserProfile` absorbs an ALREADY_EXISTS race by re-reading and
      reporting the winner's document. `.create()` was kept over `.set()` deliberately
      — `set` would clobber a document written between the existence check and the
      write. Recheck if the function's read/write shape changes.

---

## Cut

Scope decided against. Recorded so it doesn't get re-litigated.

Format: `**ID** Description — reason, date`

**P4-02** Onboarding flow — moved to P3-07, since PI-02's honesty disclosure gates
external testing and must ship before Phase 4. 2026-07-31

**P4-04** Store listings and screenshots — merged into P4-03 to keep Phase 4 legible
until submission is close. 2026-07-31

---

## Shipped

Phase 1. Kept as a record — do not delete.

- [x] Eight screens and sheets: sign-in, pairing, feed, compose, mood, secret reveal,
      settings, unpair
- [x] Fourteen supporting widgets
- [x] Theme system — `ColorScheme` + `ThemeColors` (27) + `ThemeGlyphs` (11), light
      and dark, shared `_textTheme` builder so metrics cannot drift
- [x] Fonts bundled; `allowRuntimeFetching = false`
- [x] `Glyph` widget pinning `TextScaler.noScaling` for chrome glyphs
- [x] Zero hardcoded colors or inline `TextStyle` outside `lib/theme/`
- [x] `flutter analyze` clean; 24 tests passing
- [x] Six-item code audit passed 6/6
- [x] Accessibility pass — 200% text scale, 360dp, landscape, dark mode
- [x] Name decided: Onceling; identifiers deliberately neutral
- [x] `CLAUDE.md` written
- [x] Git history clean, no AI attribution, pushed to GitHub
- [x] Firebase dev and prod projects created, Google Analytics disabled