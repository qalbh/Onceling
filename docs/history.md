# Onceling — History

The record, not the plan. Everything here is finished work moved out of
`STATUS.md` so that file stays a working document — the details were preserved
verbatim on arrival, and nothing here is an instruction. When a debt item is
closed, its whole entry moves here; open items and the per-task records of HOW
things were built stay in `STATUS.md`.

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

---

## Closed debt

Moved here with their entries intact, in ID order.

- [x] **D-05** `dart format` drift on 16 files from the theming refactor
- [x] **D-10** The `fromUid`+`toUid`+`status` composite index for the duplicate-check
      query is declared in `firestore.indexes.json` but untested — the emulator does
      not enforce indexes. Verify against dev before **P2-16**.
      *Closed at **P2-16**/**P3-06**. The duplicate-check index works — it ran inside
      `requestPairing` against real dev. **But the warning was right about a
      different query**: the streak tick needed a `coupleId + createdAt ASC` index
      that was not in the file and would have failed on every scheduled run. D-10 was
      opened about one query and caught a second nobody was looking at.*
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
- [x] **D-26** **Photo immutability was NOT enforced, on real Firebase, until it was
      measured.** `allow update: if false` never fires: both the emulator and dev
      evaluate a write to an existing path against `create`, so the update rule is
      unreachable. Dev *accepted* a sender overwriting a delivered photo. Fixed by
      adding `resource == null` to the create rule; re-measured on dev — overwrite
      rejected, fresh upload accepted.
      ***The lesson is about the shape of the evidence, not about Storage.*** *The
      original rule read correctly, passed review, and scored 4/5 in the audit. The
      emulator could not exercise it, so it was recorded as "correct by the docs,
      unproven locally" — which sounded like caution and was actually a guess. It took
      one real request to show the rule had never worked. **A rule nobody has fired in
      anger is a hypothesis.***
      *Residual, both still true and both bounded: content type is client-declared
      rather than sniffed (blast radius is one couple's own 5MB objects, readable by
      its two members), and nothing caps the NUMBER of objects a member may upload —
      rules cannot count, so that needs App Check or a Function-side quota.*
      *Cost of the fix: the emulator reports a non-null `resource` for brand-new
      objects, so the guard refuses every legitimate upload there. Three tests in
      `storage_rules.test.mjs` now assert the EMULATOR's behaviour with the divergence
      spelled out, and a structural test asserts the guard is still in the file —
      because deleting it would make the emulator suite greener and the product wrong.*
