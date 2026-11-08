import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/brand.dart';
import 'core/i18n.dart';
import 'core/session.dart';
import 'features/auth/change_pin_screen.dart';
import 'features/auth/pin_screen.dart';
import 'features/home/home_screen.dart';

/// Lets non-widget code (like the session listener below) control navigation.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The language this phone showed last time, before the first screen draws.
  await lang.load();

  // One ApiClient and one Session for the whole app. They are created here,
  // once, and passed down to the screens that need them (no global variables).
  final session = Session(ApiClient());

  // If the user is signed out while deep inside the app (token expired),
  // close every open screen so the PIN screen underneath is visible.
  session.addListener(() {
    if (!session.isLoggedIn) {
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  });

  // Kiswahili ⇄ English: close every open screen and draw home again, so
  // every text on screen is redrawn in the new language.
  lang.addListener(() => navigatorKey.currentState?.popUntil((route) => route.isFirst));

  runApp(AfyaNjiaApp(session: session));
  session.restore();
}

class AfyaNjiaApp extends StatelessWidget {
  const AfyaNjiaApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Afya Njia',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      // Tap anywhere outside a text box to close the keyboard, on every screen.
      // (iPhone number keyboards have no "Done" key, so without this the only
      // way out was the back button.) Buttons still get their taps: the
      // innermost widget wins the tap, this only sees taps on empty space.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brandGreen, primary: brandGreen),
        scaffoldBackgroundColor: pageBackground,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      // The "gate": ListenableBuilder rebuilds whenever Session (or the
      // language) calls notifyListeners(), so logging in or out swaps the whole screen.
      home: ListenableBuilder(
        listenable: Listenable.merge([session, lang]),
        builder: (context, _) => KeyedSubtree(
          // A new key when the language changes: the screens below start
          // fresh, so every text is drawn again in the new language.
          key: ValueKey(lang.code),
          child: _gate(),
        ),
      ),
    );
  }

  /// Which screen: loading, sign-in, choose-your-own-PIN, or home.
  Widget _gate() {
    if (!session.restored) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.isLoggedIn) return PinScreen(session: session);
    // A PIN someone else set (new staff, owner reset) is only for getting
    // in once: choose your own before anything else. The server refuses
    // everything else too, so this can't be skipped.
    if (session.user!.mustChangePin) return ChangePinScreen(session: session, forced: true);
    return HomeScreen(session: session);
  }
}
