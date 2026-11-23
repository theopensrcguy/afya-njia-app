import 'package:flutter/material.dart';

import 'core/appearance.dart';
import 'core/loader.dart';
import 'core/api_client.dart';
import 'core/brand.dart';
import 'core/i18n.dart';
import 'core/keyboard.dart';
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
  // Text size and font chosen on this phone (v0.50), before the first screen draws.
  await appearance.load();

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
    // Maandishi (v0.50): a new size or font redraws every screen as it is, with no restart.
    return ListenableBuilder(listenable: appearance, builder: (context, _) => _app());
  }

  Widget _app() {
    return MaterialApp(
      title: 'Afya Njia',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      // Tap anywhere outside a text box to close the keyboard, on every screen.
      // (iPhone number keyboards have no "Done" key, so without this the only
      // way out was the back button.) Buttons still get their taps: the
      // innermost widget wins the tap, this only sees taps on empty space.
      // (v0.46.1: a raw-finger listener, so buttons and rows under the finger
      // no longer swallow the tap; see core/keyboard.dart.)
      builder: (context, child) => MediaQuery(
        // The app's own text size, not the phone's (unless "Fuata simu" is chosen).
        data: MediaQuery.of(context).copyWith(textScaler: appearance.scaler(MediaQuery.of(context).textScaler)),
        child: KeyboardDismisser(
          // The loading bar and the Afya Njia loader, over every screen.
          child: ActivityLayer(child: child ?? const SizedBox()),
        ),
      ),
      // Coming back to a screen never reopens its keyboard.
      navigatorObservers: [keyboardObserver],
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: appearance.fontFamily,
        colorScheme: ColorScheme.fromSeed(seedColor: brandGreen, primary: brandGreen),
        scaffoldBackgroundColor: pageBackground,
        // Every dialog: a readable title, not the 24pt headline that a long
        // product name turned into a wall of text (v0.46.1).
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF16231F), height: 1.25),
        ),
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
      return const Scaffold(body: Center(child: AfyaLoader()));
    }
    if (!session.isLoggedIn) return PinScreen(session: session);
    // A PIN someone else set (new staff, owner reset) is only for getting
    // in once: choose your own before anything else. The server refuses
    // everything else too, so this can't be skipped.
    if (session.user!.mustChangePin) return ChangePinScreen(session: session, forced: true);
    return HomeScreen(session: session);
  }
}
