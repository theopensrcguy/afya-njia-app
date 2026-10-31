import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/brand.dart';
import 'core/session.dart';
import 'features/auth/pin_screen.dart';
import 'features/home/home_screen.dart';

/// Lets non-widget code (like the session listener below) control navigation.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
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
      // The "gate": ListenableBuilder rebuilds whenever Session calls
      // notifyListeners(), so logging in or out swaps the whole screen.
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.restored) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return session.isLoggedIn ? HomeScreen(session: session) : PinScreen(session: session);
        },
      ),
    );
  }
}
