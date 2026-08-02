# Onceling — Status

**Phase 3 of 4 · Last updated: 2026-08-03**

**Now:** P3-02 — streak calculation (needs **P2-40** for the day boundary)

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

> **Gate:** no external testers — TestFlight or Play internal — until **PI-02** ships.
> Brief §10 requires the honesty disclosure before anyone outside uses the app.

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
- [ ] **M-05** Secrets — `markOpened()` deletes client-side; must move to a Function
- [ ] **M-06** Streaks — hardcoded `47` in two places
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
- [ ] **P2-40** Write `couples/{id}.timezone` at pairing — the **Q3** decision.
      `respondToPairing` still writes it null. The zone is an IANA name taken from the
      accepting partner's device, so the client has to send it: `requestPairing` and
      `respondToPairing` gain a `timezone` argument, validated server-side against a
      known-zone list rather than trusted as a free string. **Never a UTC offset** —
      offsets break twice a year under DST.
      Blocks **P3-02**, which has nothing to read for the day boundary until this
      lands. **P2-39**'s callable should be able to change it afterwards, alongside
      the anniversary; a couple that moves should not have to re-pair.
- [ ] **P2-39** `setAnniversary(date)` callable — the settings edit path for **M-10**.
      A callable, not a write: `couples` denies every client write in every direction,
      which is what makes `coupleId` and the rest of that document trustworthy.
      Must validate that the caller is a member of the couple it names, reject a date
      in the future, and bound how far back it may be set. Until it exists the
      anniversary is whatever the pairing date was, and a couple with a real earlier
      date has no way to say so.
- [ ] **P2-13** Photo upload to Cloud Storage. *Enable the Storage emulator first —
      until it is on, Functions calls to Cloud Storage hit the real dev bucket.*
      *The compose sheet's "Add photo" chip is still a no-op after **P2-12** — the only
      item type the client cannot write. `PhotoMessage`, its mapper branch and its
      `itemKeysFor('photo')` rule already exist and are tested, so this is the upload
      and the `mediaUrl` write, not the model.*
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
- [ ] **P3-02** Streak calculation Function
      *Reads `couples/{id}.timezone` for the day boundary — one shared zone, an IANA
      name, never a UTC offset (**Q3**). **One grace day per week: a missed day does
      not reset the count**, and a genuinely broken streak renders faded rather than
      zeroed, so the history survives having been interrupted (**Q2**). There is no
      hard reset anywhere in this function.*
      *Depends on **P2-40** — `timezone` is still written null, so this has nothing to
      read until that lands.*
- [ ] **P3-03** Milestone triggers — day 100, 365, 500, 1000
      *Unaffected by **Q2**'s forgiveness: milestones count days since
      `anniversaryDate` (**M-10**), not consecutive posting. They are anniversaries,
      a different register from a daily obligation, which is why they survive a
      forgiving streak unchanged.*
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
- [x] **D-14** The functions suite intermittently reported one failure that passed on
      retry with no code change. **Diagnosed and fixed.**
      *It was never a stale build or a `clearFirestore()` race — both were guesses.
      It was `assertPairingInvariant` racing **P2-36**'s sweep trigger. Unpair is
      two-phase: separation is atomic, deletion fires a moment later. In that window
      the couple document legitimately exists listing two members who no longer point
      back at it, and the invariant read that as broken. Sweep wins the race → couple
      gone → pass. Test wins → transitional state → fail. Same code, different
      outcome, which is exactly how it presented.*
      *The fix does not skip unpaired couples, which would trade a flake for a blind
      spot. It asserts the thing that must still hold mid-sweep: **both** members are
      freed, never one. One cleared and one still bound is the orphan the transaction
      exists to prevent, and that now fails loudly even during the window.*
      *Found only because the run named the failing tests. It had been invisible for
      three occurrences.*
      *Third occurrence at **P2-12**: 78/79, then 79/79 on each of three subsequent
      runs. The identity was **not** captured — the run was piped through a
      summary-only `grep`, so the `not ok` line was discarded before it could be read.
      That is the exact mistake this entry was written to prevent. Run the suite to a
      **retained log file** and grep the file, never the pipe.*
      *Fixed structurally rather than remembered: `npm run test:functions` now goes
      through `rules-tests/run-suite.mjs`, which tees the run to `logs/functions.log`
      and prints every `not ok` line on failure. **The log file is the guarantee** —
      it survives whatever the caller did to the streams. The stderr print is a
      secondary help and deliberately does not overclaim: it defeats
      `npm test | grep …` but *not* `npm test 2>&1 | grep …`, which was the actual
      mistake, because that merges stderr into the pipe before the filter runs. Both
      cases verified by sabotaging a test, not assumed. The identity is still not
      captured for the three past occurrences, so the underlying flake is still
      undiagnosed — this only guarantees the next one is legible.*

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