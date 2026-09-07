import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rust/rust.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
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
  Future<void> sendVideo({
    required String channelId,
    required XFile videoFile,
    String? messageText,
  }) async {
    try {
      config.logger.i(
        'RealChatService.sendVideo called for channel: $channelId, video: ${videoFile.name}',
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

      config.logger.i('Uploading video with userId: $userId');

      // Get file size and MIME type
      final fileSize = await videoFile.length();
      final mimeType = lookupMimeType(videoFile.path) ?? 'video/mp4';

      config.logger.d(
        'Video info - size: $fileSize bytes, MIME: $mimeType',
      );

      // Generate a thumbnail from the video client-side so we can include it
      // as thumb_url even if the server doesn't generate one automatically.
      final thumbnailPath = await _generateVideoThumbnail(videoFile.path);

      // Build a data URI from the generated thumbnail so the ghost message can
      // render it immediately while the upload is in progress.
      String? thumbnailDataUri;
      if (thumbnailPath != null) {
        try {
          final thumbBytes = await File(thumbnailPath).readAsBytes();
          thumbnailDataUri =
              'data:image/jpeg;base64,${base64Encode(thumbBytes)}';
        } catch (e) {
          config.logger.e('Failed to read thumbnail bytes', error: e);
        }
      }

      // Create ghost message immediately with attachment placeholder (optimistic UI update)
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final placeholderAttachment = <String, dynamic>{
        'type': config.attachmentTypeVideo,
        'title': videoFile.name,
        // Point to the local video path so there's something to see immediately;
        // replaced with the real URL once the upload completes.
        'asset_url': videoFile.path,
        // Data URI preview of the generated thumbnail; replaced with the real
        // URL once the upload completes.
        'thumb_url': thumbnailDataUri ?? '',
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

      config.logger.d('Added ghost video message with ID: $ghostMessageId');
      _messagesCache.add(ghostMessage);
      _notifyMessagesChanged();

      // Start upload and send in background without awaiting
      // Randomize the key so the same file can be uploaded multiple times
      final uploadKey =
          '${DateTime.now().millisecondsSinceEpoch}_${videoFile.name}';

      _httpClient
          .uploadFile(
            channelId: channelId,
            userId: userId,
            filePath: videoFile.path,
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

            config.logger.i('Video uploaded successfully. URL: $fileUrl');

            // Update placeholder with real video URL
            placeholderAttachment['asset_url'] = fileUrl;

            // Prefer a server-provided thumbnail, otherwise fall back to the
            // client-generated one we uploaded.
            final serverThumbUrl = responseData['thumb_url'] as String?;
            if (serverThumbUrl != null) {
              placeholderAttachment['thumb_url'] = serverThumbUrl;
              config.logger.d('Added server-provided video thumbnail URL');
              // Send message with attachment
              return _socketClient.sendMessage(
                text: messageText,
                attachments: [placeholderAttachment],
              );
            }

            if (thumbnailPath != null) {
              // Upload the client-generated thumbnail as an image and use its URL
              final thumbKey =
                  '${DateTime.now().millisecondsSinceEpoch}_thumb_${videoFile.name}.jpg';
              return _httpClient
                  .uploadImage(
                    channelId: channelId,
                    userId: userId,
                    filePath: thumbnailPath,
                    namespace: [channelId],
                    key: thumbKey,
                  )
                  .then((thumbResponse) {
                    final thumbData =
                        thumbResponse['data'] as Map<String, dynamic>? ??
                        thumbResponse;
                    final thumbUrl =
                        "${config.baseUrl}/chat/resource/${thumbData['full_path']}";
                    placeholderAttachment['thumb_url'] = thumbUrl;
                    config.logger.d(
                      'Added client-generated video thumbnail URL: $thumbUrl',
                    );
                    // Send message with attachment
                    return _socketClient.sendMessage(
                      text: messageText,
                      attachments: [placeholderAttachment],
                    );
                  });
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
              'Ghost video message confirmed with real ID: $messageId',
            );
          })
          .catchError((e) {
            // On error, remove the ghost message
            config.logger.e('Error sending video', error: e);
            // Remove failed message from UI
            _messagesCache.remove(ghostMessage);
            _notifyMessagesChanged();
            // Don't rethrow since we've already handled the message
          });
    } catch (e) {
      config.logger.e('Error preparing video message', error: e);
      rethrow;
    }
  }

  /// Generate a thumbnail image from a video file.
  /// Returns the path to the generated thumbnail, or null if generation failed.
  Future<String?> _generateVideoThumbnail(String videoPath) async {
    try {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        quality: 80,
        maxWidth: 480,
      );
      config.logger.d('Generated video thumbnail at: $thumbnailPath');
      return thumbnailPath;
    } catch (e) {
      config.logger.e('Failed to generate video thumbnail', error: e);
      return null;
    }
  }

  @override
  Future<void> sendMedia({
    required String channelId,
    required List<MediaAttachment> media,
    String? messageText,
  }) async {
    if (media.isEmpty) return;

    try {
      config.logger.i(
        'RealChatService.sendMedia called for channel: $channelId, media count: ${media.length}',
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

      config.logger.i(
        'Uploading ${media.length} media items with userId: $userId',
      );

      // Prepare placeholder attachments and per-item upload metadata.
      // For images we build a data URI preview; for videos we generate a
      // thumbnail and build a data URI from it so the ghost message can render
      // something immediately while uploads are in progress.
      final placeholderAttachments = <Map<String, dynamic>>[];
      final uploadTasks = <Future<Map<String, dynamic>>>[];

      for (final item in media) {
        final file = item.file;
        final mimeType =
            lookupMimeType(file.path) ??
            (item.isVideo ? 'video/mp4' : 'image/jpeg');

        if (item.isVideo) {
          final fileSize = await file.length();
          final thumbnailPath = await _generateVideoThumbnail(file.path);

          String? thumbnailDataUri;
          if (thumbnailPath != null) {
            try {
              final thumbBytes = await File(thumbnailPath).readAsBytes();
              thumbnailDataUri =
                  'data:image/jpeg;base64,${base64Encode(thumbBytes)}';
            } catch (e) {
              config.logger.e('Failed to read thumbnail bytes', error: e);
            }
          }

          final attachment = <String, dynamic>{
            'type': config.attachmentTypeVideo,
            'title': file.name,
            'asset_url': file.path, // Local preview; replaced on upload
            'thumb_url': thumbnailDataUri ?? '',
            'mime_type': mimeType,
            'file_size': fileSize,
          };
          placeholderAttachments.add(attachment);

          final uploadKey =
              '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          uploadTasks.add(
            _httpClient
                .uploadFile(
                  channelId: channelId,
                  userId: userId,
                  filePath: file.path,
                  namespace: [channelId],
                  key: uploadKey,
                )
                .then((uploadResponse) {
                  final responseData =
                      uploadResponse['data'] as Map<String, dynamic>? ??
                      uploadResponse;
                  final fileUrl =
                      "${config.baseUrl}/chat/resource/${responseData['full_path']}";
                  attachment['asset_url'] = fileUrl;

                  // Prefer server-provided thumbnail, else upload the
                  // client-generated one.
                  final serverThumbUrl = responseData['thumb_url'] as String?;
                  if (serverThumbUrl != null) {
                    attachment['thumb_url'] = serverThumbUrl;
                    return uploadResponse;
                  }
                  if (thumbnailPath != null) {
                    final thumbKey =
                        '${DateTime.now().millisecondsSinceEpoch}_thumb_${file.name}.jpg';
                    return _httpClient
                        .uploadImage(
                          channelId: channelId,
                          userId: userId,
                          filePath: thumbnailPath,
                          namespace: [channelId],
                          key: thumbKey,
                        )
                        .then((thumbResponse) {
                          final thumbData =
                              thumbResponse['data'] as Map<String, dynamic>? ??
                              thumbResponse;
                          final thumbUrl =
                              "${config.baseUrl}/chat/resource/${thumbData['full_path']}";
                          attachment['thumb_url'] = thumbUrl;
                          return thumbResponse;
                        });
                  }
                  return uploadResponse;
                }),
          );
        } else {
          // Image
          final imageBytes = await file.readAsBytes();
          final dataUri = 'data:$mimeType;base64,${base64Encode(imageBytes)}';

          final attachment = <String, dynamic>{
            'type': config.attachmentTypeImage,
            'image_url': dataUri, // Data URI preview; replaced on upload
            'fallback': file.name,
            'original_width': item.imageWidth,
            'original_height': item.imageHeight,
          };
          placeholderAttachments.add(attachment);

          final uploadKey =
              '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          uploadTasks.add(
            _httpClient
                .uploadImage(
                  channelId: channelId,
                  userId: userId,
                  filePath: file.path,
                  namespace: [channelId],
                  key: uploadKey,
                )
                .then((uploadResponse) {
                  final responseData =
                      uploadResponse['data'] as Map<String, dynamic>? ??
                      uploadResponse;
                  final imageUrl =
                      "${config.baseUrl}/chat/resource/${responseData['full_path']}";
                  attachment['image_url'] = imageUrl;
                  return uploadResponse;
                }),
          );
        }
      }

      // Create ghost message immediately with all placeholder attachments
      // (optimistic UI update).
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final ghostMessage = Message(
        id: ghostMessageId,
        sender: userId,
        text: messageText?.isNotEmpty == true ? messageText : null,
        attachments: placeholderAttachments,
        isSending: true, // Ghost message is marked as sending
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        isDeleted: false,
      );

      config.logger.d('Added ghost media message with ID: $ghostMessageId');
      _messagesCache.add(ghostMessage);
      _notifyMessagesChanged();

      // Upload all media in parallel, then send a single message with all
      // attachments once every upload completes.
      Future.wait(uploadTasks)
          .then((_) {
            return _socketClient.sendMessage(
              text: messageText,
              attachments: placeholderAttachments,
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
              attachments: placeholderAttachments,
              isSending: false, // Now fully confirmed
              createdAt: sentAt,
              updatedAt: sentAt,
              isDeleted: false,
            );

            _messagesCache.add(confirmedMessage);
            _notifyMessagesChanged();
            config.logger.i(
              'Ghost media message confirmed with real ID: $messageId',
            );
          })
          .catchError((e) {
            // On error, remove the ghost message
            config.logger.e('Error sending media', error: e);
            // Remove failed message from UI
            _messagesCache.remove(ghostMessage);
            _notifyMessagesChanged();
            // Don't rethrow since we've already handled the message
          });
    } catch (e) {
      config.logger.e('Error preparing media message', error: e);
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

      // For image files, build a data URI preview for the ghost message so the
      // resolver can render the actual image while the upload is in progress,
      // instead of showing an error for an empty URL.
      String? dataUri;
      if (mimeType.toLowerCase().startsWith('image/')) {
        final bytes = await file.readAsBytes();
        dataUri = 'data:$mimeType;base64,${base64Encode(bytes)}';
      }

      // Create ghost message immediately with placeholder placeholder (optimistic UI update)
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final placeholderAttachment = <String, dynamic>{
        'type': attachmentType,
        'title': file.name,
        'asset_url':
            dataUri ?? '', // Data URI preview; replaced with real URL on upload
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
  Future<void> sendFiles({
    required String channelId,
    required List<XFile> files,
    String? messageText,
  }) async {
    if (files.isEmpty) return;

    try {
      config.logger.i(
        'RealChatService.sendFiles called for channel: $channelId, file count: ${files.length}',
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

      config.logger.i('Uploading ${files.length} files with userId: $userId');

      // Prepare placeholder attachments and per-file upload metadata.
      // All files are sent as generic 'file' attachments regardless of MIME
      // type. For image files we build a data URI preview so the ghost message
      // can render something immediately while uploads are in progress.
      final placeholderAttachments = <Map<String, dynamic>>[];
      final uploadTasks = <Future<Map<String, dynamic>>>[];

      for (final file in files) {
        final fileSize = await file.length();
        final mimeType =
            lookupMimeType(file.path) ?? 'application/octet-stream';

        // For image files, build a data URI preview for the ghost message.
        String? dataUri;
        if (mimeType.toLowerCase().startsWith('image/')) {
          final bytes = await file.readAsBytes();
          dataUri = 'data:$mimeType;base64,${base64Encode(bytes)}';
        }

        final attachment = <String, dynamic>{
          'type': config.attachmentTypeFile, // Always generic 'file'
          'title': file.name,
          'asset_url': dataUri ?? '', // Data URI preview; replaced on upload
          'mime_type': mimeType,
          'file_size': fileSize,
        };
        placeholderAttachments.add(attachment);

        final uploadKey =
            '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        uploadTasks.add(
          _httpClient
              .uploadFile(
                channelId: channelId,
                userId: userId,
                filePath: file.path,
                namespace: [channelId],
                key: uploadKey,
              )
              .then((uploadResponse) {
                final responseData =
                    uploadResponse['data'] as Map<String, dynamic>? ??
                    uploadResponse;
                final fileUrl =
                    "${config.baseUrl}/chat/resource/${responseData['full_path']}";
                attachment['asset_url'] = fileUrl;
                return uploadResponse;
              }),
        );
      }

      // Create ghost message immediately with all placeholder attachments
      // (optimistic UI update).
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final ghostMessage = Message(
        id: ghostMessageId,
        sender: userId,
        text: messageText?.isNotEmpty == true ? messageText : null,
        attachments: placeholderAttachments,
        isSending: true, // Ghost message is marked as sending
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        isDeleted: false,
      );

      config.logger.d('Added ghost files message with ID: $ghostMessageId');
      _messagesCache.add(ghostMessage);
      _notifyMessagesChanged();

      // Upload all files in parallel, then send a single message with all
      // attachments once every upload completes.
      Future.wait(uploadTasks)
          .then((_) {
            return _socketClient.sendMessage(
              text: messageText,
              attachments: placeholderAttachments,
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
              attachments: placeholderAttachments,
              isSending: false, // Now fully confirmed
              createdAt: sentAt,
              updatedAt: sentAt,
              isDeleted: false,
            );

            _messagesCache.add(confirmedMessage);
            _notifyMessagesChanged();
            config.logger.i(
              'Ghost files message confirmed with real ID: $messageId',
            );
          })
          .catchError((e) {
            // On error, remove the ghost message
            config.logger.e('Error sending files', error: e);
            // Remove failed message from UI
            _messagesCache.remove(ghostMessage);
            _notifyMessagesChanged();
            // Don't rethrow since we've already handled the message
          });
    } catch (e) {
      config.logger.e('Error preparing files message', error: e);
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
        'duration_millis': durationMilliseconds,
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
  Future<void> sendLocation({
    required String channelId,
    required double latitude,
    required double longitude,
    String? messageText,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      config.logger.i(
        'LOCATION_SEND start channel: $channelId, lat: $latitude, lng: $longitude '
        '(${stopwatch.elapsedMilliseconds}ms)',
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

      // Resolve the map preview thumbnail: fetch it from the server once,
      // upload it to the storage service, and cache the resulting URL keyed by
      // coordinates. This only happens now that the user has confirmed sending.
      config.logger.i(
        'LOCATION_SEND resolving thumbnail... (${stopwatch.elapsedMilliseconds}ms)',
      );
      final thumbUrl = await _getLocationThumbnailUrl(
        latitude: latitude,
        longitude: longitude,
      );
      config.logger.i(
        'LOCATION_SEND thumbnail resolved, thumbUrl=$thumbUrl '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );

      // Build the location attachment. No file upload is required since the
      // coordinates are sent directly as metadata. The map preview thumbnail
      // URL (cached in the external storage service) is baked in as `thumb_url`
      // so the renderer can display it without reconstructing it.
      final attachment = <String, dynamic>{
        'type': 'location',
        'latitude': latitude,
        'longitude': longitude,
        'title': 'Location',
        'thumb_url': thumbUrl,
      };

      // Create ghost message immediately (optimistic UI update)
      final ghostMessageId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      final ghostMessage = Message(
        id: ghostMessageId,
        sender: userId,
        text: messageText?.isNotEmpty == true ? messageText : null,
        attachments: [attachment],
        isSending: true,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        isDeleted: false,
      );

      config.logger.d('Added ghost location message with ID: $ghostMessageId');
      _messagesCache.add(ghostMessage);
      _notifyMessagesChanged();

      // Send in background without awaiting
      _socketClient
          .sendMessage(
            text: messageText,
            attachments: [attachment],
          )
          .then((messageResponse) {
            config.logger.d('Message response: $messageResponse');
            final messageData =
                messageResponse['data'] as Map<String, dynamic>? ??
                messageResponse;
            final messageId = messageData['message_id'] as String? ?? 'unknown';
            final sentAt =
                messageData['sent_at'] as String? ??
                DateTime.now().toIso8601String();

            // Remove ghost message and replace with confirmed message
            _messagesCache.remove(ghostMessage);

            final confirmedMessage = Message(
              id: messageId,
              sender: userId,
              text: messageText?.isNotEmpty == true ? messageText : null,
              attachments: [attachment],
              isSending: false,
              createdAt: sentAt,
              updatedAt: sentAt,
              isDeleted: false,
            );

            _messagesCache.add(confirmedMessage);
            _notifyMessagesChanged();
            config.logger.i(
              'LOCATION_SEND confirmed with real ID: $messageId '
              '(${stopwatch.elapsedMilliseconds}ms)',
            );
          })
          .catchError((e) {
            config.logger.e('Error sending location', error: e);
            _messagesCache.remove(ghostMessage);
            _notifyMessagesChanged();
          });
      stopwatch.stop();
    } catch (e) {
      config.logger.e(
        'LOCATION_SEND error after ${stopwatch.elapsedMilliseconds}ms',
        error: e,
      );
      stopwatch.stop();
      rethrow;
    }
  }

  /// Resolve the map preview thumbnail URL for the given coordinates.
  ///
  /// Fetches the PNG from the server once, uploads it to the storage service,
  /// and caches the resulting URL keyed by coordinates. Subsequent calls
  /// return the cached URL without hitting the server again.
  Future<String> _getLocationThumbnailUrl({
    required double latitude,
    required double longitude,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Storage key for the cached thumbnail URL for these coordinates.
    final cacheKey =
        'location_thumb_${latitude.toStringAsFixed(6)}_${longitude.toStringAsFixed(6)}';

    // Return the cached URL if we already fetched and uploaded it.
    final cached = config.storage.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      config.logger.d(
        'LOCATION_THUMB cache hit for $cacheKey (${stopwatch.elapsedMilliseconds}ms)',
      );
      stopwatch.stop();
      return cached;
    }
    config.logger.d(
      'LOCATION_THUMB cache miss for $cacheKey (${stopwatch.elapsedMilliseconds}ms)',
    );

    try {
      config.logger.i(
        'LOCATION_THUMB fetching for lat: $latitude, lng: $longitude '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );

      // 1. Download the PNG from the server.
      final thumbnailUrl =
          Uri.parse('${config.baseUrl}/chat/location/get-thumbnail')
              .replace(
                queryParameters: {
                  'lat': latitude.toString(),
                  'lon': longitude.toString(),
                },
              )
              .toString();
      config.logger.i(
        'LOCATION_THUMB downloading from $thumbnailUrl '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      final bytes = await _httpClient.downloadFileFromUrl(thumbnailUrl);
      config.logger.i(
        'LOCATION_THUMB downloaded ${bytes.length} bytes '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );

      // 2. Upload the bytes directly (no temp file write).
      final fileName =
          'location_thumb_${DateTime.now().millisecondsSinceEpoch}.png';
      final uploadKey = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      config.logger.i(
        'LOCATION_THUMB uploading bytes file=$fileName '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      final uploadResponse = await _httpClient.uploadFileBytes(
        channelId: _channelId ?? '',
        userId: _userCode,
        fileName: fileName,
        bytes: bytes,
        namespace: ['location'],
        key: uploadKey,
      );
      final responseData =
          uploadResponse['data'] as Map<String, dynamic>? ?? uploadResponse;
      final resourceUrl =
          "${config.baseUrl}/chat/resource/${responseData['full_path']}";
      config.logger.i(
        'LOCATION_THUMB uploaded, URL: $resourceUrl '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );

      // 3. Cache the resulting URL in the external storage service.
      config.storage.setString(cacheKey, resourceUrl);
      config.logger.i(
        'LOCATION_THUMB cached ($cacheKey) -> $resourceUrl '
        '(${stopwatch.elapsedMilliseconds}ms total)',
      );
      stopwatch.stop();

      return resourceUrl;
    } catch (e) {
      config.logger.e(
        'LOCATION_THUMB error after ${stopwatch.elapsedMilliseconds}ms',
        error: e,
      );
      stopwatch.stop();
      return '';
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
