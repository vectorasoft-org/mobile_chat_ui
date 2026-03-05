import 'package:flutter/material.dart';

/// Abstract interface for localizations. The vs_chat_flutter package uses this
/// to decouple from any specific app-layer localization implementation.
abstract class ChatLocalizationProvider {
  /// Get a localized string for the given key.
  String getString(String key, BuildContext context);
}
