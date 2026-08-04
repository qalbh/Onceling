import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/emulator_host.dart';

/// **P2-21** — the emulator host is different on every target, and getting it
/// wrong fails identically in all cases: the app hangs, then errors, with
/// nothing naming the host.
///
/// `Platform.isAndroid` is false under `flutter test` (it runs on the host VM)
/// and no device exists, so `resolve()` can never exercise the interesting
/// branches. `hostFor` is the pure decision behind it and takes both facts as
/// arguments, which is the only reason the matrix below is testable at all.
void main() {
  group('the host decision', () {
    test('the Android EMULATOR gets the NAT alias', () {
      expect(
        EmulatorHost.hostFor(isAndroid: true, isPhysicalDevice: false),
        EmulatorHost.androidEmulator,
      );
    });

    test('a physical Android device NEVER gets the NAT alias', () {
      // The bug this file exists for. 10.0.2.2 is the emulator's alias for the
      // host loopback; on a handset it is an address that cannot resolve, and
      // the failure reads as a network fault rather than a misconfiguration.
      // In practice `refusalFor` stops this case before it is used at all.
      expect(
        EmulatorHost.hostFor(isAndroid: true, isPhysicalDevice: true),
        isNot(EmulatorHost.androidEmulator),
      );
    });

    test('iOS simulators and desktop share the host loopback', () {
      expect(
        EmulatorHost.hostFor(isAndroid: false, isPhysicalDevice: false),
        EmulatorHost.loopback,
      );
    });

    test('a physical iOS device gets the same fallback as Android', () {
      // No adb reverse equivalent here, so the warning matters more — but the
      // address is still the only defensible default.
      expect(
        EmulatorHost.hostFor(isAndroid: false, isPhysicalDevice: true),
        EmulatorHost.loopback,
      );
    });

    test('no combination of inputs produces an empty host', () {
      for (final android in [true, false]) {
        for (final physical in [true, false]) {
          expect(
            EmulatorHost.hostFor(
              isAndroid: android,
              isPhysicalDevice: physical,
            ),
            isNotEmpty,
          );
        }
      }
    });
  });

  group('the physical-device warning', () {
    test('a handset with no override is warned, naming every way out', () {
      // It falls back rather than refusing because the fallback works: under
      // `adb reverse` loopback reaches the suite. That is only true with the
      // plugins' automaticHostMapping disabled — left on, they rewrite
      // localhost to 10.0.2.2 on Android and the handset dials an address that
      // does not exist. main.dart turns it off; see EmulatorHost.warningFor.
      final warning = EmulatorHost.warningFor(
        isPhysicalDevice: true,
        host: EmulatorHost.loopback,
      );
      expect(warning, isNotNull);
      // A warning that does not say what to do instead is just noise.
      expect(warning, contains('adb reverse'));
      expect(warning, contains('EMULATOR_HOST'));
      expect(warning, contains('USE_EMULATOR=false'));
    });

    test('an emulator is not warned about', () {
      expect(
        EmulatorHost.warningFor(
          isPhysicalDevice: false,
          host: EmulatorHost.androidEmulator,
        ),
        isNull,
      );
    });
  });

  group('the defaults a plain `flutter run` gets', () {
    test('the emulator is used unless explicitly switched off', () {
      // Defaulting the other way would mean a forgotten flag reaches real
      // Firebase, which is the failure worth preventing.
      expect(EmulatorHost.useEmulator, isTrue);
    });

    test('with no --dart-define the host is inferred, not overridden', () {
      expect(EmulatorHost.override, isEmpty);
      expect(EmulatorHost.isExplicit, isFalse);
    });

    test('the two platform hosts are distinct and correct', () {
      expect(EmulatorHost.loopback, 'localhost');
      expect(EmulatorHost.androidEmulator, '10.0.2.2');
      expect(EmulatorHost.loopback, isNot(EmulatorHost.androidEmulator));
    });

    test('no LAN IP is baked into the source', () {
      // A hardcoded address is one developer's DHCP lease rotting in the repo.
      // A real device passes --dart-define=EMULATOR_HOST=<ip> instead.
      expect(EmulatorHost.override, isEmpty);
      for (final host in [
        EmulatorHost.loopback,
        EmulatorHost.androidEmulator,
      ]) {
        expect(
          RegExp(
            r'^192\.168\.|^10\.(?!0\.2\.2$)|^172\.(1[6-9]|2\d|3[01])\.',
          ).hasMatch(host),
          isFalse,
          reason: '$host looks like a baked-in LAN address',
        );
      }
    });
  });
}
