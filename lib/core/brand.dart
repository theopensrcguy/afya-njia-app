import 'package:flutter/material.dart';

/// Brand colours in one place so every screen matches.
/// v0.2: the soft mint look chosen from the design canvas ("B2 · Mint Laini").

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
const dangerRed = Color(0xFFB42318);
const warnAmber = Color(0xFF8A5300);
const pageBackground = Color(0xFFE9F2EE);

/// Payment colours, the same on every screen (home, reports).
const paymentColors = {'cash': mintAccent, 'mobile': Color(0xFF7A5BC7), 'insurance': Color(0xFFE0A93B)};

/// The soft card used across the new screens.
BoxDecoration softCard({double radius = 26}) => BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [BoxShadow(color: Color(0x141E503C), blurRadius: 24, offset: Offset(0, 8))],
    );
