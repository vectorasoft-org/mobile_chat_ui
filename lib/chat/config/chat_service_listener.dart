import '../models.dart';
import 'chat_theme.dart';

/// Listener interface for ChatService state changes
/// ChatService implementations notify listeners of state updates via callbacks
/// This keeps the core chat module free from dependency on GetX or other state management
abstract class ChatServiceListener {
  /// Called when messages list changes
  void onMessagesChanged(List<Message> messages);

  /// Called when user data (name, code, avatar) changes
  void onUserDataChanged({
    required String userName,
    required String userCode,
    required String? userAvatarUrl,
  });

  /// Called when channel name changes
  void onChannelNameChanged(String channelName);

  /// Called when theme changes
  void onThemeChanged(ChatTheme theme);

  /// Called when an error occurs
  void onError(String message, {Object? error, StackTrace? stackTrace});
}

/// No-op implementation useful for testing or when changes don't need to be observed
class NoOpChatServiceListener implements ChatServiceListener {
  const NoOpChatServiceListener();

  @override
  void onMessagesChanged(List<Message> messages) {}

  @override
  void onUserDataChanged({
    required String userName,
    required String userCode,
    required String? userAvatarUrl,
  }) {}

  @override
  void onChannelNameChanged(String channelName) {}

  @override
  void onThemeChanged(ChatTheme theme) {}

  @override
  void onError(String message, {Object? error, StackTrace? stackTrace}) {}
}
