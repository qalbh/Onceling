# Onceling — Status

**Last updated: 2026-08-08**

## Now

**P2-28** — expire pending pairing requests (7 days, scheduled).

## At a glance

**Phase 3 of 4** · **49 open · 55 done**
Blocked on money: **4** — P2-20 (Sign in with Apple), P4-06 (prod Blaze), P4-07
(TestFlight), P4-09 (APNs key) — all the same paid Apple Developer account except
P4-06, which is a billing plan.
Blocked on hosting: **1** — M-04 (share link needs `onceling.app` served; decisions
recorded in its entry).
Before a tester can use it: **2** — P4-07 (the distribution channel itself) and
P4-10 (release-keystore SHA registration, without which Google sign-in fails in
exactly the build a tester would install). Android/Play-internal path; TestFlight
adds the money items above.

## Next three

1. **P2-28** Expire pending requests (7 days, scheduled) — PI-05's guarantee rests
   on it: a declined request must be indistinguishable from an expired one, which
   requires expiry to exist.
2. **P2-38** Backstop sweep for couples stuck at `status: 'unpaired'` — it shares
   P2-28's schedule, so building them together costs one scheduled function, not
   two, and closes the sweep gap P2-36's entry records.
3. **D-28** Prove the orphan half of the photo sweep on dev, with throwaway
   accounts — the one place "destroy everything" is still unproven, and brief §10
   and Q5 both hang on it. Test plan already written in the entry.

<!--
  The counts above are COMPUTED, not remembered: `tools/status-counts.sh`
  prints them, and `tools/status-counts.sh --check` exits non-zero if this
  dashboard disagrees with the file. Run the check before committing any tick.
  The blocked lists are judgment, not grep: confirm the entries they name still
  say what this summary claims before repeating them.
-->

---

## How to maintain this file

Read this before editing. Applies to Claude Code and to me.

- **Update this file in the same change that completes the work**, not afterwards.
  A task is not done until its box is ticked here.
- Tick `- [ ]` → `- [x]`. Do not delete completed tasks — the record is useful.
- Update **Last updated** and the dashboard's **Now** whenever you tick anything.
- **Update the dashboard with every tick, same as Last updated.** It is the first
  thing the owner reads, and a stale one is worse than none. Run
  `tools/status-counts.sh --check` before committing any tick — a number nobody
  recomputes is a number that drifts, and the check exits non-zero when the
  dashboard has. Re-read the *Next three* while there: ticking something usually
  changes what comes next.
- When a **debt item** is closed, tick it and move its whole entry to
  `docs/history.md` in the same change. The Shipped record lives there too.
  Feature entries (P/PI/M) stay here ticked — their reasoning is referenced
  constantly and the IDs must stay greppable in one file.
- When a task turns out to be bigger than one line, split it into sub-tasks rather
  than leaving it half-ticked.
- If work reveals a new task, add it under the right section with the next free ID.
- **Task IDs freeze at first commit.** Never renumber after that. Retired tasks move
  to **Cut** with their ID intact.
- Move an item out of **Built on mock data** only when it is backed by real
  persistence, not when the UI merely looks right.
- Do not mark a **Decision** resolved on the user's behalf. Those are theirs alone, and
  code implying an answer is not the same as the answer being given — note the
  implication, don't tick it. When the user does decide, tick it and record the
  decision and its reasoning in the entry.
- Scope decided *against* goes in **Cut** with a one-line reason, not ticked as done.

---

## Phase status

- [x] **Phase 1 — UI with mock data**
- [x] **Phase 2 — Firebase, auth, pairing, persistence**
      *Closed 2026-08-03 with real auth, the pairing handshake, the feed on Firestore,
      Security Rules and their tests. Deferred: **P2-13** (photo upload), **P2-16**
      (Blaze for dev), **P2-19**–**P2-22**, **P2-28** (request sweep), **P2-31**,
      **P2-32**, **P2-37**–**P2-40**.*
      ***None of it gates the start of Phase 3, and none of it gates P3-01*** — that
      is what closing Phase 2 here means. Two of them do gate specific later Phase 3
      tasks, and pretending otherwise would just move the surprise:
      **P2-40** (write `couples/{id}.timezone`) blocks **P3-02**, which has no day
      boundary to read until it lands; and **P2-16** (Blaze on dev) blocks verifying
      **P3-04**, because the emulator has no FCM and push can only be seen on a real
      deploy. Build them when their Phase 3 task comes up, not before.*
- [ ] **Phase 3 — Cloud Functions, deletion, streaks, push, onboarding** ← current
- [ ] **Phase 4 — Home widget, polish, store submission**

> **Gate lifted 2026-08-03.** **PI-02** has shipped: the §10 honesty disclosure is in
> onboarding, unskippable, and revisitable from settings. External testing —
> TestFlight or Play internal — is no longer blocked by it. **P4-06** and **P2-16**
> (Blaze) still gate an actual deploy.

---

## Decisions — blocked on the owner

Nothing below is code. Each one changes what gets built. **Q1, Q2 and Q3 are all
answered, so the Phase 3 gate is lifted.** Q4 remains open and gates nothing
immediate — it decides whether trademark checks matter, not what gets built next.

- [x] **Q1** Hard delete or short encrypted retention for opened secrets? **Hard
      delete.** No retention, no recoverable copy, no support path. Once a secret is
      opened its body is destroyed and only the tombstone in `items` survives. This
      is what the code has assumed since **P2-06** removed `SecretMessage.body` and
      `markOpened()`, what **P2-36**'s sweep already does, and what the unpair copy
      promises. Retention would mean the content still exists after the app says it
      does not, which **PI-02**'s honesty disclosure could not describe without
      undercutting the product. Decided 2026-08-02.

      *The accidental-open risk is real and accepted. Brief §10 names it: "an
      accidental open is unrecoverable." The mitigation is interaction design, not
      storage — press-and-hold is already deliberate, and **P3-01** should consider a
      confirmation before the countdown starts.*
- [x] **Q2** Are streaks in, and if in, are they forgiving? **In, and forgiving.**
      One grace day per week: a missed day does not reset the count. A genuinely
      broken streak shows the number faded rather than zeroed — the history is not
      erased for having been interrupted. Milestone celebrations at 100, 365, 500 and
      1000 stay: those are anniversaries, a different emotional register from a daily
      obligation. Brief §12 flags that streaks in a romantic context risk turning
      affection into obligation; forgiveness is the mitigation. Decided 2026-08-02.
- [x] **Q3** One couple timezone, or per-device? **One couple timezone**, stored on
      `couples/{id}` as an IANA name (`Asia/Karachi`), never a UTC offset — offsets
      break twice a year under DST. Set at pairing from the accepting partner's
      device, editable later via **P2-39**'s callable.
      Per-device was rejected because a streak is a couple-level fact: two devices
      evaluating their own midnights show the same relationship as 47 and 46, and two
      people arguing about whose phone is right is the conflict brief §12 warns about.
      Asking at pairing was rejected as friction on the flow brief §11 calls the
      single most important metric. Q2's grace day absorbs the edge cases a shared
      zone creates for a long-distance couple. Decided 2026-08-02.
- [ ] **Q4** Any monetisation intent? *Decides whether trademark checks matter.*
- [x] **Q5** Export on unpair, or destroy? **Destroy, no export.** *Unpair copy
      promises total erasure.* Implemented in **P2-36**'s sweep: items go with their
      bodies in one batch, a second pass catches bodies whose items are already gone,
      and the couple document goes last so an interrupted sweep stays discoverable.
      *Was recorded here as decided-but-unticked, on the reading that a Decision stays
      unticked whoever made it. Corrected 2026-08-02 — the owner made this call, so it
      is ticked, like **Q1**. The rule at the top guards against the agent deciding,
      not against a decision being recorded.*

---

## Product integrity

Flagged in review. Small, keeps getting deferred because none of it is code.

- [x] **PI-01** Resolve the "Screenshot alerts" toggle — it implies a detection
      capability the product cannot deliver. Rename or remove. See brief §10.
      ***Removed, not renamed.*** *There is nothing to toggle. iOS can detect a
      screenshot of your own app, so a partial version was buildable — and that is
      exactly the trap: it would cover one of §10's three defeats on one of two
      platforms, while the row's presence implies all three on both. Shipping it would
      have contradicted the disclosure written in the same change.*
- [x] **PI-02** Write the §10 honesty disclosure into onboarding. **Gates external
      testing — that gate is now open.**
      *Its own screen, half of a two-screen onboarding, not a bullet in a feature
      list. `HonestyDisclosure` is one widget used in both places it appears, so the
      onboarding copy and the settings copy cannot drift.*
      *The copy states both halves, which is what makes it honest rather than
      defensive: what IS true (opened once, the words deleted from the server, nobody
      reads it twice — all of which **P3-01** made real) and what is not (a screenshot,
      a screen recording, a second phone). The three defeats are named, not abstracted
      into "technical limitations". It does not apologise: the limitation is a design
      choice, and the closing line says the ritual is worth more for being a choice
      than it would be as a guarantee.*
      ***Not skippable, and revisitable forever.*** *A Skip button on the one screen
      that exists to be read would defeat the requirement it satisfies. The
      compensating choice is brevity — two screens, two taps, no dwell timer and no
      confirmation checkbox, because those manufacture the appearance of consent
      rather than the substance. Settings → "How secrets work" reopens it; a
      disclosure nobody can find again is weaker than one they can.*
      *Recorded server-side by `markOnboardingSeen`: set-once, server-stamped,
      client-unwritable. §10 names overclaiming as a regulatory risk, and evidence the
      client can author is weaker evidence. **What the record honestly proves** is that
      the client called the endpoint, not that a human read the screen — inherent to
      any disclosure, and stated here rather than overclaimed, which is the same
      discipline §10 is asking for.*
- [x] **PI-03** Decide whether "Mood nudges" stays — it is not in brief §6.
      ***Cut.*** *A nudge is a mechanism for prompting your partner to post. Brief §12
      already flags that streaks in a romantic context risk turning affection into
      obligation, and **Q2** answered that by making streaks forgiving. Shipping a
      feature whose entire purpose is to manufacture the obligation Q2 just softened
      would be incoherent. Not in the brief, nothing implemented it, and the settings
      row was the only thing that claimed it existed.*
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

