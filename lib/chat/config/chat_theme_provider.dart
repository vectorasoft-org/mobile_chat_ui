import 'package:flutter/material.dart';
import 'chat_theme.dart';

/// InheritedWidget that provides ChatTheme to all descendants
///
/// Widgets can access the theme via:
///   ChatTheme.of(context)
///
/// This follows the Flutter pattern used by Theme, MediaQuery, etc.
class ChatThemeProvider extends InheritedWidget {
  final ChatTheme theme;

  const ChatThemeProvider({
    super.key,
    required this.theme,
    required super.child,
  });

  /// Get the ChatTheme from the nearest ChatThemeProvider ancestor
  ///
  /// Throws if no ChatThemeProvider is found in the widget tree
  static ChatTheme of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<ChatThemeProvider>();
    if (provider == null) {
      throw FlutterError(
        'ChatTheme.of() called with a context that does not contain a ChatThemeProvider.\n'
        'Ensure that ChatThemeProvider is an ancestor of the widget that calls ChatTheme.of().',
      );
    }
    return provider.theme;
  }

  /// Get the ChatTheme from the nearest ChatThemeProvider ancestor, or null if not found
  static ChatTheme? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ChatThemeProvider>()
        ?.theme;
  }

  @override
  bool updateShouldNotify(ChatThemeProvider oldWidget) {
    return theme.primaryColor != oldWidget.theme.primaryColor ||
        theme.messageSentBackground != oldWidget.theme.messageSentBackground ||
        theme.messageReceivedBackground !=
            oldWidget.theme.messageReceivedBackground ||
        theme.inputBackground != oldWidget.theme.inputBackground ||
        theme.recordButtonBackground !=
            oldWidget.theme.recordButtonBackground ||
        theme.audioPlayerSentBackground !=
            oldWidget.theme.audioPlayerSentBackground ||
        theme.videoProgressBar != oldWidget.theme.videoProgressBar ||
        theme.errorColor != oldWidget.theme.errorColor;
  }
}
