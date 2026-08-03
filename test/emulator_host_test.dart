import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/common/emulator_host.dart';

/// **P2-21** — the emulator host is different on every platform, and getting it
/// wrong fails identically in all three cases: the app hangs, then errors, with
/// nothing naming the host.
///
/// `Platform.isAndroid` is false under `flutter test` (it runs on the host VM),
/// so these pin the parts that are testable without a device: the constants
/// themselves, and the override that a real phone depends on.
void main() {
  test('the two platform hosts are distinct and correct', () {
    // 10.0.2.2 is the Android emulator's alias for the host loopback. If these
    // ever collapse to the same value, the Android branch has been lost.
    expect(EmulatorHost.loopback, 'localhost');
    expect(EmulatorHost.androidEmulator, '10.0.2.2');
    expect(EmulatorHost.loopback, isNot(EmulatorHost.androidEmulator));
  });

  test('with no --dart-define, the host is resolved not overridden', () {
    // The default test run supplies nothing, which is the simulator case.
    expect(EmulatorHost.override, isEmpty);
    expect(EmulatorHost.isExplicit, isFalse);
    expect(EmulatorHost.resolved, EmulatorHost.loopback);
  });

  test('no LAN IP is baked into the source', () {
    // A hardcoded address is one developer's DHCP lease rotting in the repo.
    // A real device passes --dart-define=EMULATOR_HOST=<ip> instead.
    expect(EmulatorHost.override, isEmpty);
    for (final host in [EmulatorHost.loopback, EmulatorHost.androidEmulator]) {
      expect(
        RegExp(
          r'^192\.168\.|^10\.(?!0\.2\.2$)|^172\.(1[6-9]|2\d|3[01])\.',
        ).hasMatch(host),
        isFalse,
        reason: '$host looks like a baked-in LAN address',
      );
    }
  });
}