- [x] **M-01** Feed — `sampleThread()` hardcoded → Firestore collection
      *`sample_thread.dart` is deleted, with `mayaUid`, `devonUid`, `mockMembers`,
      `mockPartnerOf` and the resolver's fallback branch. `defaultTrayEmoji` and
      `reactionEmoji` were never mock — they moved to `lib/features/feed/feed_emoji.dart`
      rather than dying with the file.*
- [x] **M-02** Users — `Person` enum (`maya`, `devon`) → real accounts and profiles
      *Names now come from the signed-in profile (`myNameProvider`) and from
      `couples/{id}.memberNames`, denormalised by `respondToPairing` from the two user
      documents it already loads — no extra read. Reading the partner's profile
      directly is impossible by design: `users` is owner-only, and widening it to
      "anyone paired with me" is the enumerable-directory surface the P2-09b audit
      flagged. Same trade as **P2-25**'s `fromDisplayName`, bounded and defaulted on
      the same terms because it is user text crossing to the other person's screen.
      Confirmed by probe that `memberNames` adds no reachability — `couples` was
      already members-only, so no rules change and no auditor run.*
      *A couple with no `memberNames` — every couple formed before this — renders
      "Your person" rather than a blank or a crash. No migration by design; re-pairing
      regenerates it.*
      *`coupleName` is null on every real couple, so the title falls back to
      "<me> & <partner>", and to the neutral label if the partner is unknown rather
      than showing half a title.*
      *`memberName`/`memberInitial`/`partnerOf` are gone from `sample_thread.dart`,
      which now holds only the mock items, the two uid constants, and a `mockMembers`
      map the resolver falls back to. **That fallback is deleted at P2-12** with the
      mock thread — it exists so the sample feed stays readable, not because mock
      identity is wanted.*
      *Done: **P2-12** deleted the file and the fallback. The paragraph above describes
      the state between M-02 and P2-12, kept because it explains why the fallback ever
      existed.*
- [ ] **M-03** Pairing — `myCode = 'MK4Q7B'`, `_canPair` only checks `length == 6`
- [ ] **M-04** Share link — toast stub → deep link generation and handling
      *Deferred to the end of the phase. The domain `onceling.app` is owned but has no
      hosting. Decisions already made: host on Hostinger, not Firebase Hosting — the
      domain is registered there and one host is simpler than two. Serve
      `/.well-known/assetlinks.json` for Android. Skip
      `apple-app-site-association` for now: iOS is parked on the paid Apple Developer
      account, and Hostinger serves extensionless files as `application/octet-stream`,
      which iOS silently refuses to verify — a `ForceType application/json` rule in
      `.htaccess` is the fix when it matters.*
      *Also decided: the link needs a fallback page for someone who taps it without
      the app installed. Minimal — what Onceling is, and a Play Store link. Not a
      marketing site; that belongs with **P4-03** when there are screenshots worth
      showing.*
- [ ] **M-05** Secrets — `markOpened()` deletes client-side; must move to a Function
- [x] **M-06** Streaks — hardcoded `47` in two places
      *Both gone: the feed header and the settings row read `streakProvider`, which
      derives from the couple. Settings' `streak` constructor parameter is deleted
      rather than defaulted, like **M-10**'s anniversary — nothing ever passed it.
      A couple with no streak shows no pill at all; a broken one shows the number at
      45% opacity, which is **Q2**'s forgiveness in one visual. Settings says it in
      words too: "47-day, ended".*
- [x] **M-07** Mood — local state only, no push to partner
      *Persisted by the `setMood` callable. Push itself is **P3-04**; what landed here
      is that a mood now reaches the other person at all, which it did not before.*
