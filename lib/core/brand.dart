import 'package:flutter/material.dart';

/// Brand colours in one place so every screen matches.
/// v0.2: the soft mint look chosen from the design canvas ("B2 · Mint Laini").
/// v0.12: the same named colours as the web (public/css/afya.css in the
/// backend), so a colour means the same thing on the phone and the laptop.

/// Buttons and active icons. Dark enough that white text on it is easy to read.
const brandGreen = Color(0xFF1B7F64);

/// The brighter mint for drawings only (ring, chart bars), never under text.
const mintAccent = Color(0xFF2BA884);

/// Light mint behind progress rings, inactive bars and soft buttons.
const mintSoft = Color(0xFFE2EFE9);

/// Cards sit on the page background slightly lighter, with a soft shadow.
const cardColor = Color(0xFFF6FAF8);

const inkColor = Color(0xFF1B2B26);
const mutedText = Color(0xFF4F6963);
const dangerRed = Color(0xFFC2412D);
const warnAmber = Color(0xFF8A5300);
const pageBackground = Color(0xFFE9F2EE);

/// Green TEXT on a mint background. brandGreen on mintSoft is only 4.2:1
/// (too faint for small text); this one is 5.5:1.
const primaryStrong = Color(0xFF156B55);

/// Behind the active menu item and selected chips.
const primarySoft = Color(0xFFDDF3EA);

/// "Waiting for you" (deliveries to confirm, devices to approve). Blue, so it
/// never gets mixed up with green "good" or amber "watch out".
const infoBlue = Color(0xFF2563EB);
const infoSoft = Color(0xFFE8F0FD);

/// Soft backgrounds for warning and danger chips (the text stays warnAmber / dangerRed).
const warnSoft = Color(0xFFFDF1DC);
const dangerSoft = Color(0xFFFBE9E5);

/// Mobile money.
const momoPurple = Color(0xFF5B3FC4);

/// Chart bars: ordinary day, best day (today uses brandGreen).
const barNormal = Color(0xFF4E9A7E);
const barBest = Color(0xFF145F4B);

/// Several series in one chart, always in this order.
const chartPalette = [brandGreen, infoBlue, momoPurple, Color(0xFFC77700), mutedText];

/// Payment colours, the same on every screen (home, reports).
const paymentColors = {'cash': mintAccent, 'mobile': momoPurple, 'insurance': Color(0xFFE0A93B)};

/// The soft card used across the new screens.
BoxDecoration softCard({double radius = 26}) => BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [BoxShadow(color: Color(0x141E503C), blurRadius: 24, offset: Offset(0, 8))],
    );
