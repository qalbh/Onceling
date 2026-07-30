import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/auth/screens/sign_in_screen.dart';
import 'features/feed/screens/feed_screen.dart';
import 'features/pairing/screens/pairing_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'theme/app_theme.dart';

void main() {
  // Both families are bundled in assets/fonts/; never reach out to Google.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const OncelingApp());
}

class OncelingApp extends StatelessWidget {
  const OncelingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onceling',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      initialRoute: SignInScreen.routeName,
      routes: {
        SignInScreen.routeName: (_) => const SignInScreen(),
        PairingScreen.routeName: (_) => const PairingScreen(),
        FeedScreen.routeName: (_) => const FeedScreen(),
        SettingsScreen.routeName: (_) => const SettingsScreen(),
      },
    );
  }
}