- [ ] **M-08** Reactions — singular `reaction` on two types; brief §9 wants plural on all
- [ ] **M-09** Auth — none
- [x] **M-10** Feed header — `994 days · since 4 November 2023` was hardcoded.
      *Owner decision made: **the anniversary defaults to the pairing date.** A couple
      joining today has a real anniversary the app cannot know, and asking for it
      during pairing adds friction to the flow brief §11 calls the single most
      important metric. Default now, edit later.*
      *`respondToPairing` writes `anniversaryDate` as a second `serverTimestamp()`
      sentinel rather than reading `createdAt` back — every sentinel in one commit
      resolves to the same instant, so the two are equal by construction. Asserted to
      the nanosecond, because "by construction" is a claim and a near-miss would show
      as an off-by-one day count for a couple pairing near midnight.*
      *The header line and the settings row are both computed from it now. The
      settings row stopped being a `SettingsScreen` constructor default that nothing
      ever passed.*
      *Couples paired before this have no `anniversaryDate`, and there is **no
      migration by design** — the same choice as `memberNames` at **M-02**. They
      degrade neutrally: the header reads "your shared space" and the settings row
      reads "Not set", never a blank and never a date nobody chose.*
      *Day counting normalises both ends to midnight rather than using
      `difference().inDays`, so the number ticks over at midnight instead of at
      whatever hour the couple happened to pair. Local midnight per device — whose
      midnight it is becomes a real question once two people are in different zones,
      and that is **Q3**, still open.*
      ***The settings edit path does not exist.*** `couples` denies every client write,
      so changing an anniversary has to be a callable. That is **P2-39**, unbuilt.
      The streak beside it is still **M-06**, still blocked on **Q2**.

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
      *`anniversaryDate` and `timezone` were both written null pending owner
      decisions. Both are decided now: `anniversaryDate` defaults to the pairing date
      (**M-10**, built), and `timezone` is one shared IANA zone taken from the
      accepting partner's device (**Q3**). The `timezone` write is **P2-40**, unbuilt
      — it needs the client to send its zone, so it is a code change, not a comment.*
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
- [x] **P2-10** Security Rules — all reads/writes scoped to the requester's `coupleId`.
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
      *`items` and `secretBodies` landed here too, before **P2-12** reads them, so the
      feed is built against a closed collection rather than bolted shut afterwards.*
      *Membership is a `get()` on the caller's own profile — one read per request,
      cached, so a paginated page costs one and not one per row. A custom auth claim
      would cost nothing but goes stale until the token refreshes, and a stale copy of
      the field that decides who reads a couple's messages is the wrong trade.*
      *`items` allows `list` deliberately: **P2-12** needs an ordered, paginated, live
      query, and a flat deny would force reads by id, which a feed cannot do. Firestore
      fails the whole query if any returned row fails the rule, so an unfiltered or
      wrongly-scoped query is rejected wholesale.*
      *`update` is reactions-only, and within reactions the caller's own key only —
      both halves are expressible, with `diff().affectedKeys()` on the document and
      `MapDiff.affectedKeys()` on the map. Without the second, either member could
      rewrite or clear the other's reaction. `delete` is false: no delete-a-message
      feature exists, brief §7 puts editing out of V1, and both real deletion paths
      (**P3-01**, **P2-36**'s sweep) are server-side.*
      *Auditor scored 4/5. It found two real holes, both caught by probe rather than
      by reading and both fixed before re-scoring: `openedAt` was permitted but never
      type-checked, and type-specific fields were validated as a union, so a `text`
      item could arrive carrying `secretState`.*
- [x] **P2-11** Security Rules unit tests — negative cases on every collection: user A
      cannot read couple B's items, cannot read another user's document in
      `pairingCodes`, and cannot read another user's pending `pairingRequests`.
      *`rules-tests/items_rules.test.mjs`, own project namespace. Negatives and
      positives both: an over-strict rule passes every negative test and breaks the
      app, so the scoped/ordered/paginated query **P2-12** needs is asserted to
      succeed alongside every denial.*
      A signed-in user writing `coupleId` to their own document must be **rejected**,
      not merely absent from the happy path. Same for clearing it — an unrestricted
      clear lets a client orphan a couple, leaving one partner paired to nobody and
      the other paired to a ghost. Both directions need a failing-write test.
      Include a **passing** case alongside the two failing writes: a user updating
      their own `displayName` while `coupleId` is present and unchanged must succeed.
      Without it, an over-strict rule passes the negative tests and breaks the app.
- [x] **P2-12** Feed persistence with a real-time listener and pagination
      **`secretBodies` documents must carry `coupleId`, `senderId` and `body`.** All
      three are load-bearing and the write breaks without any of them:
      - `coupleId` — **P2-36**'s sweep finds orphans by couple. Bodies are keyed by
        item id, so items are otherwise the only handle, and either side can be
        deleted first. Without it, "destroy everything" means "destroy what we can
        still find" and brief §10's promise is not true.
      - `senderId` — **P2-10**'s rules bind creation to the sender and deny the sender
        reading their own body back, both without a `get()` on an item that may not be
        committed yet.
      - `body` — the payload, bounded at 2000 characters by the rules.
      *The rules reject a body missing any of them, so this is a hard requirement,
      not a nicety. Items must also carry only the keys their `type` permits: the
      validator is per-type, not a union.*
      *Done. `firestore.rules` did not change — the point of landing P2-10 first was
      that the feed is built against a closed collection, so no auditor run was
      triggered.*
      *Reading: one `StreamProvider` on `items`, filtered to the caller's `coupleId`,
      ordered `createdAt desc`, `limit`ed. The filter is load-bearing — `allow list`
      grants the query only where it provably stays inside the caller's couple, so
      dropping the `where` returns permission-denied for the whole query rather than
      more rows. An unpaired user emits an empty page instead of querying; the gate
      already prevents that state, but the provider does not assume the gate.*
      *Pagination is **one growing window**, not a live head plus static tail. Page
      size 30 — about three screens of bubbles, enough to fill the view and absorb
      some scrolling. Every page stays live, so a reaction landing on last week's
      message updates in place. The cost is that growing the limit re-subscribes and
      Firestore re-delivers the whole window: N pages cost 30+60+90+… reads, quadratic
      in pages. Right trade for a two-person thread, wrong one for many participants
      or long scrollback sessions; the fix if it bites is a live head plus `startAfter`
      pages, at the price of older reactions going static.*
      *The list is `reverse: true`. Index 0 is the newest message, so the thread opens
      where it should with no post-frame `jumpTo`, and appending older pages does not
      shift what is on screen.*
      *Two things the mapper had to learn, both forced by the rules rather than taste:
      `createdAt` on a create is `serverTimestamp()` because `allow create` requires
      `createdAt == request.time`; and **null-valued keys are stripped**, because in
      Firestore an explicit null is a *present* key and `keys().hasOnly()` counts it.
      Writing `openingStartedAt: null` on a secret would be rejected outright — that
      field belongs to **P3-01** and is not in the permitted create set at all. Same
      for `revealDurationSeconds` on an `untilClosed` secret.*
      *A message you have just sent carries an unresolved server timestamp, which reads
      as null until the ack. The mapper estimates it as `now()` — what the native SDKs'
      `ServerTimestampBehavior.estimate` does — and the provider re-sorts, so your own
      message appears at the top rather than at the far end for the round trip.*
      *Emoji taps no longer aggregate. The mock's `count: 14` is unreachable from a
      client because `allow update` is reactions-only, so one tap is one item. `count`
      stays on the model and in the rules for a server-side aggregate later.*
      *Reveal is **not** built, deliberately. No client can read a body: `secretBodies`
      grants `get` only while its item is `opening`, and **P3-01** owns the transition
      that gets it there. Holding a sealed card opens the reveal screen, which says so
      — "Not yet", the secret is still sealed, nothing read and nothing lost — rather
      than faking an open or throwing an error that reads as loss.*
      *Photos stay stubbed: the compose sheet's "Add photo" chip is still a no-op,
      and **P2-13** owns it.*
      *Index added: `items` on `coupleId ASC, createdAt DESC`, which is the feed's only
      composite. The sweep's `items`/`secretBodies` queries on `coupleId` alone are
      single-field and auto-indexed. **D-10** applies — the emulator does not enforce
      indexes, so this needs verifying against dev before **P2-16**.*
      *Mood is one callable, `setMood`, doing both halves of the **P2-06** decision in
      one batch: the ambient `moodEmoji`/`moodText`/`moodBy`/`moodUpdatedAt` on
      `couples/{id}`, and a `status` item for the scrollback. Split across a callable
      and a client write they could half-apply — an ambient mood with no scrollback
      record, or a scrollback entry the header contradicts. The item bypasses rules as
      every Admin SDK write does, safe on the same grounds as `ensureUserProfile`: the
      payload is a fixed literal, so no caller-supplied key reaches the document.
      `moodBy` exists because both people write into one couple document, and without
      it the ambient line cannot say whose mood it is. Nothing renders the ambient
      value yet — the thread shows the scrollback; the live value is there for the
      home widget (**P4-01**) and **M-10**'s header line.*
      *`fake_cloud_firestore` was added as a **dev** dependency. It is what makes the
      required tests provable rather than self-referential: the query, the pagination
      window, the mapper and every write run for real against an in-memory backend,
      with only `firestoreProvider` overridden.*
- [x] **P2-40** Write `couples/{id}.timezone` at pairing — the **Q3** decision.
      *The accepting device sends its IANA name with `respondToPairing`;
      `normaliseTimezone` validates it and the couple stores it. Read from
      `flutter_timezone`, because `DateTime.now().timeZoneName` returns an
      abbreviation or an offset depending on platform and neither is IANA.*
      *Validated in **two** gates, and the first is the one that matters:
      `Intl.DateTimeFormat` happily accepts `+05:00` as a timeZone, so validating
      with Intl alone would let a UTC offset through — exactly what Q3 rules out. An
      anchored `Region/City` pattern rejects anything starting with a sign or digit;
      Intl is then the second gate, so a zone that validates cannot fail in P3-02.*
      ***Invalid or missing becomes null — it never fails the accept.*** *The accept
      is the flow brief §11 calls the single most important metric, and refusing to
      pair two people because a device could not name its own timezone would trade
      that for a field nothing reads until the next daily tick. P3-02 falls back to
      **UTC** rather than skipping the couple: skipping means their streak silently
      never moves, indefinitely and invisibly, which looks exactly like a bug.*
      *Existing couples keep null and no migration runs, same as **M-02** and
      **M-10**. **P2-39** is how a couple fixes it.*
- [x] **P2-39** `setAnniversary(date)` callable — the settings edit path for **M-10**.
      *Split: the timezone edit this entry also named is now **P2-43** — it was a
      second callable with its own hazards, and half-ticking is what the maintenance
      rules forbid.*
      *A callable, not a write: `couples` denies every client write in every
      direction. **No `coupleId` parameter at all** — the couple is read from the
      caller's own profile, so the strongest form of "a non-member cannot set another
      couple's anniversary" holds: no other couple can even be named. Membership is
      still checked against the couple document, not the profile's claim, and an
      unpaired-status couple refuses.*
      *The date travels as a calendar key (`YYYY-MM-DD`), never an instant — an
      anniversary is a day on a wall calendar, and an instant would smuggle the
      DEVICE's timezone into a field the COUPLE's zone governs. Unparseable and
      impossible dates (`2026-02-30`) are rejected, never coerced. Bounds are checked
      against today IN THE COUPLE'S ZONE: past their midnight, their real anniversary
      is a future date by Greenwich's clock, and rejecting it would be Q3's off-by-one
      wearing a validation costume. Lower bound **100 years** — the longest recorded
      marriages run ~85, a century covers every living couple with margin, and
      anything earlier is a typo (1926 for 2026) that silent acceptance would turn
      into a couple with every milestone spent. Stored as an instant that lands on
      the chosen day in the couple's zone (`instantOnLocalDay`): UTC midnight is a
      day off anywhere west of Greenwich, and no single UTC hour survives the
      26-hour offset range, so it corrects once from UTC noon. Idempotent by nature.*
      ***The three milestone cases, decided:*** ***earlier*** *(and the pre-M-10
      first-set, same code path): P3-03's rule unchanged — highest fires, rest spent.
      The couple watching makes it MORE right: they just typed the date, and four
      pushes would be the app narrating arithmetic they did themselves. The milestone
      fires immediately after the commit rather than at the next tick — a couple
      standing in settings deserves the moment now, and it is the first honest demo
      of P3-03 against a real date.* ***Later*** *(uncrossing): `milestoneCelebrated`
      does NOT roll back. It records that a moment happened between two people, and
      it did; a rollback would re-fire day 365 on the second crossing, and celebrating
      the same evening twice is worse than a true history. Mechanically it would also
      overwrite the existing feed item, resetting its timestamp and wiping its
      reactions. Nothing writes the field downward, by construction — and after a
      forward edit the next milestone to fire is the next UNCELEBRATED one (500), not
      a replay.*
      ***The streak hazard checked, not assumed:*** *the incremental path resumes
      from `streakEvaluatedThrough` and never consults the anniversary once set;
      the anniversary only seeds `firstDayOf` on a never-evaluated couple, where the
      extra pre-pairing days are empty and `replayStreak`'s `streakCount === 0`
      branch scores them as nothing-to-protect. A test pins streak state across a
      three-year backdate plus a tick.*
      ***No notification to the other partner on edit, deliberately.*** *The change
      is visible where it lives — the header's day count and the settings row update
      live through the couple stream — and in the dramatic case the milestone push
      and moment reach BOTH partners anyway, which is organically the notification.
      A "your partner changed the anniversary" push is the register of an audit log,
      not of this app; the space is shared and so is control over it.*
      *Client: the settings row is the edit path. No anniversary reads "Set your day
      one" — a call to action, not the dead "Not set" label. Picker bounds mirror the
      server's; saving shows on the row; failure toasts and recovers; backing out
      saves nothing, same rule as every cancelled picker. Rules unchanged: `couples`
      was already closed to client writes, confirmed rather than assumed, so no audit
      was triggered.*
- [ ] **P2-43** `setTimezone(zone)` callable — the OTHER half of what P2-39's entry
      originally named, split out unbuilt.
      ***Changing the zone must not retroactively rewrite streak history.***
      **P3-02** stores streak dates as calendar-date keys in the couple's zone, so
      re-scoring old days under a new zone would silently move which day each past
      post belonged to and could break a live streak retroactively. Change the zone
      going forward only: leave `lastStreakDate`, `lastGraceDate`, `streakBrokenAt`
      and `streakEvaluatedThrough` untouched, and let the new zone apply from the
      next evaluation. Same callable shape as P2-39: member-only, couple from the
      caller's profile, `normaliseTimezone` already exists to validate the input.
- [x] **P2-13** Photo upload to Cloud Storage.
      *Storage emulator enabled first (port 9199, `storage.rules` registered), so
      nothing in this task ever addressed the real dev bucket.*
      ***Compression: 1600px long edge, quality 80.*** *The feed renders a photo at
      ~84% of the bubble width — about 300dp, so ~900px at 3x — and full-screen is at
      most the device's own resolution. 1600 covers both with room for a tablet or a
      future zoom. Quality 80 is the knee of the JPEG curve, past which bytes climb
      faster than anything visible improves. A 3-8MB camera photo lands at 200-500KB.
      Re-encoding also normalises HEIC to JPEG, which is what lets `storage.rules`
      check for exactly one content type.*
      ***Order: UPLOAD FIRST, then write the item.*** *Both orders leave a mess and
      they are not the same mess. Item-first means a failed upload leaves a message
      whose `mediaUrl` points at nothing — visible to both people, permanent (there is
      no delete-a-message feature), unfixable by the sender. Upload-first means a
      failed item write leaves an object nobody references: invisible, and reclaimable
      **because the id is minted before either write**, so the object is at
      `couples/{coupleId}/photos/{itemId}.jpg` whether or not the document arrives.
      Storage and Firestore cannot share a transaction, so the orphan cannot be
      designed away — only pointed in the less harmful direction.*
      ***The orphan is reclaimed by PREFIX, not by walking items.*** *`sweepCouple`
      deletes all of `couples/{coupleId}/photos/`. An item-driven deletion would visit
      exactly the objects that are NOT orphans and miss the entire orphan set. Brief
      §10 and Q5 promise erasure, not erasure-of-the-database — photos left in a
      bucket after a couple asks to be forgotten is the same broken promise as leaving
      the rows. The photo pass runs before the couple document (the completion marker)
      and swallows its own errors, so a Storage outage cannot abort a Firestore
      erasure already in progress; the trigger's `retry: true` runs it again.*
      ***Secrets stay text-only, deliberately.*** *A secret photo cannot honour the one
      promise a secret makes. **P3-01** deletes a `secretBodies` DOCUMENT — a Firestore
      write inside a transaction. A Storage object is a second system it cannot reach
      in the same operation, so "really deleted, from the server" would become two
      writes with a gap, at the exact moment the promise matters most. Worse, a
      download URL already issued can sit in the recipient's image cache after the
      object is gone. Attaching a photo therefore leaves secret mode in the compose
      sheet, and the Secret chip is hidden rather than disabled — P2-42's lesson.*
      *Client: `PhotoUploadService` (pick/compress/upload, `PhotoUploader` interface
      for tests), `PhotoSendController` (Riverpod, because progress outlives the sheet
      that started it), `PhotoUploadBanner` on the feed. `_PhotoWell` renders a real
      `Image.network` with all three P2-15 states in one fixed footprint, so the bubble
      does not resize when an image resolves.*
      *Platform: `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` added
      to Info.plist — without them iOS terminates rather than prompting — and `CAMERA`
      to the Android manifest. No `READ_MEDIA_IMAGES`: the system photo picker returns
      one granted URI, and asking for the whole library to send one picture is the
      wrong trade.*
      *Deployed to dev 2026-08-07, once Storage was provisioned on the project. It was
      blocked before that: `firebase deploy --only storage` failed with "Firebase
      Storage has not been set up", which needs a one-time **Get Started** in the
      console. The first denial after enabling was transient propagation, not a rules
      fault — worth remembering, because it looked exactly like a broken ruleset and
      sent me hunting one. See **D-26** for the real bug it was masking.*
      ***Verified on device 2026-08-07, SM-A325F, against dev.***
      *Camera: permission starts `granted=false`, `pick()` raises the system prompt
      ("Allow Onceling to take pictures and record video?"), granting flips it to
      `granted=true`, the shutter returns to `MainActivity`, and `pick()` yields a real
      file. **4.5 MB / 2400x3200 capture → 1200x1600 at 132 KB.** Also the first
      on-device run of the `targetSize` fix, and it holds: the LONG edge is capped,
      where the pre-fix code produced 2133x1600 from the same shape.*
      ***That measurement corrected a number in two places.*** *The 200-500 KB estimate
      was a guess from synthetic noise, which is adversarial for JPEG; a real
      photograph compresses far better. `storage.rules` said the 5 MB cap was "roughly
      ten times the expected size" — it is nearer 40x. Both comments now carry measured
      figures and the caveat that a busy scene lands higher.*
      *Gallery: the native sheet opens (`DocumentsUI` PickActivity via
      `ACTION_GET_CONTENT`, not the newer photo picker the manifest comment names), a
      selection returns, and it reaches the upload path. The selection was a PNG, which
      incidentally proved the re-encode: 1080x2400 PNG → 53 KB JPEG, magic bytes
      confirmed.*
      ***Unpair sweep — owner-observed 2026-08-07, and only half of the claim.***
      *The owner unpaired on the device and reported the couple's Storage prefix
      showing empty in the console afterwards. **What that establishes:** the sweep ran
      and reached Storage, so unpairing does not leave a couple's photographs behind —
      brief §10 and Q5 hold at the Storage layer for objects that were there.
      **What it does not establish:** whether any ORPHAN object — one with no item
      document pointing at it — was present immediately before the unpair. Without
      that, an item-driven sweep would have produced the same empty prefix, so the
      observation cannot distinguish prefix-deletion from item-walking. **The orphan
      half is the entire reason the sweep deletes by prefix, and it remains open.**
      The test that settles it is in **D-28**.*
      ***Still unverified:*** *a non-member read against a real bucket. Needs throwaway
      accounts — checking it on the owner's own device would mean signing them out with
      no way to sign them back in.*
- [x] **P2-14** Migrate named routes → `go_router` with a single auth redirect
      *`resolveRedirect()` in `lib/common/app_router.dart` is the whole gate, a
      pure function: loading → splash (never a sign-in flash), signed-in with no
      profile document → still splash (the sign-up write race), then coupleId
      routes pairing vs feed. Splash owns a 6s timeout with retry. Riverpod
      drives `refreshListenable`, so setting `coupleId` in the Emulator UI moves
      the app live. Sheets stayed sheets; the secret reveal became a route.
      Unpair's mock path now lands on pairing, not sign-in — a signed-in user
      cannot reach sign-in, the gate bounces them.*
- [x] **P2-15** Loading / empty / error states on every read
      *Done in the same change as **P2-12**, not after it. Every read added there needs
      all three, and retrofitting them would have meant revisiting each one.*
      *All three replace the **list only**. The header and the compose tray do not
      depend on `items`, so none of them is ever a bare spinner over the whole screen —
      the app keeps looking like itself while the thread resolves.*
      *Loading is deliberately empty rather than a spinner: the first page usually
      arrives faster than a spinner is noticed, and one that flashes reads as something
      going wrong. Paging back does not pass through it at all —
      `when(skipLoadingOnReload: true)` keeps the thread on screen while the wider
      window loads.*
      *Empty gets copy, because it is the first thing two people see together after
      pairing. Error is recoverable: it says nothing has been lost — which is true —
      and offers a retry that re-runs the listener, asserted by a test where the first
      attempt fails and the second succeeds.*
      *Write failures are surfaced too, though they are not reads: a send that silently
      does nothing is the worst available failure on a thread two people trust.*
- [x] **P2-16** Upgrade **dev** to Blaze; set a $5 budget alert.
      *Deployed 2026-08-04. Rules and indexes first, alone; then functions. All 13
      functions live, both schedules registered and firing.*
      ***Three things surfaced that only a real deploy can surface:***
      *1. **The lint config had never run.** `firebase.json`'s predeploy hook runs
      `npm run lint`, and the emulator does not execute predeploy hooks — so the
      stock `firebase init` eslint config met the codebase for the first time here,
      with 248 errors. 234 were two rules (`object-curly-spacing`, deprecated
      `valid-jsdoc`) disagreeing with every file rather than finding a defect; those
      were reconciled in `.eslintrc.js` with the reasoning recorded there. The
      genuine ten — over-length lines, backtick strings with no interpolation, two
      undocumented helpers — were fixed in source.*
      *2. **`sweepUnpairedCouple` needs `--force`.** A retry policy requires explicit
      acknowledgement that the function is idempotent. It is, by design (**P2-36**)
      and by test. Confirmed nothing existed that `--force` could silently delete
      before using it.*
      *3. **The first 2nd-gen deploy raced its own Eventarc service agent** and the
      Firestore trigger failed to create. Infrastructure propagation, not code; the
      CLI says to retry and the retry worked.*
      ***Region was wrong, and nothing would have told us.*** *`setGlobalOptions` set
      `maxInstances` but no region, so callables took the `us-central1` default while
      Firestore is in `asia-south1` — every call crossing a continent to read the
      document it was called about, with only the Firestore trigger co-located. Now
      pinned to `asia-south1` on both sides. The client half is the sharp bit:
      `FirebaseFunctions.instance` and `instanceFor(region:)` are **different
      objects**, so `main.dart`'s emulator wiring had to move to the same one — miss
      that and a debug build keeps working while calling the real dev functions.*
      ***The pin missed a third client, and the suite hid it for two commits.***
      *`rules-tests` builds its own callable handles, and `getFunctions(app)` there
      still defaulted to `us-central1`. The Functions emulator resolves callables per
      region and answers 404 for the wrong one, which the SDK surfaces as
      `functions/not-found` — indistinguishable from a function nobody wrote. It went
      unnoticed because **the running emulator kept serving the old region until it
      was restarted**: the suite stayed green against a process that predated the pin,
      and only broke when a restart made it honest. 92 of 139 failed the moment it
      did. Fixed by naming `REGION` in both test files. The lesson is not about
      regions — it is that **a long-lived emulator is stale state, and a green suite
      is evidence about the process you ran against, not about the code.** Restart the
      suite before trusting a run that follows a functions config change.*
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
- [x] **P2-19** Google sign-in.
      *Debug fingerprints from `./gradlew signingReport`, both registered on the dev
      Android app:*
      *SHA-1 `7B:6F:B8:53:C8:92:A2:E5:43:63:DB:A8:96:E6:E9:7A:6C:B6:9C:65`*
      *SHA-256 `89:C9:9B:4A:4D:61:39:E9:19:DF:98:A3:19:FF:46:85:6E:B9:F0:45:0D:A3:BD:AA:7F:C2:87:11:AA:D5:FF:85`*
      *Both from the standard `~/.android/debug.keystore`. `flutterfire configure`
      re-run, so `google-services.json` now carries an ANDROID oauth client bound to
      the SHA-1 plus the WEB client Android needs to mint an ID token. iOS got the
      reversed client ID as a `CFBundleURLTypes` scheme — without it the browser
      authenticates and never comes back.*
      ***No client id is pasted anywhere.*** *The google-services Gradle plugin emits
      `R.string.default_web_client_id` and iOS reads `CLIENT_ID` from its plist; both
      files are gitignored, so `initialize()` takes no argument rather than hardcoding
      a value out of them.*
      ***One shape of user document.*** *`signInWithGoogle` ends at the same
      `_settleProfile` as email, so the profile is written by the same
      `ensureUserProfile` callable. That matters because **P2-35** writes a fixed
      literal server-side — a provider that bypassed it would be the only way a
      differently-shaped profile could ever exist.*
      *Sign-out now signs out of Google too. Without it the account picker is skipped
      next time and the previous person is silently re-selected, which on a shared
      device is somebody else's account.*
      *Verified: the button is enabled and reaches the service (test), a cancelled
      sign-in raises no error (test), a failure shows its message (test), and
      `GoogleSignIn.instance.initialize()` succeeds on the iOS simulator — meaning it
      resolved the client id from the plist. **The OAuth flow itself was not completed
      end to end**: it needs tapping through Google's consent screen and this machine
      denies `osascript` assistive access.*
- [ ] **P2-20** Sign in with Apple — **HARD GATE on iOS submission now that P2-19
      has shipped.** Guideline 4.8 makes it mandatory once a third-party social
      sign-in is offered, so this blocks **P4-07** and nothing else: Android ships
      without it, and the simulators test without it.
      *Needs a paid Apple Developer Program membership for the Services ID and key.*
      ***The button is gone from the UI (P2-42), so this is now purely a submission
      gate rather than dead UI.*** *It shipped as a permanently disabled control, which
      was the wrong call: on the first screen a user ever sees, a dead button does not
      read as "coming soon", it reads as broken software. Removing it changes nothing
      about the obligation — Guideline 4.8 still makes Sign in with Apple mandatory for
      iOS the moment Google sign-in ships there, and this still blocks **P4-07**.
      When the account exists, the button comes back: `AuthButton` is already the
      shared treatment, so it is one more instance and no restyling.*
- [x] **P2-21** Emulator host per platform.
      *`EmulatorHost` resolves it: `localhost` for iOS simulators and desktop,
      `10.0.2.2` for the Android emulator, and a `--dart-define=EMULATOR_HOST=<ip>`
      override for a real device. **No LAN IP in source** — hardcoding bakes one
      developer's DHCP lease into the repo where it rots silently; discovery would be
      scanning or mDNS to save one flag. A test asserts no private-range address is
      baked in.*
      ***The platform branch was only half the problem.*** *With the host correct, the
      AVD still could not reach the suite: Android has blocked cleartext HTTP since
      API 28 and the emulator speaks plain HTTP. The error names cleartext, not the
      host, which is a confusing thing to reach from a failed sign-in. Fixed with a
      `network_security_config.xml` under `src/debug/` — merged into debug builds
      only, so release keeps Android's default.*
      ***That config was first scoped to `10.0.2.2`, `127.0.0.1` and `localhost`,
      which was wrong and is now corrected.*** *It contradicted the very flag it was
      meant to support: `EMULATOR_HOST` exists to name a LAN address, and a LAN
      address was exactly what the list excluded. A physical SM-A325F resolved the
      host correctly and was refused anyway —* `Cleartext HTTP traffic to
      172.20.10.3 not permitted`. *Listing the private ranges instead is not
      possible: `<domain>` matches hostnames and has no CIDR form, so `192.168.0.0/16`
      parses as a literal hostname and matches nothing — a fix that looks right and
      silently keeps failing. Generating the entry from the dart-define at build time
      is possible but needs a Gradle task ordered against `mergeDebugResources` and
      breaks on every run that omits the define, which is every simulator run. Now a
      `<base-config>`: **the boundary that matters is the build type, not the host
      list.** `android_network_config_test.dart` guards the release side.*
      ***The platform branch was the wrong question, and that was the deeper bug.***
      *It distinguished iOS from Android, not an emulator from a handset — so a real
      Samsung with no flag resolved `10.0.2.2`, which off the emulator is not a wrong
      host but a meaningless one, and surfaced as a network error reading as the app's
      fault. **There is no zero-dependency way to tell them apart:** the signal is the
      `ro.kernel.qemu` system property (`1` on the AVD, `0` on the SM-A325F, checked on
      both), and the `/dev/goldfish_pipe`-style markers are not visible from the app
      sandbox — file sniffing cannot answer it. Hence `device_info_plus` and its
      `isPhysicalDevice`, which asks the platform rather than guessing.*
      ***Chosen: a physical device falls back to `localhost` and warns loudly.***
      *`localhost` is correct under `adb reverse`, so refusing would break a working
      route. The warning names every way out — `adb reverse`, `EMULATOR_HOST`,
      `USE_EMULATOR=false` — because a warning that does not say what to do instead is
      noise. A test asserts all three are in it.*
      ***`automaticHostMapping: false` is the load-bearing part, and finding it cost a
      wrong theory first.*** *All three of `useAuthEmulator` / `useFirestoreEmulator` /
      `useFunctionsEmulator` default that flag TRUE, which on Android silently rewrites
      `localhost` and `127.0.0.1` to `10.0.2.2` — a convenience for the AVD, and on a
      handset a rewrite to an address that does not exist. So every loopback attempt
      failed, and the failure had nothing to do with loopback.*
      *I diagnosed that as "`adb reverse` cannot carry the native Firebase SDKs" and
      wrote it into the docs, this file and the `network_security_config.xml` comment,
      reasoning from a Dart `HttpClient` reaching the tunnel while Firebase did not.
      **The evidence was real and the explanation was invented.** What settled it was
      the device log naming the address it actually dialled —
      `Failed to connect to /10.0.2.2:9099` from a build told `localhost` — and the
      plugin announcing the rewrite in plain text one line earlier:
      `Mapping Firestore Emulator host "localhost" to "10.0.2.2"`. It had been printing
      that the whole time, into a log I was grepping for `[backend]` and error strings
      only. **Two lessons: read the log around the failure, not the lines you predicted
      would matter; and a mechanism that merely fits the evidence is a hypothesis, not
      a finding.** With the flag off, `adb reverse` + `EMULATOR_HOST=localhost` signs in
      on the SM-A325F. All three surfaces are corrected.*
      *The decision is a pure function (`hostFor`) taking both facts as arguments.
      `flutter test` runs on the host VM where `Platform.isAndroid` is false and no
      device exists, so the Android branches were untestable until this split; the
      physical-Android case — the actual bug — now has a test.*
      *Verified on the SM-A325F, same code: `adb reverse` + `EMULATOR_HOST=localhost`
      signs in, and so does the LAN route at `192.168.100.135 explicit=true`.
      **Not re-verified after the `automaticHostMapping` fix: the AVD and the iOS
      simulator.** Both were green before it and the flag only removes a rewrite that
      never applied to them — the AVD asks for `10.0.2.2` outright and the mapping is
      Android-only — but neither has been run since, so neither is claimed.*
- [x] **P2-41** `--dart-define=USE_EMULATOR=false` — an opt-out that skips
      `_connectToEmulators()` so a debug build talks to the dev project.
      *Required by anything with no emulator behind it. **Push (P3-04) is the standing
      case:** there is no FCM emulator and the triggers are deployed to dev, so a
      notification cannot be observed any other way — see **D-24**, where delivery has
      never been seen on any device. Also covers index-dependent queries (**P3-06**),
      which the Firestore emulator does not enforce.*
      *Deliberately opt-**out**, not opt-in: the default is the emulator, so a
      forgotten flag can only ever send you somewhere harmless. The reverse default
      would mean one absent-minded run against real users' data.*
      ***The startup line now names the backend, not just the host.*** *`host=10.0.2.2`
      never said whether that was an emulator or the dev project, and talking to the
      wrong one while everything looks fine is the entire failure class here. Reads
      either `[backend] emulator at <host> (auth 9099, firestore 8080, functions 5001)`
      or `[backend] REAL FIREBASE — dev project, no emulator`.*
- [x] **P2-42** Sign-in screen: remove the Apple button, two equal options.
      *UI only. Apple is deleted rather than disabled (**P2-20** has the reasoning).
      What remains is "Continue with Google" and "Sign in with email", both rendered by
      one `AuthButton` — **so they are siblings by construction, not by two styles kept
      in agreement.** Neither is filled: making one primary would be a recommendation
      we do not mean, since neither is the option we would rather someone picked.*
      *`PrimaryAuthButton` is deleted — it only ever rendered Apple.
      `UnderlinedTextButton` is deleted too: it was the old text-link email action and
      nothing else used it. `SecondaryAuthButton` became `AuthButton`, because
      "secondary" names a hierarchy that no longer exists.*
      ***The fixed `SizedBox(height: 58)` had to go.*** *Two equal buttons stack taller
      than the old primary + secondary + text link, and at 200% text scale each label
      can wrap to two lines — the fixed box clipped. `AuthButton` sets a minimum height
      instead and grows. A test pins it at 360dp × 200%.*
      *`AuthButton` takes an optional leading `icon`, unused for now. **There is no
      Google logo mark to keep** — `assets/images/` holds only a README and the button
      has always been text-only. An approximated Google "G" is worse than none, so the
      slot is there and the official asset drops straight in.*

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
- [x] **P2-36** Unpair. The settings screen has an unpair sheet with typed
      confirmation (Phase 1 UI), but nothing behind it. A paired user currently cannot
      separate. Needs a callable that clears `coupleId` on both users server-side —
      per CLAUDE.md, an unrestricted clear is as dangerous as an unrestricted set,
      because it orphans a couple. Must be atomic and idempotent, and must decide what
      happens to `couples/{id}`, `items`, and `secretBodies`. **Q5** answered: destroy.
      *Two phases, and the split is the point. **Phase 1** (`unpair` callable) is one
      transaction: clears `coupleId` on both users and stamps the couple
      `status: 'unpaired'`. When it returns, both people are separated — that is the
      guarantee. **Phase 2** is a sweep that only has to be reliable. Doing both in one
      callable would risk a timeout on a couple with real history, and a partial delete
      leaves the orphans `assertPairingInvariant` exists to catch.*
      *Phase 2 is an `onDocumentUpdated` trigger on `couples/{id}`, guarded to the
      transition into `'unpaired'` so phase 1's resume path cannot start a second
      sweep, with `retry: true`. A trigger rather than a schedule because the work is
      caused by exactly one state change and someone who just asked for erasure should
      not wait for a cron tick; the couple document doubles as the work queue, and its
      deletion is the completion marker.*
      *Deletion order: each item **with its secret body in the same batch**, then any
      remaining bodies by `coupleId`, then the couple document last. Items and bodies
      go together rather than all-bodies-then-all-items — bodies are keyed by item id,
      so the phased order opens a window where an item is gone and its body is
      unreachable. The couple goes last because it is the only handle on the data.*
      *Found while testing: a body whose item was already deleted is unreachable
      forever. **`secretBodies` must carry `coupleId`, and P2-12 must write it** — the
      second pass depends on it. Without that, "destroy" means "destroy what we can
      still find".*
      *No rules change: `couples` already denies all client writes and `items` /
      `secretBodies` fall to the catch-all deny. Confirmed with seven probes rather
      than assumed, so no auditor run.*
- [ ] **P2-38** Backstop sweep for couples stuck at `status: 'unpaired'`. **P2-36**'s
      trigger retries, but a sweep that exhausts its retries leaves a couple marked
      unpaired forever with nobody looking, and its data undeleted — which the unpair
      copy promises is gone. A scheduled pass over that state closes it; it can share
      **P2-28**'s schedule.
- [ ] **P2-37** Black screen on sign-out, unreproduced. Observed once on the 16e after
      a paired sign-in, an attempted unpair, and sign-out. Two hypotheses disproven
      with device traces: the celebration detector never arms on sign-out (`_observe`
      returns early on a null profile), and the `_unpair()` `context.go` race does not
      produce it at 0 ms or 2500 ms gaps. No exception was captured — the `flutter run`
      for that device had been killed, so nothing held stderr.
      *Note: the device was running an instrumented build at the time, later found to
      have survived a source-level revert. That build's auto-submit hook may be
      implicated. If it does not recur on clean builds, close this as not-a-defect.*
      *If it recurs, the thing that would settle it is a `flutter run` attached to the
      device at the time. Do not chase further without a new occurrence.*
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

- [x] **P3-01** Secret reveal — hard delete `secretBodies`, keep the tombstone in
      `items`. **Two transitions, both server-only**, since a client cannot set
      `secretState`: item `update` is restricted to the caller's own reaction key.
      - `beginReveal` — `sealed -> opening`, stamping `openingStartedAt`.
      - `completeReveal` — `opening -> opened`, deleting the body in the same
        transaction as the state change. **Q1: hard delete**, no retention, no
        recoverable copy, no support path.
      *Both idempotent, and the shape of `beginReveal`'s idempotency is the point: a
      second call on a still-open window returns the EXISTING `openingStartedAt`
      rather than stamping a new one. Restarting the clock would extend the window,
      which is the one thing it must never do — and the client does re-call it, on a
      retry after a failed body read.*
      *`heldFullCountdown` is derived server-side from real elapsed time, never taken
      from the caller. It is what the SENDER is told, and an app about honesty should
      not let one side author the other side's notification.*
      **The expired-window case, decided: a scheduled sweep, `every 10 minutes`.**
      *Not folded into an existing one, because there is no existing schedule to fold
      into — **P2-28** is deferred and unbuilt, and **P2-36**'s `sweepUnpairedCouple`
      is a document trigger that fires on a couple going `unpaired`, so it would never
      see an abandoned reveal in a couple still together. Attaching to it would mean
      collection happened only by luck. When P2-28 is built it can share this
      schedule; both are "collect what nobody finished".*
      *It cannot race a live reveal: each item is judged against its OWN deadline —
      `openingStartedAt` + its own window + a 5-minute grace — not one global cutoff.
      A 10s and a 30s secret are each judged on their own terms.*
      ***What happens to an `untilClosed` secret whose reader never finishes:*** *it is
      closed at a one-hour ceiling. Those carry no `revealDurationSeconds`, so nothing
      time-based expires them, and without a bound a reader who walks away leaves a
      readable body on the server indefinitely — the retention brief §10 promises
      against, not just the wrong reader. The ceiling mirrors the existing
      `revealDurationSeconds <= 3600` cap so the invariant is uniform: **no reveal
      session outlasts an hour.** It is enforced in `firestore.rules` as well as in
      the sweep, so the body stops being readable at the hour mark rather than
      whenever the schedule next runs. **This slightly narrows what "until they close
      it" means** — a reader lingering past an hour loses the text. Recorded as a
      decision the owner can overturn; the alternative is indefinite retention.*
      **Q1's confirmation question, answered: no dialog.** *`beginReveal` moved to
      AFTER the held breath and the tear, so those 2.3 seconds are the confirmation —
      nothing is written during them and leaving costs nothing. A modal after a
      deliberate press-and-hold would duplicate a commitment the choreography already
      makes, and is the kind of prompt people learn to dismiss unread. Moving the call
      also means the reader gets the whole window for reading instead of losing 2.3s
      of it to animation. Pinned by a test that abandons mid-tear and asserts no call
      was made.*
      *The screen handles: the body failing to load after `beginReveal` succeeded
      (retryable, and says the clock has started, because it has); backgrounding
      mid-countdown (the window is the server's, so on resume it recomputes from
      `openingStartedAt` rather than resuming a paused local timer); the window
      expiring while open; and the already-opened case.*
      *`firestore.rules` changed — the `untilClosed` branch only. **Auditor: 4/5**,
      unchanged from P2-10 and for the same reasons. No finding is attacker-reachable;
      every one is a member acting on their own couple's data. Findings: orphan
      `secretBodies` creation with no item required (a rules-level `exists()` check is
      not viable — P2-12 writes both in one batch, evaluated against pre-batch state,
      so the item does not exist yet), unbounded content writes with no rate limit
      (folded into **P3-05**), and the `itemKeysFor` note below.*
      *The auditor's `itemKeysFor` recommendation was **applied and then reverted**:
      adding `openingStartedAt` to the permitted secret keys made
      `openingStartedAt: null` writable by a client, trading a live guarantee for a
      hypothetical one. A P2-12 test caught it immediately. The landmine it was meant
      to defuse is now a comment instead: **do not add `isWellFormedItem` to
      `allow update`** — the stored shape carries an admin-written key the validator
      does not list, and every reaction on a secret would start failing.*
      *Verified on device end to end, which is what the rule had never had: the
      recipient read the body through the rule during the window; the sender was
      denied mid-window; `completeReveal` destroyed the body and left the tombstone
      with `openedAt` and a correctly-derived `heldFullCountdown`; the recipient could
      neither re-read nor reopen it afterwards; and the tombstone arrived on the
      reader's screen through the feed listener with no refresh.*
- [x] **P3-02** Streak calculation Function
      **What counts as "posted": all five item types, and only item types.**
      *`text`, `photo`, `secret` are unambiguous. `emoji` counts because a streak
      measures reaching out, not effort — a couple who sent each other hearts all day
      plainly showed up. `status` (a mood) is the closest call, authored about
      yourself rather than to your partner, and it counts because it lands in their
      thread and they read it; someone who told their partner how they were doing has
      not "failed to post" in any sense a person would accept. Brief §12's coercion
      warning argues for the forgiving reading wherever the line is genuinely unclear.*
      ***Reactions deliberately do not count**, and they are the sharp edge: a
      reaction is a field on the other person's message, not an item. Replying is not
      reaching out, and a streak kept alive by tapping ❤️ on whatever arrived would
      measure attendance rather than contact.*
      **Grace: one per ROLLING seven days**, tracked by `lastGraceDate`.
      *Rolling rather than a fixed week boundary, which would create a cliff nobody
      could explain — miss Saturday and Sunday and you die, miss Sunday and Monday and
      you live, purely because an invisible line sits between them. Rolling makes the
      promise simply true, at the cost of storing a date instead of a counter.*
      **"Faded, not zeroed" is `streakBrokenAt`.** *`streakCount` keeps its last value
      when a streak breaks and this field tells the UI to dim it. A "previous count"
      field would say the same thing while letting the two drift apart. Coming back
      restarts at 1 — the old number stays visible until that moment precisely so it
      is not erased.*
      **Incremental, with an explicit repair path.** *A daily full replay of every
      couple's whole thread is a read cost that grows without bound, for a number that
      changes by at most one. So the daily path increments, and `recalculateStreak`
      replays from history and overwrites when a count is wrong. Both share the same
      pure `replayStreak` core, so the repair cannot disagree with the daily path
      about the rules — only about how far back it looked. Purity is also what makes
      idempotency structural rather than asserted.*
      **Scheduling across timezones: hourly, not daily.** *A streak day ends at the
      couple's own midnight and couples in different zones do not share one. Rather
      than a cron per zone, the tick runs hourly and the evaluation is idempotent and
      keyed on the couple's local date via `streakEvaluatedThrough` — so a couple is
      scored within an hour of their own midnight and never scored twice for the same
      day. Frequency becomes an implementation detail instead of a correctness
      property.*
      *Fields added to `couples`: `streakBrokenAt` (faded), `lastGraceDate` (the
      rolling grace), `streakEvaluatedThrough` (idempotency). `streakCount` and
      `lastStreakDate` already existed per brief §9. **All dates are calendar-date
      keys (`YYYY-MM-DD`), not timestamps** — a timestamp would be ambiguous about
      whose midnight it meant, which is the entire problem Q3 exists to solve.*
      *Only completed days are scored; today is never evaluated, or every streak would
      break at midnight and mend when someone posted. The count increments only on
      days both posted, so a 47-day streak means 47 days they both showed up rather
      than 47 calendar days — grace days keep it alive without inflating it.*
      *No new index: the existing `coupleId` + `createdAt` composite covers the range
      query.*
- [x] **P3-03** Milestone triggers — day 100, 365, 500, 1000
      *Unaffected by **Q2**'s forgiveness: milestones count days since
      `anniversaryDate` (**M-10**), not consecutive posting. They are anniversaries,
      a different register from a daily obligation, which is why they survive a
      forgiving streak unchanged.*
      ***Detection rides P3-02's hourly tick*** *— a second sweep over `couples` would
      double **D-20**'s read cost to learn nothing the first pass does not already
      know. The check is pure arithmetic against the couple document that tick has
      already read: zero extra reads until a milestone actually fires. Days elapsed
      use `localDateKey`/`daysBetweenKeys`, the same helpers as the streak boundary,
      so the two features cannot disagree about when a couple's day ticks over.*
      ***Idempotency: `milestoneCelebrated` on the couple document*** *— a single
      integer, the highest day already fired. One monotonic field rather than an
      array, because the firing rule collapses to `crossed > celebrated` and the
      backdate decision falls out of the same comparison. The check-and-set is a
      transaction that also creates the feed item at a deterministic id
      (`{coupleId}-milestone-{day}`), so a raced retry writes the SAME document
      rather than a second one. Pushes go after the commit: a crash between the two
      loses a push, never doubles a milestone. `couples` denies all client writes, so
      the record is unforgeable.*
      ***Backdated anniversaries (P2-39) fire the HIGHEST crossed milestone only.***
      *Three years entered at once means 100/365/500/1000 crossed in one write. Four
      pushes at once is spam; four same-timestamp feed items is clutter pretending to
      be history; silence is a real loss. The statement that is true TODAY is the
      biggest one, so it fires and everything beneath is marked spent, never firing
      late. The same principle covers an app dormant across two milestones.*
      ***The feed item is a first-class `milestone` type, not a `status` with a
      marker*** *— a status is a person speaking, and three systems believe that: it
      counts toward the streak (`POSTING_TYPES`), it enters `notifyOnItem`'s
      partner-only fan-out, and it renders as somebody's line. The milestone document
      carries NO `senderId`, and the absence is load-bearing in all three places:
      `notifyOnItem` returns early (no one-sided push), `postsByDay` skips it (the
      app congratulating itself cannot extend a streak), and the feed centres it.
      The create rules' type enum deliberately excludes `milestone`, so no client
      can forge one; members can react to one like any item. Written once per couple
      — the id contains no member.*
      ***Push: both partners, identically.*** *Every other notification excludes the
      actor; a milestone has no actor, so for the first time there is nobody to
      exclude. Fixed copy, no user content, so the previews setting is not consulted.
      Targeting is tested; delivery remains **D-24**'s standing gap.*
      ***The full-screen moment is a comparison of durable state, NOT P2-26's
      transition detector*** *— deliberately. The pairing moment watches a change
      arrive because one partner causes it; a milestone has no actor and crosses at
      the couple's midnight with both phones dark, so "did this session watch it
      happen" is the wrong question. Instead: `couples.milestoneCelebrated` (server
      truth) against `users/{uid}.milestoneSeen` (this partner's own record, written
      on dismissal). Greater means owed. Each partner sees it exactly once,
      independently; a cold start after dismissal compares equal and shows nothing;
      a leap across two milestones shows the highest. Gate-wise it is P2-26's shape:
      a route of its own, released by acknowledge, with the pairing moment ranked
      above it should P2-39 ever make both pending at once.*
      *Rules: `milestoneSeen` added to `isWellFormedProfile` — nullable int,
      0..100000, client-writable like `pushToken` (a fact about the writer's own
      viewing; forging it costs the forger only their own celebration). **Audited:
      4/5**, one new finding accepted (no monotonicity — a user can lower it and
      replay their own moment, harming nobody else). Copy is a hand-kept Dart/TS
      mirror in the D-17 shape: `milestone_copy.dart` ↔ `milestoneCopy` in
      `milestone.ts`.*
      *NOT deployed to dev in this change; the tick carrying it deploys with the
      next functions release.*
