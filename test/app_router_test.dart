import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/app_router.dart';

/// The auth gate is one pure function; these pin every branch of it.
void main() {
  String? resolve({
    bool isLoadingAuth = false,
    bool isSignedIn = false,
    bool isLoadingProfile = false,
    bool profileExists = false,
    String? coupleId,
    String currentLocation = AppRoutes.splash,
  }) {
    return resolveRedirect(
      isLoadingAuth: isLoadingAuth,
      isSignedIn: isSignedIn,
      isLoadingProfile: isLoadingProfile,
      profileExists: profileExists,
      coupleId: coupleId,
      currentLocation: currentLocation,
    );
  }

  group('sign-out ordering', () {
    // Auth and the profile document do not clear together. Device traces of a
    // sign-out showed signedIn=false while the profile stream still held the
    // old paired value, for about 20ms. The gate is only correct here because
    // the signed-out branch is evaluated before anything that reads coupleId.
    test('routes on a stale profile during sign-out', () {
      expect(
        resolve(
          isSignedIn: false,
          profileExists: true,
          coupleId: 'couple-1',
          currentLocation: AppRoutes.settings,
        ),
        AppRoutes.signIn,
        reason:
            'a signed-out user must not be routed on a profile they no '
            'longer have a session for',
      );
    });

    test('a stale profile cannot reach the feed or the paired moment', () {
      for (final location in [AppRoutes.feed, AppRoutes.settings]) {
        expect(
          resolve(
            isSignedIn: false,
            profileExists: true,
            coupleId: 'couple-1',
            currentLocation: location,
          ),
          AppRoutes.signIn,
        );
      }
    });

    test('the same window with no couple also lands on sign-in', () {
      expect(
        resolve(
          isSignedIn: false,
          profileExists: true,
          currentLocation: AppRoutes.pairing,
        ),
        AppRoutes.signIn,
      );
    });
  });

  group('loading auth', () {
    test('holds on splash from anywhere', () {
      expect(
        resolve(isLoadingAuth: true, currentLocation: AppRoutes.signIn),
        AppRoutes.splash,
      );
      expect(
        resolve(isLoadingAuth: true, currentLocation: AppRoutes.feed),
        AppRoutes.splash,
      );
    });

    test('already on splash stays put — no redirect loop', () {
      expect(resolve(isLoadingAuth: true), isNull);
    });

    test('does NOT fall through to sign-in while loading', () {
      // The cold-start flash: a signed-in user must never glimpse sign-in.
      expect(resolve(isLoadingAuth: true), isNot(AppRoutes.signIn));
    });
  });

  group('signed out', () {
    test('lands on sign-in from anywhere', () {
      expect(resolve(currentLocation: AppRoutes.feed), AppRoutes.signIn);
      expect(resolve(currentLocation: AppRoutes.settings), AppRoutes.signIn);
      expect(resolve(currentLocation: AppRoutes.splash), AppRoutes.signIn);
    });

    test('already at sign-in stays put', () {
      expect(resolve(currentLocation: AppRoutes.signIn), isNull);
    });
  });

  group('signed in, profile not settled', () {
    test('profile loading holds on splash', () {
      expect(
        resolve(
          isSignedIn: true,
          isLoadingProfile: true,
          currentLocation: AppRoutes.signIn,
        ),
        AppRoutes.splash,
      );
    });

    test('profile absent is loading, NOT unpaired', () {
      // The sign-up race: account exists, document write still in flight.
      // Bouncing to pairing here is the bug this branch exists to prevent.
      expect(
        resolve(isSignedIn: true, profileExists: false),
        isNull, // already on splash
      );
      expect(
        resolve(
          isSignedIn: true,
          profileExists: false,
          currentLocation: AppRoutes.signIn,
        ),
        AppRoutes.splash,
      );
    });
  });

  group('signed in, unpaired', () {
    test('coupleId null routes to pairing', () {
      expect(resolve(isSignedIn: true, profileExists: true), AppRoutes.pairing);
    });

    test('already at pairing stays put', () {
      expect(
        resolve(
          isSignedIn: true,
          profileExists: true,
          currentLocation: AppRoutes.pairing,
        ),
        isNull,
      );
    });

    test('settings is reachable while unpaired — sign-out lives there', () {
      expect(
        resolve(
          isSignedIn: true,
          profileExists: true,
          currentLocation: AppRoutes.settings,
        ),
        isNull,
      );
    });

    test('feed is NOT reachable while unpaired', () {
      expect(
        resolve(
          isSignedIn: true,
          profileExists: true,
          currentLocation: AppRoutes.feed,
        ),
        AppRoutes.pairing,
      );
    });
  });

  group('signed in, paired', () {
    test('coupleId set routes to feed', () {
      expect(
        resolve(isSignedIn: true, profileExists: true, coupleId: 'c1'),
        AppRoutes.feed,
      );
    });

    test('already at feed stays put', () {
      expect(
        resolve(
          isSignedIn: true,
          profileExists: true,
          coupleId: 'c1',
          currentLocation: AppRoutes.feed,
        ),
        isNull,
      );
    });

    test('settings and the secret reveal ride on top of feed', () {
      for (final location in [AppRoutes.settings, AppRoutes.secretReveal]) {
        expect(
          resolve(
            isSignedIn: true,
            profileExists: true,
            coupleId: 'c1',
            currentLocation: location,
          ),
          isNull,
          reason: '$location must not be yanked back to feed',
        );
      }
    });

    test('pairing bounces forward to feed once paired', () {
      expect(
        resolve(
          isSignedIn: true,
          profileExists: true,
          coupleId: 'c1',
          currentLocation: AppRoutes.pairing,
        ),
        AppRoutes.feed,
      );
    });
  });

  group('transitions', () {
    test('signing out at settings goes to sign-in', () {
      expect(resolve(currentLocation: AppRoutes.settings), AppRoutes.signIn);
    });

    test('coupleId appearing while on pairing moves to feed', () {
      // The emulator scenario: set coupleId by hand, app moves without restart.
      expect(
        resolve(
          isSignedIn: true,
          profileExists: true,
          coupleId: 'c1',
          currentLocation: AppRoutes.pairing,
        ),
        AppRoutes.feed,
      );
    });

    test('profile deletion mid-session falls back to splash, not a crash', () {
      expect(
        resolve(
          isSignedIn: true,
          profileExists: false,
          currentLocation: AppRoutes.feed,
        ),
        AppRoutes.splash,
      );
    });
  });
}
