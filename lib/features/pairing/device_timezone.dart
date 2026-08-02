import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Reads the device's IANA timezone name, e.g. `Asia/Karachi` (**P2-40**).
///
/// A package rather than `DateTime.now().timeZoneName`, which returns an
/// abbreviation like `PKT` or an offset like `GMT+5` depending on platform.
/// Neither is an IANA name, and **Q3 rules out offsets outright** — they are
/// wrong for half the year anywhere that observes DST, which is exactly the
/// failure a streak boundary must not have.
///
/// Behind a provider so tests can supply a fixed zone without a platform
/// channel, and so the pairing flow has one place to fake.
typedef TimezoneReader = Future<String?> Function();

final deviceTimezoneProvider = Provider<TimezoneReader>(
  (ref) => readDeviceTimezone,
);

/// Never throws. A device that cannot name its own zone must not be able to
/// fail a pairing — the server treats null as "unknown" and falls back, and
/// **P2-39** will let the couple set it properly later.
Future<String?> readDeviceTimezone() async {
  try {
    // `.identifier` is the IANA name; the object also carries a localised
    // display name, which is the wrong thing to store — it is not stable and
    // not a zone.
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } catch (error) {
    developer.log(
      'could not read the device timezone: $error',
      name: 'DeviceTimezone',
    );
    return null;
  }
}
