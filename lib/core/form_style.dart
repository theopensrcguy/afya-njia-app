import 'package:flutter/material.dart';

import 'phone_field.dart';

/// The form look agreed with Sajili mteja (v0.47): a small label above, a
/// white box with a soft edge, the country code joined to the number. Shared
/// so every form in the app reads the same (v0.48.3).
const _muted = Color(0xFF5B6F69);
const _edge = Color(0xFFC9D6D1);
const _deep = Color(0xFF0E3B31);

Widget formLabel(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 0, 6),
      child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted)),
    );

/// [onCard]: the box sits on a white card, so it's a soft grey instead.
InputDecoration formBox(String? hint, {String? counter, bool onCard = false}) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: onCard ? const Color(0xFFF6F9F8) : Colors.white,
      isDense: true,
      counterText: counter,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: onCard ? const Color(0xFFE3EBE7) : _edge)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _deep, width: 1.6)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );

Widget formPhone(TextEditingController controller, {String hint = '712 345 678', bool onCard = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
          color: onCard ? const Color(0xFFF6F9F8) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: onCard ? const Color(0xFFE3EBE7) : _edge)),
      child: PhoneField(controller: controller, bare: true, hint: hint),
    );

/// A white card holding a group of fields, with a title and an icon.
Widget formSection({required IconData icon, required String title, String? note, required List<Widget> children}) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFE3F4EA), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: const Color(0xFF0E5A44)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        ]),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(note, style: const TextStyle(fontSize: 12, color: _muted))),
        ...children,
      ]),
    );
