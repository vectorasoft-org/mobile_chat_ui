import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust/rust.dart';
// import 'package:rust/rust.dart';
import 'package:vs_chat_flutter/chat/services/socket_io_client.dart';
import 'package:vs_chat_flutter/core/ext/iterable.dart';
import '../config/chat_config.dart';
import '../config/chat_theme.dart';
import '../config/chat_service_listener.dart';
import '../models.dart';
import 'chat_service.dart';
import 'http_client.dart';

class RealChatService extends ChatService {
  final ChatConfig config;
  late final StreamChatHttpClient _httpClient;
  late final StreamChatSocketIoClient _socketClient;

  // Core state - plain Dart types
  final List<Message> _messagesCache = [];
  late ChatTheme _selectedTheme;
  late String _channelName;
  String? _channelId;
  late String _userName;
  late String _userCode;
  late String? _userAvatarUrl;

  // Listener management
  final List<ChatServiceListener> _listeners = [];

  RealChatService({required this.config}) {
    _httpClient = StreamChatHttpClient(config: config);
    _socketClient = StreamChatSocketIoClient(
      config: config,
      onNewMessage: _handleNewMessage,
      onDeletedMessages: _handleDeletedMessages,
    );
    _selectedTheme = ChatTheme.houExpress();
    _channelName = 'Channel';
    _userName = 'Unknown';
    _userCode = 'Unknown ID';
    _userAvatarUrl = null;
    config.logger.i('RealChatService initialized');
  }

  @override
  dynamic get client => _httpClient;

  @override
  Future<void> initialize() async {
    final response = await _httpClient.getSignedJwtToken(userId: _userCode);
    final token = response['data']!;
    await _socketClient.initialize(
      token: token,
    );
  }

  @override
  void dispose() {
    _socketClient.dispose();
  }

  Future<void> joinChannel(String channelId) async {
    await _socketClient.joinChannel(channelId);
  }

