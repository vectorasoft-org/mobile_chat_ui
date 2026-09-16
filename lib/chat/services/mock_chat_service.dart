import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../config/chat_service_listener.dart';
import '../config/chat_theme.dart';
import '../models.dart';
import 'chat_service.dart';

class MockChatService extends ChatService {
  final List<ChatServiceListener> _listeners = [];
  final List<Message> _messages = [];

  ChatTheme _theme = ChatTheme.houExpress();
  String _channelName = 'Channel';
  String _userName = 'Unknown';
  String _userCode = 'Unknown ID';
  String? _userAvatarUrl;

  @override
  dynamic get client => null;

  void _notifyMessages() {
    final snapshot = List<Message>.from(_messages);
    for (final listener in _listeners) {
      listener.onMessagesChanged(snapshot);
    }
  }

  void _notifyTheme() {
    for (final listener in _listeners) {
      listener.onThemeChanged(_theme);
    }
  }

  void _notifyUserData() {
    for (final listener in _listeners) {
      listener.onChannelNameChanged(_channelName);
      listener.onUserDataChanged(
        userName: _userName,
        userCode: _userCode,
        userAvatarUrl: _userAvatarUrl,
      );
    }
  }

  @override
  void addListener(ChatServiceListener listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(ChatServiceListener listener) {
    _listeners.remove(listener);
  }

  @override
  List<Message> getMessagesCache() => List<Message>.from(_messages);

  @override
  ChatTheme getSelectedTheme() => _theme;

  @override
  String getCachedChannelName() => _channelName;

  @override
  String? getChannelId() => null;

  @override
  String getCachedUserName() => _userName;

  @override
  String getCachedUserCode() => _userCode;

  @override
  String? getCachedUserAvatarUrl() => _userAvatarUrl;

  @override
  void setSelectedTheme(ChatTheme theme) {
    _theme = theme;
    _notifyTheme();
  }

  @override
  void setChannelName(String name) {
    _channelName = name;
    _notifyUserData();
  }

  @override
  void setUserName(String name) {
    _userName = name;
    _notifyUserData();
  }

  @override
  void setUserCode(String code) {
    _userCode = code;
    _notifyUserData();
  }

  @override
  void setUserAvatarUrl(String? url) {
    _userAvatarUrl = url;
    _notifyUserData();
  }

  @override
  Future<List<Message>> getMessages({
    required String channelId,
    int limit = 20,
    GetMessageOpt? getMessageOpt,
    String? optMessageId,
  }) async {
    final start = _messages.length > limit ? _messages.length - limit : 0;
    final page = _messages.sublist(start);
    return List<Message>.from(page);
  }

  @override
  Future<void> sendMessage({
    required String channelId,
    required String messageText,
  }) async {
    _messages.add(
      Message(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sender: _userName,
        text: messageText,
      ),
    );
    _notifyMessages();
  }

  @override
  Future<void> sendAttachment({
    required String channelId,
    required Map<String, dynamic> attachment,
  }) async {
    _messages.add(
      Message(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sender: _userName,
        attachments: [attachment],
      ),
    );
    _notifyMessages();
  }

  @override
  Future<void> sendImage({
    required String channelId,
    required XFile imageFile,
    required int imageWidth,
    required int imageHeight,
    String? messageText,
  }) async {
    await sendAttachment(
      channelId: channelId,
      attachment: {
        'type': 'image',
        'image_url': imageFile.path,
        'title': imageFile.name,
      },
    );
  }

  @override
  Future<void> sendVideo({
    required String channelId,
    required XFile videoFile,
    String? messageText,
  }) async {
    await sendAttachment(
      channelId: channelId,
      attachment: {
        'type': 'video',
        'asset_url': videoFile.path,
        'title': videoFile.name,
      },
    );
  }

  @override
  Future<void> sendMedia({
    required String channelId,
    required List<MediaAttachment> media,
    String? messageText,
  }) async {
    final attachments = media.map((item) {
      if (item.isVideo) {
        return <String, dynamic>{
          'type': 'video',
          'asset_url': item.file.path,
          'title': item.file.name,
        };
      }
      return <String, dynamic>{
        'type': 'image',
        'image_url': item.file.path,
        'title': item.file.name,
      };
    }).toList();

    _messages.add(
      Message(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sender: _userName,
        text: messageText?.isNotEmpty == true ? messageText : null,
        attachments: attachments,
      ),
    );
    _notifyMessages();
  }

  @override
  Future<void> sendFile({
    required String channelId,
    required XFile file,
    String? messageText,
  }) async {
    await sendAttachment(
      channelId: channelId,
      attachment: {
        'type': 'file',
        'asset_url': file.path,
        'title': file.name,
      },
    );
  }

  @override
  Future<void> sendFiles({
    required String channelId,
    required List<XFile> files,
    String? messageText,
  }) async {
    final attachments = files
        .map(
          (file) => <String, dynamic>{
            'type': 'file',
            'asset_url': file.path,
            'title': file.name,
          },
        )
        .toList();

    _messages.add(
      Message(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sender: _userName,
        text: messageText?.isNotEmpty == true ? messageText : null,
        attachments: attachments,
      ),
    );
    _notifyMessages();
  }

  @override
  Future<void> sendVoiceRecording({
    required String channelId,
    required String filePath,
    required int durationMilliseconds,
  }) async {
    await sendAttachment(
      channelId: channelId,
      attachment: {
        'type': 'voiceRecording',
        'asset_url': filePath,
        'duration': durationMilliseconds ~/ 1000,
      },
    );
  }

  @override
  Future<void> sendLocation({
    required String channelId,
    required double latitude,
    required double longitude,
    String? messageText,
  }) async {
    await sendAttachment(
      channelId: channelId,
      attachment: {
        'type': 'location',
        'latitude': latitude,
        'longitude': longitude,
        'title': 'Location',
        'thumb_url': '',
      },
    );
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    _messages.removeWhere((m) => m.id == messageId);
    _notifyMessages();
  }

  @override
  Future<String?> downloadFile({
    required Message message,
    String? imageUrl,
    Uint8List? imageBytes,
    String fileExtension = 'jpg',
  }) async {
    return null;
  }

  @override
  Future<String?> getChannelName({required String channelId}) async {
    return 'Channel - $channelId';
  }
}
