import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/feed/models/sample_thread.dart';
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
        signedInOverrides(coupleId: 'couple-1', memberNames: null),
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

  test('the resolver prefers the couple over the mock map', () async {
    final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
    await settle(c);
    final resolve = c.read(memberNameResolverProvider);

    expect(resolve('uid-test'), 'Maya', reason: 'me');
    expect(resolve('uid-partner'), 'Devon', reason: 'from memberNames');
  });

  test('the mock fallback still resolves the two sample uids', () async {
    // Keeps the sample thread readable until P2-12 replaces its items.
    final c = containerWith(signedInOverrides(coupleId: 'couple-1'));
    await settle(c);
    final resolve = c.read(memberNameResolverProvider);

    expect(resolve(mayaUid), 'Maya');
    expect(resolve(devonUid), 'Devon');
  });

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
}
