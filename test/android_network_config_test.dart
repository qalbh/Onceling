import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **P2-21** — the debug build permits cleartext HTTP so it can reach the Local
/// Emulator Suite. Release must not.
///
/// Structural rather than behavioural: nothing in a Dart test can observe
/// Android's network security policy, and the failure this guards against is
/// silent in the worst direction — a release build shipping with cleartext
/// permitted looks and behaves exactly like one that does not, until someone
/// inspects traffic.
///
/// The regression these exist for is not "someone edits the XML". It is
/// someone moving it, or referencing it, from `src/main/` — a one-line change
/// that reads as tidying up and quietly applies the debug policy to every
/// build.
void main() {
  final debugConfig = File(
    'android/app/src/debug/res/xml/network_security_config.xml',
  );
  final debugManifest = File('android/app/src/debug/AndroidManifest.xml');
  final mainManifest = File('android/app/src/main/AndroidManifest.xml');

  test('the debug build permits cleartext, and says why', () {
    expect(debugConfig.existsSync(), isTrue);
    final xml = debugConfig.readAsStringSync();

    // base-config rather than a <domain> list: EMULATOR_HOST names arbitrary
    // LAN addresses, and <domain> matches hostnames with no CIDR form.
    expect(xml, contains('cleartextTrafficPermitted="true"'));
    expect(xml, contains('<base-config'));
  });

  test('the debug manifest is what wires it in', () {
    expect(
      debugManifest.readAsStringSync(),
      contains('android:networkSecurityConfig'),
    );
  });

  test(
    'RELEASE inherits Android\'s default — nothing in main references it',
    () {
      // The load-bearing assertion. src/main/ applies to every build type, so a
      // networkSecurityConfig here would permit cleartext in release too.
      expect(
        mainManifest.readAsStringSync(),
        isNot(contains('networkSecurityConfig')),
        reason: 'src/main/ applies to RELEASE builds as well as debug',
      );
    },
  );

  test('no network security config exists outside src/debug/', () {
    // Catches the same mistake arriving as a new file rather than an edit.
    final strayConfigs = Directory('android/app/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('network_security_config.xml'))
        .where((f) => !f.path.contains('/src/debug/'))
        .map((f) => f.path)
        .toList();

    expect(
      strayConfigs,
      isEmpty,
      reason: 'a config outside src/debug/ can reach release builds',
    );
  });

  test('the profile build type does not reference one either', () {
    // `flutter run --profile` is closer to release than debug and is used for
    // performance work; it should not carry a development network policy.
    final profileManifest = File('android/app/src/profile/AndroidManifest.xml');
    if (profileManifest.existsSync()) {
      expect(
        profileManifest.readAsStringSync(),
        isNot(contains('networkSecurityConfig')),
      );
    }
  });
}
