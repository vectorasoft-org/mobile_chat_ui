import 'package:flutter/material.dart';

/// How a room says who is speaking: a role chip next to the sender's name,
/// and the colour that name and their avatar take.
///
/// A role is whatever the host's member roster says (`role`, else
/// `user_class`). A room whose roster carries no roles - friends chatting -
/// shows no chip and gives each person a colour of their own, with nothing
/// to configure. The chip's text is the roster's value made readable, or the
/// host's own text for it: a `role_<key>` entry in `strings`.
class ChatSenderRoles {
  const ChatSenderRoles({this.show = true, this.colors = const {}});

  /// Never show a role chip, whatever the roster says.
  const ChatSenderRoles.hidden() : show = false, colors = const {};

  /// Show the chip when the roster names a role for the sender.
  final bool show;

  /// A colour per role, keyed by the roster's value in lower case
  /// (`{'driver': Color(0xFFB45309)}`). A role not listed keeps one steady
  /// colour of its own.
  final Map<String, Color> colors;

  /// The web widget's hues (vschat.js HUES), so a sender reads the same on
  /// both. Brand red is left out: it means "you" and errors.
  static const List<Color> _hues = [
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFB45309),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF0E7490),
    Color(0xFF4D7C0F),
    Color(0xFF475569),
  ];

  /// The roster's role as a lookup key, or '' when there is none to show.
  String keyOf(String? role) => show ? (role ?? '').trim().toLowerCase() : '';

  /// One colour per role when the sender has one, else one per person.
  Color colorOf(String senderId, String? role) {
    final key = keyOf(role);
    return key.isEmpty ? _steady(senderId) : (colors[key] ?? _steady(key));
  }

  /// "operation_officer" -> "Operation officer".
  static String readable(String role) {
    final s = role.replaceAll('_', ' ').trim();
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  static Color _steady(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _hues[h % _hues.length];
  }
}