- [x] **P3-04** FCM fan-out — secret payloads carry no body and no preview.
      ***What each type shows.*** *A secret carries **the sender and nothing else**,
      and the check ignores the preview setting entirely rather than consulting it —
      there is no configuration in which a secret's words reach a lock screen. A
      preview would mean the secret was read while the app never registered an open,
      the body was never deleted and the sender was told nothing: the mechanic
      defeated end to end.*
      ***text, photo, status, emoji are a SETTING, defaulting OFF.*** *Brief §5 names
      couples who share devices, and they are exactly the people for whom a warm,
      useful preview is the wrong default. Someone on their own phone wants to read
      "be there in ten" without unlocking; someone whose tablet gets borrowed does
      not. Neither is a mistake, so neither is a default that fits everyone — and OFF
      is the direction where being wrong costs nothing, because the reverse would leak
      once before anyone learned the setting existed. Read from the RECIPIENT's
      profile: it is their lock screen. Emoji shows itself, being already less
      revealing than the notification announcing it.*
      *`pushToken` on `users/{uid}`: stored on sign-in, followed through rotation,
      **cleared on sign-out**. Driven by a provider watching auth rather than called
      from each sign-in path, so a new one cannot forget it — Google sign-in landed
      afterwards and needed no change. The server's copy is cleared before the local
      one, because the reverse order can leave a token nobody can reach but the
      fan-out still targets. A dead token is cleared by the fan-out too.*
      *Also notifies on an incoming pairing request — which is what lets **P2-24**'s
      waiting screen stop saying the partner sees it next time they open the app — and
      on an accept. Never the person who caused the event: `partnerOf` excludes them
      by construction rather than by a comparison someone could forget.*
      *Deployed to `asia-south1` per the **P3-06** finding.*
      ***Verified against real dev, up to the radio:*** *all three triggers fire, the
      recipient is resolved correctly, the payload is built, and a dead token is
      cleared — confirmed in `notifyOnPairingRequest`'s own logs. **Delivery to a
      handset is NOT verified**: no physical Android device is attached, and this
      AVD's Play services is broken (`Unknown calling package name
      'com.google.android.gms'`) so it cannot mint a token. I expected a
      `google_apis_playstore` image to work and it did not.*
      *iOS is fully built and will not deliver until an APNs key is uploaded —
      **P4-09**, and that is genuinely the only remaining step.*
- [ ] **P3-05** Rate limiting on any future secret-bearing check. *The pairing half
      moved forward to **P2-27** — it is a **P2-09** dependency, not later polish.*
- [x] **P3-06** Composite indexes; keep `firestore.indexes.json` in sync
      ***A required index was missing, and it would have failed in production on
      every run.*** *`postsByDay` in **P3-02**'s streak tick queries `items` with
      equality on `coupleId` plus a RANGE on `createdAt` and no explicit `orderBy`.
      Firestore then sorts ASCENDING — and composite index directions are not
      interchangeable, so the `coupleId + createdAt DESC` index the feed uses does
      not serve it. The emulator does not enforce indexes, so this query had never
      once run anywhere that could tell us. Added by hand to
      `firestore.indexes.json` rather than via the console link, since a
      console-created index does not exist in prod. Build time ~5 minutes on a
      near-empty collection. A comment at the query now names the index and why it
      differs from the feed's.*
      *Every other query verified against real dev and needed no new index: the feed
      listener and its pagination, incoming requests, the outgoing request, the
      pairing duplicate-check, `memberIds` array-contains, **P3-01**'s
      `secretState == 'opening'` sweep, and both of **P2-36**'s sweep queries.*
      ***`memberIds` array-contains: the P2-35 claim was correct.*** *It is served by
      the automatic single-field index; it ran inside `ensureUserProfile` against
      real Firestore for every new account in this pass and never asked for one.*
      *The streak tick's couple scan needs no index at all — an unfiltered
      `collection("couples").limit(200)` read, so there is nothing to declare.*
      *6 composite indexes declared before this pass, 7 after; declared and deployed
      sets match exactly.*
- [x] **P3-07** Onboarding flow *(includes PI-02 — gates external testing)*
      **Two screens: what the space is, then how secrets really work.**
      *Three were drafted and the third cut. It explained that a code pairs you with
      exactly one person — which is what the pairing screen itself says two taps
      later, so it was padding in front of the flow brief §11 calls the single most
      important metric. Two also makes the disclosure half of onboarding rather than
      an item in a list, which is the requirement.*
      *Position in the gate is the other decision: after the profile exists and
      **before** the coupleId branch. It explains the space before anyone invites
      another person into it, and because PI-02 gates external testing, a tester who
      paired on an older build still meets it rather than skipping it by having been
      early. Behind the profile branch, not ahead of it — a signed-in user with no
      document yet is still loading, and showing onboarding there would race the
      sign-up write.*
      *No collision with **P2-26**: the pairing moment is reached only via the
      coupleId branch, which onboarding sits ahead of, so the two can never both
      want the screen.*
      *Finishing records the flag and navigates nothing — the profile stream carries
      `onboardingSeenAt` and the gate moves, exactly as the pairing moment works.
      A failed write does not trap the reader; worst case they see it once more.*

---

## Phase 4 — Ship

- [ ] **P4-01** Home screen widget (native, both platforms)
- [ ] **P4-03** Store submission prep — app icon, launch screen, listings,
      screenshots, privacy policy
- [ ] **P4-05** Crashlytics
- [ ] **P4-06** Upgrade **prod** to Blaze; set a budget alert
- [ ] **P4-09** Upload an APNs key to Firebase, so iOS push actually delivers.
      *The client side of **P3-04** is complete on iOS and was built and run on the
      simulators; `getToken()` simply returns null with no APNs credential. This is a
      key upload in the Firebase console and nothing else — no code, no rewrite. Needs
      the paid Apple Developer account, same one **P2-20** and **P4-07** wait on.*
- [ ] **P4-10** Register the RELEASE keystore's SHA-1 and SHA-256 in Firebase.
      ***Google sign-in fails on release builds until this is done*** — the classic
      ships-broken-to-testers bug, because debug builds work perfectly and nothing
      warns you. The release keystore does not exist yet; create it, register both
      fingerprints, re-run `flutterfire configure`, and verify on a release build
      before **P4-07**.
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
- [ ] **D-11** The accept transaction's correctness rests partly on incidental
      mechanisms. Sabotage testing at **P2-18** showed the stale-request sweep's
      `transaction.get(query)` provides the contention that aborts concurrent
      accepts, and the not-pending guard independently catches double-tap. Neither
      was designed for that. Any refactor that moves the sweep out of the transaction
      removes a correctness mechanism while leaving every test green. Warning comment
      is at the call site.
- [ ] **D-13** `couples/{id}.memberNames` is a snapshot from pairing time — a later
      rename does not propagate, so the partner keeps seeing the old name. Same
      accepted trade as **P2-25**'s `fromDisplayName`. The fix is a profile-update
      path that refreshes the couple, and it belongs with whatever task lets someone
      edit their display name — which does not exist yet.
- [ ] **D-12** `ensureUserProfile` absorbs an ALREADY_EXISTS race by re-reading and
      reporting the winner's document. `.create()` was kept over `.set()` deliberately
      — `set` would clobber a document written between the existence check and the
      write. Recheck if the function's read/write shape changes.
- [ ] **D-18** A **second**, different intermittent in the functions suite, seen once
      on 2026-08-03: `clearFirestore()` threw gRPC `CANCELLED` (499, "call already
      cancelled") from a `beforeEach` hook, failing `P2-18 — concurrent accepts`. A
      hook failure, not an assertion — no product behaviour was implicated, and two
      subsequent runs were clean.
      *Recorded rather than shrugged off because **D-14** was closed against a
      different cause (the sweep race), and it would be easy to read that as "the
      flake is fixed" and misfile this one. It is not the same thing.*
      *Suspected trigger: `build:watch` recompiling `functions/lib/` while the suite
      was running — the run started moments after a `pairing.ts` edit, and a functions
      reload mid-suite could plausibly disturb the emulator connection. Untested. If
      it recurs, note whether a rebuild was in flight before blaming the emulator.*
      ***Three for three now.*** *Occurrences at **P3-01**, **P2-40** and **P2-16**,
      every one on the FIRST suite run after a functions source edit, every one the
      same test and the same `clearFirestore` CANCELLED, every one clean on re-run.
      That is no longer a coincidence — it is a reproducible precondition. Next step
      is to stop the watcher, run the suite, and see whether it survives; if it does,
      the fix is a settle-wait in `run-suite.mjs` before the first test.*
      *Second occurrence at **P3-01**, and it corroborates the hypothesis: same test,
      same `clearFirestore` CANCELLED, and again on the FIRST run after a functions
      source edit (`secret.ts` was new, so build:watch had just recompiled). Two for
      two. Clean on re-run both times. Worth trying: pause the watcher, or wait for it
      to settle, before starting the suite.*
      *The identity was captured this time without effort, because `run-suite.mjs`
      names failures and retains the log. That is what D-14 bought.*
- [ ] **D-19** `secretBodies` create does not require a corresponding `items`
      document, so a member can write orphan bodies at arbitrary ids. Raised by the
      **P3-01** audit as minor. A rules-level `exists()` check is **not** the fix:
      **P2-12** writes item and body in one batch, and batch writes evaluate against
      pre-batch state, so the item genuinely does not exist yet. The fix is a write
      counter in `rateLimits`, which belongs with **P3-05**. Blast radius is the
      member's own couple; **P2-36**'s sweep collects them by `coupleId` on unpair.
- [ ] **D-20** **P3-02**'s hourly tick reads every couple document (`COUPLE_BATCH`
      200) to find the ones whose local yesterday is unscored. Whether a couple is due
      depends on their own `streakEvaluatedThrough` and their own zone, so it is not
      a queryable condition — hence a scan. Fine at V1 scale and bounded per tick, but
      it does not scale: at a few thousand couples this is a full read of the
      collection every hour. The fix when it matters is a `streakDueAt` timestamp
      written at evaluation time and queried with a range, which makes the due set
      indexable.
- [ ] **D-21** `firebase.json`'s predeploy hook is the only thing that runs eslint,
      and the emulator never runs predeploy hooks — so lint errors accumulate
      invisibly until a deploy, which is where they are most expensive to discover
      (**P2-16** hit 248). Nothing in the four-suite loop catches them. Add
      `npm --prefix functions run lint` to whatever CI lands, or accept that every
      deploy starts with a lint fix.
- [ ] **D-22** Two throwaway couples and roughly ten `verify-*@onceling.test` accounts
      are left on the dev project from **P2-16**'s verification pass, plus their
      items. Harmless on a test project and not worth admin credentials to remove,
      but dev is no longer a clean slate — anything that counts documents there
      should know. The verification scripts themselves were deleted.
- [ ] **D-23** The Firebase plugin family must be upgraded together. Adding
      `firebase_messaging` at **P3-04** broke the iOS build outright:
      `firebase_auth` pinned firebase-ios-sdk 12.15.0 while messaging wanted 12.17.0,
      and SPM refuses to resolve. `cloud_firestore` then stayed pinned by
      `fake_cloud_firestore` until a full `flutter pub upgrade`. Recovery also needed
      `flutter clean`, a DerivedData wipe and `flutter precache --ios --force`.
      **Android builds fine throughout, so this only surfaces on an iOS build** — do
      not assume a green Android run means the pubspec is coherent.
- [ ] **D-24** The AVD (`Pixel_10_Pro`, `google_apis_playstore`) cannot mint an FCM
      token: `SecurityException: Unknown calling package name
      'com.google.android.gms'`. A Play Store image was expected to work and does not,
      so **push delivery has never been observed on any device**. Everything up to the
      radio is verified. Needs a physical Android phone, or a repaired AVD, before
      P3-04 can be called delivered rather than built.
- [ ] **D-25** `firebase.json` binds all four emulators to `0.0.0.0` rather than the
      default `127.0.0.1` — Auth 9099, Functions 5001, Firestore 8080, UI 4000.
      Required for a physical device to reach the suite over the LAN, and without it
      the packet arrives and is refused. The cost is that **the suite is exposed to
      every host on the local network**, with no auth in front of it: anyone who can
      route to the Mac can read and write the whole Firestore, mint tokens for any
      account through the Auth emulator, and open the UI. Fine on a home network,
      **not on shared or public wifi** — a café, an office, a conference.
      **To revert:** delete the four `"host": "0.0.0.0"` lines in `firebase.json`;
      the default rebinds to loopback. Simulators and the AVD are unaffected either
      way — they reach the host without it. A USB device does not need it either:
      `adb reverse` tunnels to the phone's own loopback, which works once
      `automaticHostMapping` is off (**P2-21**). So the revert is free whenever USB is
      available, and should be the default posture off a trusted network.
- [ ] **D-28** **Prove the orphan half of the prefix-deletion decision on a real
      bucket.** The sweep deletes `couples/{id}/photos/` wholesale rather than walking
      items and deleting each `mediaUrl`, because an upload that succeeded while its
      item write failed leaves an object no document references — and an item-driven
      sweep would visit exactly the non-orphans and miss the entire orphan set. The
      emulator covers this (`pairing_functions.test.mjs` seeds a linked object, an
      orphan and a neighbour, and asserts 2 deleted with the neighbour intact). On dev
      it is unproven: the owner's 2026-08-07 observation of an empty prefix is
      consistent with prefix-deletion AND with item-walking, so it cannot tell them
      apart.
      **The test, on throwaway accounts, destroying nothing anyone cares about:**
      1. Create two accounts on dev and pair them through the callables
         (`ensureUserProfile`, `ensurePairingCode`, `requestPairing`,
         `respondToPairing`) — the same sequence already scripted this session.
      2. Send one photo the ordinary way, so the object AND its `items` document both
         exist. Record the object path.
      3. Write a second object directly to `couples/{id}/photos/orphan.jpg` with **no
         item document** — the upload-succeeded-item-write-failed state, reproduced
         deliberately rather than waited for.
      4. Seed a THIRD couple with its own photo, untouched, as the neighbour control.
         Without it a sweep that deleted the whole bucket would pass.
      5. Unpair, wait for `sweepUnpairedCouple`.
      6. Assert: both objects of the unpaired couple are gone **including the orphan**,
         and the neighbour's survives.
      Step 3 and step 6's orphan clause are the whole point; steps 2 and 4 exist so a
      pass cannot be explained by "it deleted everything" or "it deleted the linked one
      and stopped". Verification needs admin access to list the prefix — a capability
      URL cannot serve, because a stale token returns 403 for a present object and an
      absent one alike, which is how the first attempt at this failed.
- [ ] **D-27** `rules-tests/storage_rules.test.mjs` uses the DEFAULT project namespace,
      breaking CLAUDE.md's one-namespace-per-file rule, and it has to. The Storage
      emulator resolves `firestore.get()` against the emulator's default project, not
      the project the test client uses — so a profile seeded in a private namespace is
      invisible to the membership rule that must read it. **The signature is worth
      recognising: every positive case fails and every negative case passes**, because
      deny-by-evaluation-error is indistinguishable from deny-by-rule. Cost: this
      file's `clearFirestore()` wipes the device seed. The other three rules files keep
      their own namespaces, so no test-to-test collision arises.
- [ ] **D-15** Feed pagination is one growing `limit`, so page N re-delivers the whole
      window: N pages cost 30+60+90+… document reads, quadratic in pages. Chosen at
      **P2-12** so every page stays live and a reaction on an old message updates in
      place. Fine for a two-person thread; revisit if read volume or scrollback depth
      makes it matter. The fix is a live head plus `startAfter` pages, and it costs
      live reactions on everything below the head.
- [ ] **D-16** `fake_cloud_firestore` is a dev dependency as of **P2-12** and does not
      evaluate Security Rules. The Dart tests therefore prove the client asks the right
      question; `rules-tests/items_rules.test.mjs` proves the server would refuse the
      wrong one. Neither alone is sufficient, and a reader of either could mistake it
      for both. It also pulled in nine transitive dev packages.
- [ ] **D-17** The item and body payloads are written in Dart
      (`itemCreatePayload`, `secretBodyPayload`) and mirrored by hand in the P2-12
      rules tests. Dart and JS cannot share a constant, so a change to one must be
      made to the other — and `flutter test` alone will not catch the drift, because
      the Dart side has no rules engine behind it. Same shape as the
      `pairingCodeAlphabet` mirror.
---

## Cut

Scope decided against. Recorded so it doesn't get re-litigated.

Format: `**ID** Description — reason, date`

**P4-02** Onboarding flow — moved to P3-07, since PI-02's honesty disclosure gates
external testing and must ship before Phase 4. 2026-07-31

**P4-04** Store listings and screenshots — merged into P4-03 to keep Phase 4 legible
until submission is close. 2026-07-31
