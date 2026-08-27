import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../config/chat_theme.dart';
import '../config/chat_service_listener.dart';

enum GetMessageOpt {
  lt,
  lte,
}

@immutable
class MessageFilter {
  final String refMessageOpt;
  final String refMessageId;

  const MessageFilter({
    required this.refMessageOpt,
    required this.refMessageId,
  });
}

abstract class ChatService {
  dynamic get client;

  FutureOr<void> initialize() {}
  FutureOr<void> dispose() {}

  /// Register a listener to receive state change notifications
  void addListener(ChatServiceListener listener);

  /// Unregister a listener
  void removeListener(ChatServiceListener listener);

  /// Get current cached messages
  List<Message> getMessagesCache();

  /// Get currently selected theme
  ChatTheme getSelectedTheme();

  /// Get cached channel name
  String getCachedChannelName();

  /// Get cached user name
  String getCachedUserName();

  /// Get cached user code/ID
  String getCachedUserCode();

  /// Get cached user avatar URL
  String? getCachedUserAvatarUrl();

  /// Set currently selected theme
  void setSelectedTheme(ChatTheme theme);

  /// Set cached channel name
  void setChannelName(String name);

  /// Set cached user name
  void setUserName(String name);

  /// Set cached user code/ID
  void setUserCode(String code);

  /// Set cached user avatar URL
  void setUserAvatarUrl(String? url);

  Future<List<Message>> getMessages({
    required String channelId,
    int limit = 20,
    GetMessageOpt? getMessageOpt,
    String? optMessageId,
  });

  Future<void> sendMessage({
    required String channelId,
    required String messageText,
  });

  Future<void> sendAttachment({
    required String channelId,
    required Map<String, dynamic> attachment,
  });

  Future<void> sendImage({
    required String channelId,
    required XFile imageFile,
    required int imageWidth,
    required int imageHeight,
    String? messageText,
  });

  Future<void> sendFile({
    required String channelId,
    required XFile file,
    String? messageText,
  });

  Future<void> sendVoiceRecording({
    required String channelId,
    required String filePath,
    required int durationMilliseconds,
  });

  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  });

  Future<String?> downloadFile({
    required Message message,
    String? imageUrl,
    Uint8List? imageBytes,
    String fileExtension = 'jpg',
  });

  Future<String?> getChannelName({
    required String channelId,
  });
}
