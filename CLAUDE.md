# Onceling — Project Rules

Flutter app. Two paired people, one shared private space. Package name `couple_app`.

Read this before writing code. These rules are not suggestions; if a request conflicts
with one, say so instead of silently working around it.

---

## Definition of done

A change is not complete until all five hold:

1. `flutter analyze` is clean
2. `flutter test` passes
3. `dart format lib test` produces no diff
4. New behaviour has a test (see Testing)
5. The relevant box in `STATUS.md` is ticked, in this same change

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

Start **without** codegen (`@riverpod` annotations / `build_runner`). Plain
`Provider` / `StreamProvider` / `NotifierProvider` declarations. Codegen can come
later if boilerplate becomes a real problem.

Never introduce BLoC, Provider, GetX, Redux, or MobX. One state library.

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

- **Pairing is a server-side claim operation.** A callable Cloud Function running a
  Firestore transaction. Never fetch a partner's code to the client and compare it
  there. Never accept a pairing that the server did not perform.
- **Secret deletion happens in a Cloud Function**, never on the client. A client that
  deletes its own copy has not deleted anything.
- **The one-partner invariant is enforced in a transaction and in Firestore Security
  Rules**, not in UI copy. The pairing screen promises "You can only ever be paired
  with one person" — that promise must be true at the data layer, atomically, and
  safe against two people claiming the same code at the same moment.
- Any operation that must not double-apply (pairing, claiming, unpairing, one-time
  reveals) is a transaction or a callable function. Idempotent, safe against double
  taps and races.
- Any future secret-bearing check — a passcode, a lock, a verification step — is
  server-side with rate limiting. Never a client-side comparison, never stored in a
  readable document.
- Every Firestore collection ships with matching Security Rules in the same change
  that introduces it. A collection without rules is not done.
- Push payloads for secrets carry no body text and no preview.

If asked to implement any of the above client-side, refuse and explain why.

## Firebase

Projects `qalb-coupleapp-dev` and `qalb-coupleapp-prod`. IDs are permanent.

- **Build against the Local Emulator Suite, not the cloud project.** Wipe between
  runs, test concurrent writes, run Security Rules unit tests. The dev cloud project
  is for device testing with real push, not for iteration.
- Functions can be built and tested on the Spark plan via the emulator. Blaze is only
  required to deploy.
- `lib/firebase_options*.dart`, `google-services.json`, and `GoogleService-Info.plist`
  are gitignored. Never commit them, never paste their contents into chat.
- Model for the queries actually run, not relational tidiness. Denormalize where it
  saves reads.
- Handle loading / empty / error states explicitly on every read. All three.
- Paginate lists. Avoid collection scans; use lookup documents keyed by the value
  being searched when uniqueness or O(1) lookup is needed.
- Keep composite indexes in `firestore.indexes.json` in sync with queries.

## Navigation

Named routes in `main.dart` for now. When auth-gating lands (signed-out → sign-in,
signed-in-unpaired → pairing, paired → feed), migrate to `go_router` with a single
redirect. Handle gating in one place, never per-screen.

## Testing

- Any new screen with real interaction gets a widget test.
- Anything server-adjacent gets a unit test: transaction logic, mappers, validators.
- Security Rules changes get rules unit tests. A rule without a test proving the
  negative case — user A cannot read couple B's data — is not done.
- Set `tester.view.physicalSize` with `addTearDown(tester.view.reset)` when device
  size matters.
- Do not write golden tests test-first; generate the golden from verified output.

## Code conventions

- `build()` stays under ~100 lines. Decompose into named private `StatelessWidget`
  classes, not helper methods returning widgets.
- Dispose every controller.
- Prefer `const` constructors.
- Modern Dart is encouraged: pattern matching, sealed classes, `abstract final class`
  for namespaces.
- Run `dart format lib test` before finishing. Scripted text replacement does not
  produce formatted output — if you edit by pattern, format afterwards.

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