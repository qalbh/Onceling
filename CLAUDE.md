# Onceling — Project Rules

Flutter app. Two paired people, one shared private space. Package name `couple_app`.

Read this before writing code. These rules are not suggestions; if a request conflicts
with one, say so instead of silently working around it.

---

## Definition of done

A change is not complete until all six hold:

1. `flutter analyze` is clean
2. `flutter test` passes, **and the test count is stated with its delta.** A green
   suite proves nothing if you do not check which tests ran. During P2-29 a file
   landed on disk as `" .dart"` — a literal space plus extension — so 8 tests were
   silently skipped and the suite still reported green. If the count does not match
   arithmetic, investigate before proceeding.
3. `dart format lib test` produces no diff
4. New behaviour has a test (see Testing)
5. The relevant box in `STATUS.md` is ticked, in this same change
6. `npm run lint` passes in `functions/` — eslint only runs as a deploy predeploy
   hook, which the emulator never invokes. 248 errors accumulated undetected before
   the first real deploy (**D-21**). Run it with the other suites, not at deploy time.

---

## Naming

The product is **Onceling**. Identifiers are deliberately brand-neutral so a rebrand
stays cheap:

- Bundle ID `dev.qalb.coupleApp` · Android applicationId `dev.qalb.couple_app`
- Dart package `couple_app`
- Firebase projects `qalb-coupleapp-dev` and `qalb-coupleapp-prod`

Do not rename identifiers to match the product. Theme classes use neutral names
(`ThemeColors`, `ThemeGlyphs`) for the same reason. Note the leading `dev.` in the
bundle ID is the reverse-domain TLD, not "development" — never append `.dev` to it.

The Android applicationId and iOS bundle ID differ in case and separator. That is
pre-existing, both are registered in Firebase, and both become permanent at first
store submission. Do not attempt to unify them.

## Architecture

Feature-first. Everything lives under `lib/features/<feature>/`, split into
`screens/`, `widgets/`, and `models/`. Shared theme in `lib/theme/`, shared
utilities in `lib/common/`.

Do not introduce `lib/core/`, `lib/data/`, `lib/domain/`, or any layered/Clean
Architecture structure. The current shape is deliberate.

## State management

Two tiers, and the distinction matters:

**Local UI state → `StatefulWidget` + `setState`.** This is correct, not a
compromise. Sheet expansion flags, tray selection, animation controllers, text field
focus. Do not convert existing `setState` to Riverpod.

**Shared or async state → Riverpod.** Auth session, the pairing relationship, the
feed, anything backed by Firestore or surviving a screen transition. Use
`ConsumerWidget` / `ConsumerStatefulWidget` with `ref.watch`.

Riverpod is added at **P2-07**, with the auth and couple providers. Start **without**
codegen (`@riverpod` annotations / `build_runner`) — plain `Provider` /
`StreamProvider` / `NotifierProvider` declarations. Codegen can come later if
boilerplate becomes a real problem.

Never introduce BLoC, GetX, Redux, MobX, or the standalone `provider` package. One
state library. Note that Riverpod's own `Provider` class is unrelated to the
`provider` package and is the correct thing to use.

## Theming

Colors and typography come from the theme. Never hardcode.

- No raw `Color(0x...)` outside `lib/theme/`.
- No inline `TextStyle(` in widget files at all. Use `TextTheme` entries.
- Every color must be reachable through `Theme.of(context)` so dark mode keeps
  working. `AppColors` exists to *feed* `ColorScheme`, `TextTheme`, and the theme
  extensions — never to be referenced directly from a widget.
- Light and dark share one `_textTheme(ink)` builder. Metrics must not diverge
  between modes; only color does.
- Non-role colors live in the `ThemeColors` extension, reached via `context.palette`.

Both greps must return nothing:

```
grep -rn 'AppColors\.' lib --include="*.dart" | grep -v '/theme/'
grep -rn 'TextStyle(' lib --include="*.dart" | grep -v '/theme/'
```

Fonts (Plus Jakarta Sans, Fraunces) are bundled as assets;
`GoogleFonts.config.allowRuntimeFetching` is `false`. Keep it that way.

**Glyph sizing.** Glyph and icon sizes live in `ThemeGlyphs`, not `TextTheme`.
Decorative glyphs are wrapped in `Glyph`, which pins `TextScaler.noScaling`. Glyphs
that carry content — an emoji sent *as* a message — stay in `TextTheme` and scale.

## Layout and sizing

- Never lift pixel widths off a Figma frame. Values like 320, 327, 343, 375 are the tell.
- Fill the parent with `double.infinity` + padding, `Expanded`, or `Flexible`. Cap
  width with `BoxConstraints(maxWidth: ...)`, never a fixed `width`.
- Fixed sizes are acceptable only for genuinely fixed things: icons, avatars, dots,
  small square tiles.
