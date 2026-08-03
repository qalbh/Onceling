import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Where the Local Emulator Suite lives, as seen from *this* device
/// (**P2-21**).
///
/// Three different answers, and getting it wrong looks the same in all three
/// cases — the app hangs, then fails, with nothing pointing at the host:
///
/// - **iOS simulator and desktop** share the host's loopback, so `localhost`
///   is correct and always has been.
/// - **Android emulator** runs behind its own NAT. `10.0.2.2` is the magic
///   alias the emulator maps back to the host's loopback; `localhost` there
///   means the emulator itself, where nothing is listening.
/// - **A real device** is on the LAN and has no route to either. It needs the
///   host machine's LAN IP.
///
/// The LAN IP is deliberately **not discovered and not hardcoded**. Hardcoding
/// bakes one developer's DHCP lease into the repo, where it rots silently and
/// breaks for everyone else. Discovery would mean scanning or mDNS, which is a
/// lot of moving parts to save one flag. So a real device passes it in:
///
///     flutter run -d <device> --dart-define=EMULATOR_HOST=192.168.1.42
///
/// Passing it also works for the simulators, which is occasionally useful when
/// running the suite on one machine and the app on another.
abstract final class EmulatorHost {
  /// Overrides the platform default. Empty when not supplied.
  ///
  /// A `--dart-define` compiles into the binary and leaves no trace in the
  /// repo — see docs/local-run.md on why that matters when checking what a
  /// device is actually running.
  static const override = String.fromEnvironment('EMULATOR_HOST');

  /// The host to point the SDKs at, for whatever this build is running on.
  static String get resolved {
    if (override.isNotEmpty) return override;

    // `Platform` is unavailable on web; this app has no web target (brief §7),
    // but the guard keeps the getter honest if that ever changes.
    if (!kIsWeb && Platform.isAndroid) return androidEmulator;
    return loopback;
  }

  static const loopback = 'localhost';

  /// The Android emulator's alias for the host's loopback interface.
  ///
  /// **Only correct for the emulator.** A real Android phone reaches this and
  /// finds nothing, which is why [override] exists.
  static const androidEmulator = '10.0.2.2';

  /// True when this build is talking to a host it had to be told about.
  static bool get isExplicit => override.isNotEmpty;
}
