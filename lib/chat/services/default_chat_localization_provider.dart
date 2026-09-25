import 'package:flutter/widgets.dart';
import 'package:vs_chat_flutter/chat/services/chat_strings.dart';
import 'package:vs_chat_flutter/chat/services/localization_provider.dart';

/// The package's built-in texts ([chatStrings]) in the host's current
/// language, with the host's [overrides] on top.
class DefaultChatLocalizationProvider implements ChatLocalizationProvider {
  DefaultChatLocalizationProvider({this.language, this.overrides = const {}});

  /// The current language code ('en', 'km'); read on every lookup.
  final String Function()? language;

  /// Per-language replacements: `{'km': {'title': '...'}}`.
  final Map<String, Map<String, String>> overrides;

  @override
  String getString(String key, BuildContext context) => lookup(key);

  /// [key] in the current language, else [fallback], else English, else
  /// the key itself.
  String lookup(String key, [String? fallback]) {
    final lang = language?.call() ?? 'en';
    return overrides[lang]?[key] ??
        chatStrings[lang]?[key] ??
        fallback ??
        chatStrings['en']![key] ??
        key;
  }
}
