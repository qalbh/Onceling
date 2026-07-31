import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/common/providers.dart';
import 'package:couple_app/features/auth/auth_service.dart';
import 'package:couple_app/features/auth/models/user_profile.dart';
import 'package:couple_app/features/pairing/pairing_service.dart';

/// The redirect only ever asks "is there a user" — no member is touched, so a
/// null-returning [noSuchMethod] is safe here and fails loudly anywhere else.
class FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

UserProfile fakeProfile({String? coupleId, String? pairingCode}) => UserProfile(
  uid: 'uid-test',
  displayName: 'Maya',
  favoriteEmojis: const ['❤️'],
  coupleId: coupleId,
  pairingCode: pairingCode,
);

/// Records calls; never reaches the Functions emulator.
class FakePairingService implements PairingService {
  FakePairingService({this.code = 'MK4Q7B'});

  final String code;
  final List<String> calls = [];

  @override
  Future<String> ensurePairingCode() async {
    calls.add('ensurePairingCode');
    return code;
  }

  @override
  Future<String> requestPairing(String code) async {
    calls.add('requestPairing:$code');
    return 'req-1';
  }

  @override
  Future<void> cancelPairingRequest(String requestId) async {
    calls.add('cancelPairingRequest:$requestId');
  }
}

/// Overrides for a signed-out session: the gate lands on sign-in.
List<Override> signedOutOverrides() => [
  authStateProvider.overrideWith((ref) => Stream.value(null)),
  currentUserProvider.overrideWith((ref) => Stream.value(null)),
  pairingServiceProvider.overrideWithValue(FakePairingService()),
];

/// Overrides for a signed-in session with the given pairing state.
///
/// [pairingCode] defaults to a claimed code so the pairing screen does not
/// fire `ensurePairingCode` during unrelated tests.
List<Override> signedInOverrides({
  String? coupleId,
  String? pairingCode = 'MK4Q7B',
  PairingService? pairing,
}) => [
  authStateProvider.overrideWith((ref) => Stream.value(FakeUser())),
  currentUserProvider.overrideWith(
    (ref) =>
        Stream.value(fakeProfile(coupleId: coupleId, pairingCode: pairingCode)),
  ),
  pairingServiceProvider.overrideWithValue(pairing ?? FakePairingService()),
];

/// A session whose auth state can be flipped mid-test — sign-out goes through
/// [service] and lands on the streams the router is watching.
///
/// Each subscriber first receives the current value, then live updates. A bare
/// broadcast stream would drop the initial signed-in event: it fires before
/// the providers subscribe, and the app would never leave splash.
class FakeSession {
  User? _user = FakeUser();
  final _controller = StreamController<User?>.broadcast();
  late final service = _FakeAuthService(this);

  void _set(User? user) {
    _user = user;
    _controller.add(user);
  }

  List<Override> overrides({String? coupleId}) => [
    authStateProvider.overrideWith((ref) async* {
      yield _user;
      yield* _controller.stream;
    }),
    currentUserProvider.overrideWith((ref) async* {
      UserProfile? profileOf(User? user) => user == null
          ? null
          : fakeProfile(coupleId: coupleId, pairingCode: 'MK4Q7B');
      yield profileOf(_user);
      yield* _controller.stream.map(profileOf);
    }),
    authServiceProvider.overrideWithValue(service),
    pairingServiceProvider.overrideWithValue(FakePairingService()),
  ];

  void dispose() {
    _controller.close();
  }
}

class _FakeAuthService implements AuthService {
  _FakeAuthService(this._session);

  final FakeSession _session;

  @override
  Future<void> signIn({required String email, required String password}) async {
    _session._set(FakeUser());
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _session._set(FakeUser());
  }

  @override
  Future<void> signOut() async {
    _session._set(null);
  }
}