  @override
  void addListener(ChatServiceListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  @override
  void removeListener(ChatServiceListener listener) {
    _listeners.remove(listener);
  }

  void _notifyMessagesChanged() {
    for (final listener in _listeners) {
      listener.onMessagesChanged(List.unmodifiable(_messagesCache));
    }
  }

  void _notifyUserDataChanged() {
    for (final listener in _listeners) {
      listener.onUserDataChanged(
        userName: _userName,
        userCode: _userCode,
        userAvatarUrl: _userAvatarUrl,
      );
    }
  }

  void _notifyChannelNameChanged() {
    for (final listener in _listeners) {
      listener.onChannelNameChanged(_channelName);
    }
  }

  void _notifyThemeChanged() {
    for (final listener in _listeners) {
      listener.onThemeChanged(_selectedTheme);
    }
  }

  @override
  List<Message> getMessagesCache() => List.unmodifiable(_messagesCache);

  @override
  ChatTheme getSelectedTheme() => _selectedTheme;

  @override
  String getCachedChannelName() => _channelName;

  @override
  String getCachedUserName() => _userName;

  @override
  String getCachedUserCode() => _userCode;

  @override
  String? getCachedUserAvatarUrl() => _userAvatarUrl;

  @override
  void setSelectedTheme(ChatTheme theme) {
    _selectedTheme = theme;
    _notifyThemeChanged();
  }

  @override
  void setChannelName(String name) {
    _channelName = name;
    _notifyChannelNameChanged();
  }

  @override
  void setUserName(String name) {
    _userName = name;
    _notifyUserDataChanged();
  }

  @override
  void setUserCode(String code) {
    _userCode = code;
    _notifyUserDataChanged();
  }

  @override
  void setUserAvatarUrl(String? url) {
    _userAvatarUrl = url;
    _notifyUserDataChanged();
  }

  void _handleNewMessage(Message message) {
    if (message.sender != _userCode) {
      _messagesCache.add(message);
      _notifyMessagesChanged();
      config.logger.d("New message arrived: ${message.id}");
    }
  }

  void _handleDeletedMessages(List<String> messageIds) {
    bool didChange = false;
    for (final id in messageIds) {
      final target = _messagesCache.firstWhereOrNull((m) => m.id == id);
      if (target == null) {
        // not found
        continue;
      }
      if (target.sender == _userCode) {
        // we'll handle it by ack
        continue;
      } else {
        didChange = true;
        _messagesCache.remove(target);
      }
    }
    if (didChange) {
      _notifyMessagesChanged();
    }
  }

  @override
  Future<List<Message>> getMessages({
    required String channelId,
    int limit = 20,
    GetMessageOpt? getMessageOpt,
    String? optMessageId,
  }) async {
    try {
      config.logger.i(
        'RealChatService.getMessages called - channelId: $channelId, limit: $limit, opt: $getMessageOpt',
      );

      // Prepare pagination parameters
      String? refMessageId;
      String? op;

      if (getMessageOpt == GetMessageOpt.lt && optMessageId != null) {
        refMessageId = optMessageId;
        op = 'id_lt';
      } else if (getMessageOpt == GetMessageOpt.lte && optMessageId != null) {
        refMessageId = optMessageId;
        op = 'id_lte';
      }

      config.logger.d(
        'Calling HTTP client with refMessageId: $refMessageId, op: $op',
      );

      final filter = (op == null || refMessageId == null)
          ? null
          : MessageFilter(refMessageId: refMessageId, refMessageOpt: op);

      // Fetch from API
      final response = await _socketClient.getMessages(
        // channelId: channelId,
        limit: limit,
        filter: filter,
        // refMessageId: refMessageId,
        // op: op,
      );

      // config.logger.d('HTTP response received: ${response.keys.toList()}');

      // Parse response
      // final messagesData = response['data']?['messages'] as List?;
      final messagesData = response;
      config.logger.i('Found ${messagesData.length} messages in API response');

      // Convert to Message objects
      final newMessages = messagesData;
      // final newMessages = (messagesData)
      //     .map((msgJson) => Message.fromStreamChatJson(msgJson))
      //     .toList()
      //     .cast<Message>();

      config.logger.i(
        'Converted ${newMessages.length} messages to Message objects',
      );

      // If this is an initial load (no pagination opt), replace cache
      if (getMessageOpt == null) {
        config.logger.i(
          'Initial load: replacing cache with ${newMessages.length} messages',
        );
        _messagesCache.clear();
        _messagesCache.addAll(newMessages);
        _notifyMessagesChanged();
        config.logger.i(
          'Cache updated. Current cache size: ${_messagesCache.length}',
        );
        return newMessages;
      }

      // For pagination (getMessageOpt.lt or lte), merge with cache avoiding duplicates
      final existingIds = _messagesCache.map((m) => m.id).toSet();
      final uniqueNewMessages = newMessages
          .where((m) => !existingIds.contains(m.id))
          .toList();

      config.logger.i(
        'Pagination: found ${uniqueNewMessages.length} new unique messages (existing: ${existingIds.length})',
      );

      // Prepend new messages (they are older messages from before)
      if (uniqueNewMessages.isNotEmpty) {
        _messagesCache.insertAll(0, uniqueNewMessages);
        _notifyMessagesChanged();
        config.logger.i(
          'Cache updated after pagination. Current cache size: ${_messagesCache.length}',
        );
      }

      return newMessages;
    } catch (e) {
      config.logger.e('Error fetching messages', error: e);
      rethrow;
    }
  }

  @override
  Future<void> sendMessage({
    required String channelId,
    required String messageText,
  }) async {
    try {
      config.logger.i(
        'RealChatService.sendMessage called for channel: $channelId',
      );

      // Get user ID from configured storage
      final userDataJson = config.storage.getString(config.userDataKey);

      if (userDataJson == null) {
        config.logger.e('User data not found in storage');
        throw Exception('User not authenticated');
      }

      final userData = jsonDecode(userDataJson) as Map<String, dynamic>;
      config.logger.d('User data keys: ${userData.keys.toList()}');

      final userId = userData[config.userIdField]?.toString();

      if (userId == null) {
        config.logger.e(
          '${config.userIdField} not found in user data: $userData',
        );
        throw Exception('Invalid user data - ${config.userIdField} missing');
      }

      config.logger.i('Sending message with ${config.userIdField}: $userId');

      // Create ghost message immediately with temporary ID (optimistic UI update)
      // This appears in the UI immediately with reduced opacity
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final ghostMessage = Message(
        id: ghostMessageId,
        sender: userId,
        text: messageText.isNotEmpty ? messageText : null,
        attachments: null,
        isSending: true, // Ghost message is marked as sending
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        isDeleted: false,
      );

      config.logger.d('Added ghost message with ID: $ghostMessageId');
      _messagesCache.add(ghostMessage);
      _notifyMessagesChanged();

      // Start HTTP request in background without awaiting
      _socketClient
          .sendMessage(text: messageText)
          .then((response) {
            // Extract message ID and timestamp from API response
            config.logger.d('Full HTTP response: $response');
            final responseData =
                response['data'] as Map<String, dynamic>? ?? response;
            final messageId =
                responseData['message_id'] as String? ?? 'unknown';
            final sentAt =
                responseData['sent_at'] as String? ??
                DateTime.now().toIso8601String();

            config.logger.d(
              'API response - message_id: $messageId, sent_at: $sentAt',
            );

            // Remove ghost message and replace with confirmed message
            _messagesCache.remove(ghostMessage);

            // Construct confirmed Message object with real data from API
            final confirmedMessage = Message(
              id: messageId,
              sender: userId,
              text: messageText.isNotEmpty ? messageText : null,
              attachments: null,
              isSending: false, // Now fully confirmed
              createdAt: sentAt,
              updatedAt: sentAt,
              isDeleted: false,
            );

            _messagesCache.add(confirmedMessage);
            _notifyMessagesChanged();
            config.logger.i('Ghost message confirmed with real ID: $messageId');
          })
          .catchError((e) {
            // On error, remove or mark the ghost message as failed
            config.logger.e('Error sending message', error: e);
            // Remove failed message from UI
            _messagesCache.remove(ghostMessage);
            _notifyMessagesChanged();
            // Don't rethrow since we've already handled the message
          });
    } catch (e) {
      config.logger.e('Error preparing message', error: e);
      rethrow;
    }
  }

  @override
  Future<void> sendAttachment({
    required String channelId,
    required Map<String, dynamic> attachment,
  }) async {
    // TODO: Implement real API attachment sending
    throw UnimplementedError(
      'sendAttachment not yet implemented for RealChatService',
    );
  }

  @override
  Future<void> sendImage({
    required String channelId,
    required XFile imageFile,
    required int imageWidth,
    required int imageHeight,
    String? messageText,
  }) async {
    try {
      config.logger.i(
        'RealChatService.sendImage called for channel: $channelId, image: ${imageFile.name}',
      );

      // Get user ID from configured storage
      final userDataJson = config.storage.getString(config.userDataKey);

      if (userDataJson == null) {
        config.logger.e('User data not found in storage');
        throw Exception('User not authenticated');
      }

      final userData = jsonDecode(userDataJson) as Map<String, dynamic>;
      final userId = userData[config.userIdField]?.toString();

      if (userId == null) {
        config.logger.e('${config.userIdField} not found in user data');
        throw Exception('Invalid user data - ${config.userIdField} missing');
      }

      config.logger.i('Uploading image with userId: $userId');

      // Read image bytes to build a data URI preview for the ghost message.
      // This lets the resolver render the actual image while the upload is
      // still in progress, instead of showing an error for an empty URL.
      final imageBytes = await imageFile.readAsBytes();
      final mimeType = lookupMimeType(imageFile.path) ?? 'image/jpeg';
      final dataUri = 'data:$mimeType;base64,${base64Encode(imageBytes)}';

      // Create ghost message immediately with attachment placeholder (optimistic UI update)
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final placeholderAttachment = {
        'type': 'image',
        'image_url':
            dataUri, // Data URI preview; replaced with real URL on upload
        'fallback': imageFile.name,
        'original_width': imageWidth,
        'original_height': imageHeight,
      };

      final ghostMessage = Message(
        id: ghostMessageId,
        sender: userId,
        text: messageText?.isNotEmpty == true ? messageText : null,
        attachments: [placeholderAttachment],
        isSending: true, // Ghost message is marked as sending
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        isDeleted: false,
      );

      config.logger.d('Added ghost image message with ID: $ghostMessageId');
      _messagesCache.add(ghostMessage);
      _notifyMessagesChanged();

      // Start upload and send in background without awaiting
      // Randomize the key so the same file can be uploaded multiple times
      final uploadKey =
          '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      _httpClient
          .uploadImage(
            channelId: channelId,
            userId: userId,
            filePath: imageFile.path,
            namespace: [channelId],
            key: uploadKey,
          )
          .then((uploadResponse) {
            // Extract image URL from response
            final responseData =
                uploadResponse['data'] as Map<String, dynamic>? ??
                uploadResponse;
            final imageUrl =
                "${config.baseUrl}/chat/resource/${responseData['full_path']}";

            config.logger.i('Image uploaded successfully. URL: $imageUrl');

            // Update placeholder with real image URL
            placeholderAttachment['image_url'] = imageUrl;

            // Send message with attachment
            return _socketClient.sendMessage(
              text: messageText,
              attachments: [placeholderAttachment],
            );
          })
          .then((messageResponse) {
            // Extract message ID and timestamp from API response
            config.logger.d('Message response: $messageResponse');
            final messageData =
                messageResponse['data'] as Map<String, dynamic>? ??
                messageResponse;
            final messageId = messageData['message_id'] as String? ?? 'unknown';
            final sentAt =
                messageData['sent_at'] as String? ??
                DateTime.now().toIso8601String();

            config.logger.d(
              'API response - message_id: $messageId, sent_at: $sentAt',
            );

            // Remove ghost message and replace with confirmed message
            _messagesCache.remove(ghostMessage);

            // Construct confirmed Message object with real data from API
            final confirmedMessage = Message(
              id: messageId,
              sender: userId,
              text: messageText?.isNotEmpty == true ? messageText : null,
              attachments: [placeholderAttachment],
              isSending: false, // Now fully confirmed
              createdAt: sentAt,
              updatedAt: sentAt,
              isDeleted: false,
            );

            _messagesCache.add(confirmedMessage);
            _notifyMessagesChanged();
            config.logger.i(
              'Ghost image message confirmed with real ID: $messageId',
            );
          })
          .catchError((e) {
            // On error, remove the ghost message
            config.logger.e('Error sending image', error: e);
            // Remove failed message from UI
            _messagesCache.remove(ghostMessage);
            _notifyMessagesChanged();
            // Don't rethrow since we've already handled the message
          });
    } catch (e) {
      config.logger.e('Error preparing image message', error: e);
      rethrow;
    }
  }

  @override
  Future<void> sendFile({
    required String channelId,
    required XFile file,
    String? messageText,
  }) async {
    try {
      config.logger.i(
        'RealChatService.sendFile called for channel: $channelId, file: ${file.name}',
      );

      // Get user ID from configured storage
      final userDataJson = config.storage.getString(config.userDataKey);

      if (userDataJson == null) {
        config.logger.e('User data not found in storage');
        throw Exception('User not authenticated');
      }

      final userData = jsonDecode(userDataJson) as Map<String, dynamic>;
      final userId = userData[config.userIdField]?.toString();

      if (userId == null) {
        config.logger.e('${config.userIdField} not found in user data');
        throw Exception('Invalid user data - ${config.userIdField} missing');
      }

      config.logger.i('Uploading file with userId: $userId');

      // Get file size and MIME type
      final fileSize = await file.length();
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
      final attachmentType = _getAttachmentTypeFromMimeType(mimeType);

      config.logger.d(
        'File info - size: $fileSize bytes, MIME: $mimeType, type: $attachmentType',
      );

      // Create ghost message immediately with attachment placeholder (optimistic UI update)
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final placeholderAttachment = <String, dynamic>{
        'type': attachmentType,
        'title': file.name,
        'asset_url': '', // Will be updated when upload completes
        'mime_type': mimeType,
        'file_size': fileSize,
      };

      final ghostMessage = Message(
        id: ghostMessageId,
        sender: userId,
        text: messageText?.isNotEmpty == true ? messageText : null,
        attachments: [placeholderAttachment],
        isSending: true, // Ghost message is marked as sending
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        isDeleted: false,
      );

      config.logger.d('Added ghost file message with ID: $ghostMessageId');
      _messagesCache.add(ghostMessage);
      _notifyMessagesChanged();

      // Start upload and send in background without awaiting
      // Randomize the key so the same file can be uploaded multiple times
      final uploadKey = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      _httpClient
          .uploadFile(
            channelId: channelId,
            userId: userId,
            filePath: file.path,
            namespace: [channelId],
            key: uploadKey,
          )
          .then((uploadResponse) {
            // Extract file URL from response
            final responseData =
                uploadResponse['data'] as Map<String, dynamic>? ??
                uploadResponse;
            final fileUrl =
                "${config.baseUrl}/chat/resource/${responseData['full_path']}";
            // final fileUrl = responseData['file'] as String?;

            config.logger.i('File uploaded successfully. URL: $fileUrl');

            // Update placeholder with real file URL
            placeholderAttachment['asset_url'] = fileUrl;

            // For videos, also include thumb_url if present
            final thumbUrl = responseData['thumb_url'] as String?;
            if (thumbUrl != null &&
                attachmentType == config.attachmentTypeVideo) {
              placeholderAttachment['thumb_url'] = thumbUrl;
              config.logger.d('Added video thumbnail URL');
            }

            // Send message with attachment
            return _socketClient.sendMessage(
              text: messageText,
              attachments: [placeholderAttachment],
            );
          })
          .then((messageResponse) {
            // Extract message ID and timestamp from API response
            config.logger.d('Message response: $messageResponse');
            final messageData =
                messageResponse['data'] as Map<String, dynamic>? ??
                messageResponse;
            final messageId = messageData['message_id'] as String? ?? 'unknown';
            final sentAt =
                messageData['sent_at'] as String? ??
                DateTime.now().toIso8601String();

            config.logger.d(
              'API response - message_id: $messageId, sent_at: $sentAt',
            );

            // Remove ghost message and replace with confirmed message
            _messagesCache.remove(ghostMessage);

            // Construct confirmed Message object with real data from API
            final confirmedMessage = Message(
              id: messageId,
              sender: userId,
              text: messageText?.isNotEmpty == true ? messageText : null,
              attachments: [placeholderAttachment],
              isSending: false, // Now fully confirmed
              createdAt: sentAt,
              updatedAt: sentAt,
              isDeleted: false,
            );

            _messagesCache.add(confirmedMessage);
            _notifyMessagesChanged();
            config.logger.i(
              'Ghost file message confirmed with real ID: $messageId',
            );
          })
          .catchError((e) {
            // On error, remove the ghost message
            config.logger.e('Error sending file', error: e);
            // Remove failed message from UI
            _messagesCache.remove(ghostMessage);
            _notifyMessagesChanged();
            // Don't rethrow since we've already handled the message
          });
    } catch (e) {
      config.logger.e('Error preparing file message', error: e);
      rethrow;
    }
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    try {
      config.logger.i(
        "RealChatService.deleteMessage called for channel: $channelId",
      );

      _socketClient
          .deleteMessages(messageIds: [messageId])
          .then((response) {
            config.logger.d("Full HTTP response: $response");
            final responseData =
                response['data'] as Map<String, dynamic>? ?? response;
            final messageIds = (responseData['message_ids'] as List<dynamic>)
                .cast<String>();
            config.logger.d("API response - deleted message ids: $messageIds");

            _messagesCache.removeWhere((m) => messageIds.contains(m.id));
            _notifyMessagesChanged();
            config.logger.i("Messages has been deleted");
          })
          .catchError((e) {
            config.logger.e("Error deleting message", error: e);
          });
    } catch (e) {
      config.logger.e("Error trying to delete message", error: e);
      rethrow;
    }
  }

  @override
  Future<void> sendVoiceRecording({
    required String channelId,
    required String filePath,
    required int durationMilliseconds,
  }) async {
    try {
      config.logger.i(
        'RealChatService.sendVoiceRecording called for channel: $channelId',
      );

      // Get user ID from configured storage
      final userDataJson = config.storage.getString(config.userDataKey);

      if (userDataJson == null) {
        config.logger.e('User data not found in storage');
        throw Exception('User not authenticated');
      }

      final userData = jsonDecode(userDataJson) as Map<String, dynamic>;
      final userId = userData[config.userIdField]?.toString();

      if (userId == null) {
        config.logger.e('${config.userIdField} not found in user data');
        throw Exception('Invalid user data - ${config.userIdField} missing');
      }

      config.logger.i('Uploading voice recording with userId: $userId');

      // Get file size
      final file = File(filePath);
      final fileSize = await file.length();
      final durationSeconds = durationMilliseconds ~/ 1000;
      const mimeType = 'audio/ogg';
      const attachmentType = 'voiceRecording';

      config.logger.d(
        'Voice recording info - size: $fileSize bytes, duration: $durationSeconds seconds',
      );

      // Create ghost message immediately with attachment placeholder (optimistic UI update)
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final placeholderAttachment = <String, dynamic>{
        'type': attachmentType,
        'asset_url': '', // Will be updated when upload completes
        'duration': durationSeconds,
        'mime_type': mimeType,
      };

      final ghostMessage = Message(
        id: ghostMessageId,
        sender: userId,
        text: null, // Voice recordings have no text
        attachments: [placeholderAttachment],
        isSending: true, // Ghost message is marked as sending
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        isDeleted: false,
      );

      config.logger.d(
        'Added ghost voice recording message with ID: $ghostMessageId',
      );
      _messagesCache.add(ghostMessage);
      _notifyMessagesChanged();

      // Start upload and send in background without awaiting
      // Randomize the key so the same file can be uploaded multiple times
      final uploadKey =
          '${DateTime.now().millisecondsSinceEpoch}_${Path(filePath).fileName()}';
      _httpClient
          .uploadFile(
            channelId: channelId,
            userId: userId,
            filePath: filePath,
            namespace: [channelId],
            key: uploadKey,
          )
          .then((uploadResponse) {
            // Extract file URL from response
            final responseData =
                uploadResponse['data'] as Map<String, dynamic>? ??
                uploadResponse;
            final fileUrl =
                "${config.baseUrl}/chat/resource/${responseData['full_path']}";
            // final fileUrl = responseData['file'] as String?;

            config.logger.i(
              'Voice recording uploaded successfully. URL: $fileUrl',
            );

            // Update placeholder with real file URL
            placeholderAttachment['asset_url'] = fileUrl;

            // Send message with voice recording attachment
            return _socketClient.sendMessage(
              text: null,
              attachments: [placeholderAttachment],
            );
          })
          .then((messageResponse) {
            // Extract message ID and timestamp from API response
            config.logger.d('Message response: $messageResponse');
            final messageData =
                messageResponse['data'] as Map<String, dynamic>? ??
                messageResponse;
            final messageId = messageData['message_id'] as String? ?? 'unknown';
            final sentAt =
                messageData['sent_at'] as String? ??
                DateTime.now().toIso8601String();

            config.logger.d(
              'API response - message_id: $messageId, sent_at: $sentAt',
            );

            // Remove ghost message and replace with confirmed message
            _messagesCache.remove(ghostMessage);

            // Construct confirmed Message object with real data from API
            final confirmedMessage = Message(
              id: messageId,
              sender: userId,
              text: null,
              attachments: [placeholderAttachment],
              isSending: false, // Now fully confirmed
              createdAt: sentAt,
              updatedAt: sentAt,
              isDeleted: false,
            );

            _messagesCache.add(confirmedMessage);
            _notifyMessagesChanged();
            config.logger.i(
              'Ghost voice recording message confirmed with real ID: $messageId',
            );
          })
          .catchError((e) {
            // On error, remove the ghost message
            config.logger.e('Error sending voice recording', error: e);
            // Remove failed message from UI
            _messagesCache.remove(ghostMessage);
            _notifyMessagesChanged();
            // Don't rethrow since we've already handled the message
          });
    } catch (e) {
      config.logger.e('Error preparing voice recording message', error: e);
      rethrow;
    }
  }

  @override
  Future<String?> downloadFile({
    required Message message,
    String? imageUrl,
    Uint8List? imageBytes,
    String fileExtension = 'jpg',
  }) async {
    try {
      config.logger.i(
        'RealChatService.downloadFile called for message: ${message.id}',
      );

      // Get downloads directory (platform-aware using path_provider)
      final downloadsDir = await getDownloadsDirectory();

      if (downloadsDir == null) {
        config.logger.e('Downloads directory not available on this platform');
        return null;
      }

      // Create file path with deterministic naming based on Message metadata
      // Use updated_at if available (reflects latest edit), otherwise fall back to created_at
      final dateString = message.updatedAt ?? message.createdAt;
      final dateTime = dateString != null
          ? DateTime.parse(dateString)
          : DateTime.now();
      final uniqueId = dateTime.millisecondsSinceEpoch.toString();

      // Use type-specific prefix based on file extension
      final prefix = _getPrefixFromExtension(fileExtension);
      final fileName = '${prefix}_$uniqueId.$fileExtension';

      final filePath = '${downloadsDir.path}/$fileName';
      final file = File(filePath);

      // Check if file already exists - skip download if cached
      if (await file.exists()) {
        config.logger.i('File already exists in cache: $filePath');
        return filePath;
      }

      // File doesn't exist, get file bytes - either from in-memory bytes or download from URL
      late Uint8List bytes;

      // Check if bytes are directly provided
      if (imageBytes != null) {
        bytes = imageBytes;
        config.logger.i('Using in-memory bytes for file save');
      } else if (imageUrl != null) {
        config.logger.i('Downloading from URL: $imageUrl');
        // Download file bytes using HTTP client
        List<int> downloadedBytes = await _httpClient.downloadFileFromUrl(
          imageUrl,
        );
        bytes = Uint8List.fromList(downloadedBytes);
      } else {
        config.logger.e('No image URL or bytes provided');
        return null;
      }

      // Write file
      await file.writeAsBytes(bytes);

      config.logger.i('File downloaded and saved to: $filePath');
      return filePath;
    } catch (e) {
      config.logger.e('Error downloading file', error: e);
      return null;
    }
  }

  /// Get type-specific prefix based on file extension
  String _getPrefixFromExtension(String extension) {
    final ext = extension.toLowerCase();

    // Image extensions
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff'].contains(ext)) {
      return 'image';
    }

    // Video extensions
    if ([
      'mp4',
      'mkv',
      'avi',
      'mov',
      'flv',
      'wmv',
      'webm',
      '3gp',
    ].contains(ext)) {
      return 'video';
    }

    // Audio extensions
    if ([
      'mp3',
      'wav',
      'flac',
      'aac',
      'm4a',
      'aiff',
      'ogg',
      'wma',
    ].contains(ext)) {
      return 'audio';
    }

    // Default for generic files
    return 'file';
  }

  /// Determine attachment type from MIME type
  /// Maps MIME types to audio/video/file attachment types
  String _getAttachmentTypeFromMimeType(String mimeType) {
    final mime = mimeType.toLowerCase();

    // Audio MIME types
    if (mime.startsWith('audio/')) {
      return config.attachmentTypeAudio; // 'audio'
    }

    // Video MIME types
    if (mime.startsWith('video/')) {
      return config.attachmentTypeVideo; // 'video'
    }

    // Default to generic file type
    return config.attachmentTypeFile; // 'file'
  }

  @override
  Future<String?> getChannelName({required String channelId}) async {
    try {
      config.logger.i(
        '[RealChatService] Fetching channel name for: $channelId',
      );

      final response = await _socketClient.getChannelDetails();

      // Extract the name from the response data
      final data = response['data'] as Map<String, dynamic>?;
      final name = data?['name'] as String?;

      config.logger.d('[RealChatService] Channel name fetched: $name');
      return name;
    } catch (e) {
      config.logger.e(
        '[RealChatService] Error fetching channel name',
        error: e,
      );
      // Return null on error so we can fallback to channelId in UI
      return null;
    }
  }
}