- Every screen and bottom sheet needs `SafeArea`.
- Any scrollable content needs `SingleChildScrollView` / `ListView`.
- Any sheet containing a `TextField` must handle `MediaQuery.viewInsets.bottom`.

Target minimum width is 360dp. Layouts must survive 200% text scale and landscape
without overflow.

## Security — non-negotiable

The client is untrusted. Assume a modified client.

- **Pairing is a server-side request/accept handshake**, not a claim. Three callables:
  `requestPairing` (**P2-09**), `respondToPairing` (**P2-09b**), `cancelPairingRequest`
  (**P2-09c**). Knowing a code is not enough to pair — the recipient must accept. Never
  fetch a partner's code to the client and compare it there. Never accept a pairing
  the server did not perform. The accept is the transaction that creates the couple,
  sets `coupleId` on both users, rejects all other pending requests for both, and
  deletes both pairing codes.
- A code is an address, not a credential. Knowing it lets you knock, nothing more.
  Never build a flow where entering a code pairs anyone automatically.
- A declined request must expire silently. Never tell the sender they were declined
  (**PI-05**) — it is unkind, and it confirms to a code-guesser that a real person owns
  that code.
- **Secret deletion happens in a Cloud Function** (**P3-01**), never on the client. A
  client that deletes its own copy has not deleted anything.
- **The one-partner invariant is enforced in a transaction and in Firestore Security
  Rules**, not in UI copy. The pairing screen promises "You can only ever be paired
  with one person" — that promise must be true at the data layer, atomically, and
  safe against the handshake's races — chiefly two users accepting each other's
  requests simultaneously, and the same request being accepted twice. See **P2-18**.
- **`coupleId` is the load-bearing field of the pairing model.** Every guarantee
  downstream assumes a client cannot forge or clear it. It is set only by
  **P2-09b**'s transaction and cleared only by the unpair path — both server-side.
  A Security Rule must reject any client write to it in either direction. An
  unrestricted clear is as dangerous as an unrestricted set: it orphans a couple.
- **Profile writes are server-side.** `users/{uid}` is created only by
  `ensureUserProfile` (**P2-35**) via the Admin SDK. `allow create` is `false` — no
  client can create a profile by any route. Consequence: `isWellFormedProfile` does
  not guard creation, because the Admin SDK bypasses rules. The function is the only
  validator on that path, and it guarantees correctness by construction — it writes a
  fixed literal, so no caller-supplied key reaches the document. Any new auth path
  must go through `ensureUserProfile`, never a direct client write.
- Any operation that must not double-apply (pairing, claiming, unpairing, one-time
  reveals) is a transaction or a callable function. Idempotent, safe against double
  taps and races.
- Any future secret-bearing check — a passcode, a lock, a verification step — is
  server-side with rate limiting. Never a client-side comparison, never stored in a
  readable document.
- Every Firestore collection ships with matching Security Rules in the same change
  that introduces it. A collection without rules is not done.
- Push payloads for secrets carry no body text and no preview.
- **Every change to `firestore.rules` must be audited with the
  `firebase-security-rules-auditor` skill before it is committed.** Report the score
  and every finding. A score below 4 blocks the change. The audit is not a substitute
  for rules unit tests (**P2-11**). Both are required: the auditor reviews, the
  emulator proves.

If asked to implement any of the above client-side, refuse and explain why.

## Firebase

Projects `qalb-coupleapp-dev` and `qalb-coupleapp-prod`. IDs are permanent.
`.firebaserc` defaults to dev; switching to prod is deliberate and explicit.

**Build against the Local Emulator Suite, never the cloud project.** Cloud Functions
live in `functions/` — TypeScript, source in `src/`, build output in `lib/`. Emulator
ports, the two watcher processes the emulator depends on, the Node pin, the
`@firebase/app` dependency that looks unused but is not, the Storage-emulator gap and
the seed script all live in **`docs/local-run.md`**. Read it before starting or
restarting the emulator, or before debugging a function whose changes seem not to
apply.

- Minimum iOS is 15.0, forced by the Firebase SDKs. Do not lower it.
- `lib/firebase_options*.dart`, `google-services.json`, and `GoogleService-Info.plist`
  are gitignored. Never commit them, never paste their contents into chat.
- Model for the queries actually run, not relational tidiness. Denormalize where it
  saves reads.
- Handle loading / empty / error states explicitly on every read. All three.
- Paginate lists. Avoid collection scans; use lookup documents keyed by the value
  being searched when uniqueness or O(1) lookup is needed.
- Keep composite indexes in `firestore.indexes.json` in sync with queries (**P3-06**).

## Local run

Simulators, seeded accounts, install order, and how to prove what is actually running
on a device — **`docs/local-run.md`**. Read it before any device walkthrough, and
before trusting anything you saw on a simulator. Every rule in it was earned by a
device verification that silently reported the wrong thing.

## Agent skills

`.claude/skills/` and `.agents/skills/` hold Firebase-authored skills installed by
`firebase init`. Six are kept deliberately:

