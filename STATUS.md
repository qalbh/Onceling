# Onceling — Status

**Phase 2 of 4 · Last updated: 2026-07-31**

**Now:** P2-29 — email/password sign-in flow

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
- [ ] **PI-05** A declined request must not tell the sender they were declined. It
      expires silently. Naming the refusal is unkind, and it confirms to a
      code-guesser that a real person owns that code.

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
- [ ] **P2-29** Email/password sign-in and sign-up flow. Wire the existing sign-in
      screen to `FirebaseAuth`. Loading, error and empty states on every path.
      *Precedes P2-08 — nothing else in Phase 2 works without a signed-in user.*
- [ ] **P2-30** Create `users/{uid}` on first sign-in — `displayName`, `avatarUrl`,
      `coupleId: null`, `favoriteEmojis`, `accentColor` (brief §9). Decide and record
      whether this is a client write protected by rules or an Auth-trigger Function.
      *Precedes P2-08 — the code generator needs somewhere to write.*
- [ ] **P2-08** Six-character code generation with a uniqueness lookup document
- [ ] **P2-09** `requestPairing(code)` callable — validates the code exists, refuses
      self-pairing and already-paired users, creates a `pairingRequests` document with
      status 'pending'. Rate limited (see **P2-27**).
- [ ] **P2-09b** `respondToPairing(requestId, accept)` callable — the transaction that
      matters. On accept: creates the couple, sets `coupleId` on both users, rejects
      every other pending request for both users, deletes both pairing codes. Atomic,
      idempotent, safe against two accepts landing simultaneously.
- [ ] **P2-09c** `cancelPairingRequest(requestId)` callable — sender-initiated,
      supports **P2-24**.
- [ ] **P2-10** Security Rules — all reads/writes scoped to the requester's `coupleId`.
      `pairingRequests` and `pairingCodes` both need rules in the same change that
      introduces them.
- [ ] **P2-11** Security Rules unit tests — negative cases on every collection: user A
      cannot read couple B's items, cannot read another user's document in
      `pairingCodes`, and cannot read another user's pending `pairingRequests`.
- [ ] **P2-12** Feed persistence with a real-time listener and pagination
- [ ] **P2-13** Photo upload to Cloud Storage. *Enable the Storage emulator first —
      until it is on, Functions calls to Cloud Storage hit the real dev bucket.*
- [ ] **P2-14** Migrate named routes → `go_router` with a single auth redirect
- [ ] **P2-15** Loading / empty / error states on every read
- [ ] **P2-16** Upgrade **dev** to Blaze; set a $5 budget alert.
      *Needed to deploy Functions. The emulator runs them locally on Spark, so
      build and test the P2-09 family (P2-09/09b/09c) first and upgrade only when you
      deploy.*
- [x] **P2-17** Unit tests for the mapper layer — round-trip every `FeedItem` subtype
      *21 tests: every subtype, null `mediaUrl`/`caption`, empty and multi-person
      reactions, until-closed duration, sealed vs opened, count > 1, unknown type
      and unknown duration both throw.*
- [ ] **P2-18** Unit tests for the pairing transaction — concurrent claim, double tap,
      self-pair, already-paired user. Plus the handshake races:
      two users accepting requests from each other simultaneously;
      accepting one request while another is being accepted for the same user;
      accepting a request whose sender paired with someone else in between;
      the same request accepted twice (double tap).
      *Highest-value test in the project.*
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
- [ ] **P2-23** Send-confirmation sheet — after entering a valid code, confirm before
      sending. Echoes the code back so a typo is catchable. Shows nothing about the
      code's owner: B must learn nothing about A before A accepts.
- [ ] **P2-24** Waiting state on the pairing screen — who the request went to, when,
      and a Cancel action. Until push lands (**P3-04**) it must say plainly that the
      partner sees it next time they open the app.
- [ ] **P2-25** Incoming request sheet — shows the sender's display name and avatar.
      Accept / Not now. Multiple pending requests render as a list; accepting one
      dismisses the others.
- [ ] **P2-26** Paired confirmation moment — full-screen, both sides, before the feed
      opens. Activation is brief §11's single most important metric.
- [ ] **P2-27** Rate limiting on `requestPairing`. Moved forward from **P3-05** because
      **P2-23**'s asymmetry means an attacker spraying requests at guessed codes learns
      a real user exists on every accept. **PI-05** covers the sender's side; only rate
      limiting covers the guessing. This is a **P2-09** dependency, not a later polish.
- [ ] **P2-28** Expire pending requests after 7 days. Scheduled Function. Expiry is
      timezone-independent — 7 days is 7 days — so this is **not** blocked by Q3 or by
      **P3-02**. It can share **P3-02**'s schedule if convenient, but does not require
      one.

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