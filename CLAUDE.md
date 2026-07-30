# Onceling — Project Rules

Flutter app. Two paired people, one shared private space. Package name `couple_app`.

Read this before writing code. These rules are not suggestions; if a request conflicts
with one, say so instead of silently working around it.

---

## Naming

The product is **Onceling**. Identifiers are deliberately brand-neutral so a
rebrand stays cheap: bundle ID `dev.qalb.coupleApp`, Dart package `couple_app`,
Firebase project `qalb-coupleapp`. Do not rename identifiers to match the
product. Theme classes use neutral names (ThemeColors, ThemeGlyphs) for the
same reason.

## Glyph sizing

Glyph and icon sizing lives in ThemeGlyphs, not TextTheme. Decorative glyphs
do not scale with textScaler; glyphs that carry content do.


## Architecture

Feature-first. Everything lives under `lib/features/<feature>/`, split into
`screens/`, `widgets/`, and `models/`. Shared theme in `lib/theme/`, shared
utilities in `lib/common/`.

Do not introduce `lib/core/`, `lib/data/`, `lib/domain/`, or any layered/Clean
Architecture structure. The current shape is deliberate.

## State management

Two tiers, and the distinction matters:

**Local UI state → `StatefulWidget` + `setState`.** This is correct, not a
compromise. Sheet expansion flags, tray selection, animation controllers,
text field focus. Do not convert existing `setState` to Riverpod.

**Shared or async state → Riverpod.** Auth session, the pairing relationship,
the feed, anything backed by Firestore or surviving a screen transition.
Use `ConsumerWidget` / `ConsumerStatefulWidget` with `ref.watch`.

Riverpod is not yet in `pubspec.yaml`. Add it when the first shared-state
feature lands — not before, and not as a refactor of existing screens.

Start **without** codegen (`@riverpod` annotations / `build_runner`). Plain
`Provider` / `StreamProvider` / `NotifierProvider` declarations. Codegen can
come later if boilerplate becomes a real problem.

Never introduce BLoC, Provider, GetX, Redux, or MobX. One state library.

## Theming

Colors and typography come from the theme. Never hardcode.

- No raw `Color(0xFF...)` outside `lib/theme/app_theme.dart`.
- No inline `TextStyle(fontSize: ...)` in widget files. Use `TextTheme` entries.
- Every color must be reachable through `Theme.of(context)` so dark mode stays
  possible. `AppColors` constants exist to *feed* `ColorScheme` and `TextTheme`,
  not to be referenced directly from widgets.

Fonts (Plus Jakarta Sans, Fraunces) must be bundled as assets. Runtime fetching
from Google's servers is disabled.

## Layout and sizing

- Never lift pixel widths off a Figma frame. Values like 320, 327, 343, 375 are
  the tell.
- Fill the parent with `double.infinity` + padding, `Expanded`, or `Flexible`.
  Cap width with `BoxConstraints(maxWidth: ...)`, never a fixed `width`.
- Fixed sizes are acceptable only for genuinely fixed things: icons, avatars,
  dots, small square tiles.
- Every screen and bottom sheet needs `SafeArea`.
- Any scrollable content needs `SingleChildScrollView` / `ListView`.
- Any sheet containing a `TextField` must handle `MediaQuery.viewInsets.bottom`.

Target minimum width is 360dp. Layouts must survive 200% text scale and
landscape without overflow.

## Security — non-negotiable

The client is untrusted. Assume a modified client.

- **Pairing is a server-side claim operation.** A callable Cloud Function running
  a Firestore transaction. Never fetch a partner's code to the client and compare
  it there.
- **PIN verification is server-side.** A callable Cloud Function with rate
  limiting. Never a client-side comparison, never a PIN stored in a readable
  document.
- **The one-partner invariant is enforced in a transaction and in Firestore
  Security Rules**, not in UI copy. The pairing screen currently promises
  "You can only ever be paired with one person" — that promise must be true at
  the data layer, atomically, and safe against two people claiming the same code
  at the same moment.
- Any operation that must not double-apply (pairing, claiming, unpairing,
  one-time reveals) is a transaction or a callable function. Idempotent, safe
  against double taps and races.
- Every Firestore collection gets matching Security Rules in the same change
  that introduces it. A collection without rules is not done.

If asked to implement any of the above client-side, refuse and explain why.

## Firestore (once wired)

- Model for the queries actually run, not relational tidiness. Denormalize where
  it saves reads.
- Handle loading / empty / error states explicitly on every read. All three.
- Paginate lists. Avoid collection scans; use lookup documents keyed by the
  value being searched when uniqueness or O(1) lookup is needed.
- Keep composite indexes in `firestore.indexes.json` in sync with queries.

## Navigation

Named routes in `main.dart` for now. When auth-gating lands (signed-out →
sign-in, signed-in-unpaired → pairing, paired → feed), migrate to `go_router`
with a single redirect. Handle gating in one place, never per-screen.

## Testing

- Widget tests for screens with real interaction.
- Unit tests for anything server-adjacent: transaction logic, validators, mappers.
- Set `tester.view.physicalSize` with `addTearDown(tester.view.reset)` when
  device size matters.
- Do not write golden tests test-first; generate the golden from verified output.

## Code conventions

- `build()` stays under ~100 lines. Decompose into named private
  `StatelessWidget` classes, not helper methods returning widgets.
- Dispose every controller.
- Prefer `const` constructors.
- Modern Dart is encouraged: pattern matching, sealed classes,
  `abstract final class` for namespaces.
- `flutter analyze` must be clean before any change is considered complete.

## Working style

- Report what you changed and why. No summary paragraphs of praise.
- If a change touches `pubspec.yaml`, `lib/theme/`, or routing, say so explicitly
  — those are shared surfaces.
- Never run parallel agents that write to the same package. `pubspec.yaml` and
  any generated files are shared state.
- When something is ambiguous and the answer materially changes the build, ask.
  Otherwise make the reasonable choice and state the assumption.