`firebase-security-rules-auditor` · `firebase-firestore` · `firebase-auth-basics` ·
`firebase-basics` · `firebase-crashlytics` · `xcode-project-setup`

Six more were installed and **deliberately removed**: `firebase-data-connect`,
`firebase-app-hosting-basics`, `firebase-hosting-basics`, `firebase-ai-logic-basics`,
`firebase-remote-config-basics`, `extension-to-functions-codebase`.

Do not reinstall them. Data Connect is a competing database product that contradicts
the Firestore data model in brief §9, and the hosting skills describe a web app,
which brief §7 puts out of scope for V1. If `firebase init` restores them, prune
again and prune the matching entries from `skills-lock.json`.

Any skill that changes content hash in `skills-lock.json` should be re-read before it
is trusted — these are third-party files that shape agent behaviour.

## Navigation

Named routes in `main.dart` for now. When auth-gating lands (signed-out → sign-in,
signed-in-unpaired → pairing, paired → feed), migrate to `go_router` with a single
redirect (**P2-14**). Handle gating in one place, never per-screen.

## Testing

- Any new screen with real interaction gets a widget test.
- Anything server-adjacent gets a unit test: transaction logic, mappers (**P2-17**),
  validators.
- Security Rules changes get rules unit tests run against the emulator. A rule without
  a test proving the negative case — user A cannot read couple B's data — is not done.
- Concurrency claims need concurrency tests (**P2-18**). "Atomic" is not established
  by reading the code; prove it by firing simultaneous operations in a loop and
  asserting exactly one succeeds.
- Set `tester.view.physicalSize` with `addTearDown(tester.view.reset)` when device
  size matters.
- Do not write golden tests test-first; generate the golden from verified output.
- Security Rules tests live in `rules-tests/` and run with `npm test` in that
  directory, not under `flutter test`. Both must pass. When CI exists, it runs both.
- A device walkthrough run after the Node suites is testing a wiped database. Re-seed
  (`docs/local-run.md`) and re-establish any pairing it needs, then confirm the state before
  drawing conclusions — a run that signs in as an unpaired user when you meant a
  paired one looks like it worked. This has silently invalidated a device test more
  than once.
- Rules tests run in parallel under `node --test`. Each test file needs its own
  emulator project namespace; sharing one means `clearFirestore()` in one file wipes
  another mid-run. Two rule bugs during P2-09 were this, not the rules.

## Code conventions

- `build()` stays under ~100 lines. Decompose into named private `StatelessWidget`
  classes, not helper methods returning widgets.
- Dispose every controller.
- Prefer `const` constructors.
- Modern Dart is encouraged: pattern matching, sealed classes, `abstract final class`
  for namespaces.
- Run `dart format lib test` before finishing. Scripted text replacement does not
  produce formatted output — if you edit by pattern, format afterwards.
- Cloud Functions are TypeScript. Do not add `.js` files to `functions/src/`. The
  pairing transaction and secret deletion are exactly the code where a mistyped
  field name should fail at compile time rather than in the emulator.
- `analysis_options.yaml` excludes `build/**`. Swift Package Manager checks plugin
  sources into `build/ios/SourcePackages/`, and without the exclusion the analyzer
  walks other packages' tests — 394 errors after the Firebase dependencies landed.
  Do not remove the exclusion.

## File editing

The working tree has three possible writers — this agent, the IDE's autosave, and the
terminal. They do not coordinate.

- When the IDE is open, **the agent owns file edits.** Do not instruct the user to run
  `sed` or other terminal edits mid-session; stale editor buffers will overwrite them
  on autosave.
- The terminal is for read-only commands: grep, analyze, test, git.
- Verify outcomes with a terminal command against the working tree, never by trusting
  a report of what was changed.

## Working style

- Report what you changed and why. No summary paragraphs of praise.
- If a change touches `pubspec.yaml`, `lib/theme/`, routing, or Security Rules, say so
  explicitly — those are shared surfaces.
- Never run parallel agents that write to the same package. `pubspec.yaml` and any
  generated files are shared state.
- When something is ambiguous and the answer materially changes the build, ask.
  Otherwise make the reasonable choice and state the assumption.
- If a prior instruction turns out to be wrong, say so rather than working around it.

## Status tracking

`STATUS.md` at the repo root is the source of truth for what's done and what's next.
Its own maintenance rules are at the top of that file — follow them.

- Read it at the start of any session that touches feature work.
- Tick the relevant box in the **same change** that completes the task.
- Update **Last updated**, the **Phase** line, and **Now** whenever you tick anything.
- Never mark a **Decision** (Q1–Q5) resolved. Those belong to the owner. If the code
  implies an answer, note it in the description — don't tick it.
- New tasks get the next free ID. IDs are frozen; never renumber. Retired scope moves
  to **Cut** with its ID intact, not ticked as done.