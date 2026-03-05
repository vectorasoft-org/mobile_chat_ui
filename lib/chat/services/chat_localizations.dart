import 'package:flutter/material.dart';

import 'localization_provider.dart';

/// ChatLocalizations provides a clean, typed interface for accessing chat-related
/// localized strings. This abstraction layer decouples the chat module from the
/// app's localization implementation--allowing future changes to the localization
/// system without modifying chat_page.dart.
///
/// Must be initialized with a ChatLocalizationProvider before use:
///   ChatLocalizations.setProvider(myProvider);
///
/// Usage in chat_page.dart:
///   String title = ChatLocalizations.chatThemeDialogTitle(context);
///   String message = ChatLocalizations.clearCacheDialogContent(context);
class ChatLocalizations {
  static ChatLocalizationProvider? _provider;

  /// Initialize the localization provider.
  static void setProvider(ChatLocalizationProvider provider) {
    _provider = provider;
  }

  static ChatLocalizationProvider get _getProvider {
    if (_provider == null) {
      throw StateError(
        'ChatLocalizations provider not set. Call ChatLocalizations.setProvider() first.',
      );
    }
    return _provider!;
  }

  static String _getString(String key, BuildContext context) =>
      _getProvider.getString(key, context);
  // Chat Theme Dialog
  static String chatThemeDialogTitle(BuildContext context) =>
      _getString('chatThemeDialogTitle', context);

  static String chatThemeRed(BuildContext context) =>
      _getString('chatThemeRed', context);

  static String chatThemeBlue(BuildContext context) =>
      _getString('chatThemeBlue', context);

  static String chatThemeGreen(BuildContext context) =>
      _getString('chatThemeGreen', context);

  // Dialog & Button Actions
  static String cancelButton(BuildContext context) =>
      _getString('cancelButton', context);

  static String applyButton(BuildContext context) =>
      _getString('applyButton', context);

  static String clearButton(BuildContext context) =>
      _getString('clearButton', context);

  // Clear Cache Dialog
  static String clearCacheMenuTitle(BuildContext context) =>
      _getString('clearCacheMenuTitle', context);

  static String clearCacheDialogTitle(BuildContext context) =>
      _getString('clearCacheDialogTitle', context);

  static String clearCacheDialogContent(BuildContext context) =>
      _getString('clearCacheDialogContent', context);

  // Clear Cache Feedback
  static String cacheCleared(BuildContext context) =>
      _getString('cacheCleared', context);

  static String cacheClaredMessage(BuildContext context) =>
      _getString('cacheClaredMessage', context);

  static String clearCacheError(BuildContext context) =>
      _getString('clearCacheError', context);

  static String clearCacheErrorPrefix(BuildContext context) =>
      _getString('clearCacheErrorPrefix', context);

  // Microphone Permission Errors
  static String micPermissionRequired(BuildContext context) =>
      _getString('micPermissionRequired', context);

  static String micPermissionRequiredMessage(BuildContext context) =>
      _getString('micPermissionRequiredMessage', context);

  static String micPermissionDenied(BuildContext context) =>
      _getString('micPermissionDenied', context);

  static String micPermissionDeniedMessage(BuildContext context) =>
      _getString('micPermissionDeniedMessage', context);

  static String micPermissionRestricted(BuildContext context) =>
      _getString('micPermissionRestricted', context);

  static String micPermissionRestrictedMessage(BuildContext context) =>
      _getString('micPermissionRestrictedMessage', context);

  static String micPermissionError(BuildContext context) =>
      _getString('micPermissionError', context);

  static String micPermissionErrorMessage(BuildContext context) =>
      _getString('micPermissionErrorMessage', context);

  static String settingsButton(BuildContext context) =>
      _getString('settingsButton', context);

  // Menu Items
  static String changeThemeMenuItem(BuildContext context) =>
      _getString('changeThemeMenuItem', context);

  // Chat Input
  static String inputHint(BuildContext context) =>
      _getString('inputHint', context);

  static String slideToCancel(BuildContext context) =>
      _getString('slideToCancel', context);

  static String releaseToCancel(BuildContext context) =>
      _getString('releaseToCancel', context);

  // Generic Error
  static String errorLabel(BuildContext context) =>
      _getString('errorLabel', context);

  // Channel Info Page
  static String channelInfoTitle(BuildContext context) =>
      _getString('channelInfoTitle', context);

  static String channelName(BuildContext context) =>
      _getString('channelName', context);

  static String channelId(BuildContext context) =>
      _getString('channelId', context);

  static String userInfoTitle(BuildContext context) =>
      _getString('userInfoTitle', context);

  static String userId(BuildContext context) => _getString('userId', context);

  static String userName(BuildContext context) =>
      _getString('userName', context);

  static String actionsTitle(BuildContext context) =>
      _getString('actionsTitle', context);
}
