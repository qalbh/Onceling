import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/pairing/couple_names.dart';

import 'test_doubles.dart';

/// **M-02** — names come from the signed-in profile and the couple's
/// denormalised `memberNames`, never from a hardcoded map on a real screen.
void main() {
  ProviderContainer containerWith(List<Override> overrides) {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }

  /// Providers derive from streams, so let the first values land.
  Future<void> settle(ProviderContainer c) async {
    c.listen(coupleProvider, (_, _) {});
    c.listen(currentUserProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
  }

  test('my own name comes from my profile', () async {
    final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
    await settle(c);
    expect(c.read(myNameProvider), 'Maya');
  });

  test("the partner's name comes from the couple, not their profile", () async {
    final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
    await settle(c);
    // users/ is owner-only; this is the whole point of denormalising.
    expect(c.read(partnerNameProvider), 'Devon');
  });

  test(
    'a couple with no memberNames degrades, it does not blank or crash',
    () async {
      // Every couple formed before M-02, including both simulator accounts.
      final c = containerWith(
        signedInOverrides(coupleId: 'couple-1', withNames: false),
      );
      await settle(c);

      expect(c.read(partnerNameProvider), unknownMemberName);
      expect(c.read(partnerNameProvider), isNotEmpty);
      // And the title does not render half a name.
      expect(c.read(coupleTitleProvider), unknownMemberName);
      expect(c.read(coupleTitleProvider).contains('&'), isFalse);
    },
  );

  test('an unpaired user has no partner name', () async {
    final c = containerWith(signedInOverrides());
    await settle(c);
    expect(c.read(partnerNameProvider), unknownMemberName);
  });

  test('the couple title is both names when unnamed', () async {
    final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
    await settle(c);
    // coupleName is null on every real couple; nothing sets it yet.
    expect(c.read(coupleTitleProvider), 'Maya & Devon');
  });

  test('an explicit coupleName wins over the derived title', () async {
    final c = containerWith([
      ...signedInOverrides(coupleId: 'couple-1'),
      coupleProvider.overrideWith(
        (ref) => Stream.value(fakeCouple(coupleName: 'The Cottage')),
      ),
    ]);
    await settle(c);
    expect(c.read(coupleTitleProvider), 'The Cottage');
  });

  test(
    'the resolver reads me from the profile and them from the couple',
    () async {
      final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
      await settle(c);
      final resolve = c.read(memberNameResolverProvider);

      expect(resolve('uid-test'), 'Maya', reason: 'me');
      expect(resolve('uid-partner'), 'Devon', reason: 'from memberNames');
    },
  );

  test(
    'a uid outside the couple gets the neutral label, not a mock name',
    () async {
      // Rewritten at P2-12: this used to assert that `mockMembers` resolved the
      // two sample uids. With the sample thread deleted there is no stand-in
      // identity left to fall back to, and inventing one for a uid that is not
      // a member would be a lie about who is in the couple.
      final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
      await settle(c);
      final resolve = c.read(memberNameResolverProvider);

      expect(resolve('uid-maya'), unknownMemberName);
      expect(resolve('uid-devon'), unknownMemberName);
    },
  );

  test('an unknown uid gets the neutral label, never a blank', () async {
    final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
    await settle(c);
    expect(c.read(memberNameResolverProvider)('nobody'), unknownMemberName);
  });

  test('initials come from the resolved name', () async {
    final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
    await settle(c);
    final initial = c.read(memberInitialResolverProvider);

    expect(initial('uid-test'), 'M');
    expect(initial('uid-partner'), 'D');
    expect(initial('nobody'), unknownMemberName.characters.first.toUpperCase());
  });

  group('M-10 — the anniversary line', () {
    List<Override> withAnniversary(DateTime? date, {DateTime? now}) => [
      ...signedInOverrides(coupleId: 'couple-1', anniversaryDate: date),
      if (now != null) nowProvider.overrideWithValue(() => now),
    ];

    test('reads as a day count and a date', () async {
      final c = containerWith(
        withAnniversary(
          DateTime(2023, 11, 4),
          // Pinned: a test that asserts a day count must not read the wall
          // clock, or it changes its own answer overnight.
          now: DateTime(2026, 7, 25),
        ),
      );
      await settle(c);
      expect(
        c.read(anniversaryLineProvider),
        '994 days · since 4 November 2023',
      );
    });

    test(
      'a couple with no anniversary degrades neutrally, not blank',
      () async {
        // Every couple paired before M-10. No migration by design, same as
        // memberNames — so this must read as something true, not as an error
        // and not as a date nobody chose.
        final c = containerWith(withAnniversary(null));
        await settle(c);

        expect(c.read(anniversaryLineProvider), unknownAnniversary);
        expect(c.read(anniversaryLineProvider), isNotEmpty);
        expect(c.read(anniversaryLineProvider).contains('1970'), isFalse);
        expect(c.read(anniversaryLineProvider).contains('days'), isFalse);
      },
    );

    test('the day it is set, it does not read "0 days"', () async {
      // Pairing day. A zero count reads as a bug rather than as today.
      final c = containerWith(
        withAnniversary(
          DateTime(2026, 7, 25, 9),
          now: DateTime(2026, 7, 25, 23),
        ),
      );
      await settle(c);
      expect(c.read(anniversaryLineProvider), 'since 25 July 2026');
    });

    test('one day is singular', () async {
      final c = containerWith(
        withAnniversary(DateTime(2026, 7, 24), now: DateTime(2026, 7, 25)),
      );
      await settle(c);
      expect(c.read(anniversaryLineProvider), '1 day · since 24 July 2026');
    });

    test('the count ticks at midnight, not at the hour it was set', () async {
      // 11pm yesterday to 1am today is two hours, and one day.
      final c = containerWith(
        withAnniversary(
          DateTime(2026, 7, 24, 23),
          now: DateTime(2026, 7, 25, 1),
        ),
      );
      await settle(c);
      expect(c.read(anniversaryLineProvider), '1 day · since 24 July 2026');
    });

    test('settings shows the date alone, and says so when unset', () async {
      final set = containerWith(withAnniversary(DateTime(2023, 11, 4)));
      await settle(set);
      expect(set.read(anniversaryLabelProvider), '4 November 2023');

      final unset = containerWith(withAnniversary(null));
      await settle(unset);
      expect(unset.read(anniversaryLabelProvider), 'Not set');
    });
  });
}
