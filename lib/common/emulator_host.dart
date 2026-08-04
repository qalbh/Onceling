import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Which backend a debug build talks to, and where it lives (**P2-21**).
///
/// Two independent questions, and they used to be conflated:
///
///   1. **Emulator or the real dev project?** Almost always the emulator — but
///      anything with no emulator behind it has to be tested against dev. Push
///      (**P3-04**) is the standing example: there is no FCM emulator, so a
///      notification can only be observed by a debug build talking to real
///      Firebase. `--dart-define=USE_EMULATOR=false` is that switch.
///   2. **If the emulator, at what host?** Different on every target, and
///      wrong looks identical everywhere — the app hangs, then fails, with
///      nothing naming the host:
///      - **iOS simulator and desktop** share the host's loopback: `localhost`.
///      - **The Android emulator** runs behind its own NAT. `10.0.2.2` is the
///        alias it maps back to the host loopback; `localhost` there means the
///        emulator itself, where nothing is listening.
///      - **A physical device** is on the LAN and has no route to either.
///
/// The LAN IP is deliberately **not discovered and not hardcoded**. Hardcoding
/// bakes one developer's DHCP lease into the repo, where it rots silently and
/// breaks for everyone else. Discovery would mean scanning or mDNS, which is a
/// lot of moving parts to save one flag. So a real device passes it in:
///
///     flutter run -d <device> --dart-define=EMULATOR_HOST=192.168.1.42
///
/// ## Why `isPhysicalDevice` and not a guess
///
/// This branched on `Platform.isAndroid` alone, which answers the wrong
/// question: it distinguishes iOS from Android, not an emulator from a handset.
/// A real Samsung with no flag resolved `10.0.2.2` — an address that means
/// nothing off the emulator — and the failure surfaced as a network error,
/// reading as the app's fault rather than a misconfiguration.
///
/// There is no zero-dependency way to tell. The signal that actually separates
/// them is the `ro.kernel.qemu` system property (`1` on the AVD, `0` on the
/// SM-A325F); the `/dev/goldfish_pipe`-style markers are not visible, and
/// system properties need a platform channel. Hence `device_info_plus`, which
/// asks the platform instead of sniffing for artefacts.
abstract final class EmulatorHost {
  /// Overrides the host. Empty when not supplied.
  ///
  /// A `--dart-define` compiles into the binary and leaves no trace in the
  /// repo — see docs/local-run.md on why that matters when checking what a
  /// device is actually running.
  static const override = String.fromEnvironment('EMULATOR_HOST');

  /// Whether to use the Local Emulator Suite at all.
  ///
  /// Defaults true: the emulator is the development environment, and a build
  /// that silently reached production data would be the worse default by far.
  /// `--dart-define=USE_EMULATOR=false` opts out.
  static const useEmulator = bool.fromEnvironment(
    'USE_EMULATOR',
    defaultValue: true,
  );

  static const loopback = 'localhost';

  /// The Android emulator's alias for the host's loopback interface.
  ///
  /// **Only ever correct on the emulator.** A physical phone reaches this and
  /// finds nothing.
  static const androidEmulator = '10.0.2.2';

  /// True when this build was told its host rather than inferring one.
  static bool get isExplicit => override.isNotEmpty;

  /// The host decision, as a pure function of the two facts it depends on.
  ///
  /// Split out from [resolve] so it is testable: `flutter test` runs on the
  /// host VM, where `Platform.isAndroid` is false and no device exists, so the
  /// real resolver can never exercise the Android branch.
  ///
  /// **A physical device never resolves to [androidEmulator].** It falls back
  /// to [loopback], which is correct under `adb reverse` — provided the
  /// plugins' host rewriting is off, which is the whole subject of the note on
  /// [warningFor].
  static String hostFor({
    required bool isAndroid,
    required bool isPhysicalDevice,
  }) {
    if (override.isNotEmpty) return override;
    if (isAndroid && !isPhysicalDevice) return androidEmulator;
    return loopback;
  }

  /// The loud part of the fallback, or null when there is nothing to say.
  ///
  /// A physical device with no `EMULATOR_HOST` is running on an assumption —
  /// that `adb reverse` is up. When that assumption is wrong the connection
  /// fails, and without this line the only evidence is a network error.
  ///
  /// ## `adb reverse` works, and the reason it looked broken
  ///
  /// This was briefly a hard refusal, on the measured grounds that loopback
  /// never reached the suite from a handset. The measurement was real and the
  /// conclusion drawn from it was wrong. **The plugins rewrite the host.** Each
  /// of `useAuthEmulator` / `useFirestoreEmulator` / `useFunctionsEmulator`
  /// defaults `automaticHostMapping: true`, which on Android silently turns
  /// `localhost` and `127.0.0.1` into `10.0.2.2` — a convenience for the AVD,
  /// and on a handset a rewrite to an address that does not exist. The device
  /// log said it outright once the error surfaced the address it actually
  /// dialled: told `localhost`, it reported
  /// `Failed to connect to /10.0.2.2:9099`.
  ///
  /// So loopback was never tested; the traffic never went there. `main.dart`
  /// now passes `automaticHostMapping: false` on all three, and `adb reverse`
  /// is a working route. The earlier "native SDKs cannot use the tunnel" story
  /// was invented to explain a result that had a much duller cause.
  static String? warningFor({
    required bool isPhysicalDevice,
    required String host,
  }) {
    if (!isPhysicalDevice || override.isNotEmpty) return null;
    return 'physical device with no EMULATOR_HOST — falling back to $host. '
        'This works ONLY under `adb reverse tcp:8080 tcp:8080` (and 9099, '
        '5001). Otherwise pass --dart-define=EMULATOR_HOST=<host LAN IP>, or '
        '--dart-define=USE_EMULATOR=false to use the dev project.';
  }

  /// Asks the platform whether this is real hardware.
  ///
  /// Anything that is not Android or iOS is treated as not-a-handset: desktop
  /// and web share the host's loopback, which is the same answer.
  static Future<bool> isPhysicalDevice() async {
    if (kIsWeb) return false;
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await info.androidInfo).isPhysicalDevice;
    if (Platform.isIOS) return (await info.iosInfo).isPhysicalDevice;
    return false;
  }

  /// The host to point the SDKs at, for whatever this build is running on.
  static Future<String> resolve() async => hostFor(
    isAndroid: !kIsWeb && Platform.isAndroid,
    isPhysicalDevice: await isPhysicalDevice(),
  );
}
