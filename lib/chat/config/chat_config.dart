import 'dart:convert';

import 'chat_logger.dart';
import '../storage/api/chat_storage_adapter.dart';
import '../models.dart';
import 'chat_theme.dart';

/// Central configuration object for the chat module
/// All dependencies are supplied at instantiation time
/// See HomePage or similar for example initialization
class ChatConfig {
  /// API Configuration
  final String baseUrl;
  final String apiKey;

  /// Optional access token from the host application, sent as
  /// `Authorization: Bearer <token>` on every HTTP client request.
  final String? httpClientApiKey;

  /// The type of channel to create during service initialization.
  /// Defaults to a support channel.
  final ChannelType channelType;

  final String socketBaseUrl;

  /// A room the host has ALREADY opened (DMS: open-channel). When set,
  /// [channelType] is ignored: no /chat/sign-jwt, no /chat/create-channel,
  /// and the member's id comes from here, not from [storage].
  final ChatSession? session;

  /// A fresh socket token for every reconnect - chat-service accepts each
  /// token once. Without it a dropped socket stays down.
  final Future<String?> Function()? tokenProvider;

  /// Who is in the room, for the Members tab. The chat service does not
  /// list members to end users, so only the host can answer.
  final Future<List<ChatMember>> Function()? membersProvider;

  /// The host's CURRENT request headers (`Authorization`, app version, ...),
  /// read per request so a refreshed login token is picked up. Sent on every
  /// call to [baseUrl] and every file fetched from it. Wins over
  /// [httpClientApiKey].
  final Map<String, String> Function()? requestHeaders;

  /// Photos, files, voice notes and location in the composer. Off for a
  /// member who has no host to upload through (a public visitor): text only.
  final bool attachmentsEnabled;

  /// Theme Configuration
  final ChatTheme theme;

  /// Logger Implementation
  final ChatLogger logger;

  /// Storage Adapter
  final ChatStorageAdapter storage;

  /// Storage Keys
  final String userDataKey;
  final String messageCacheKey;
  final String themeKey;

  /// User ID Configuration
  /// Field name to extract user ID from userData (e.g., 'official_code', 'user_id')
  final String userIdField;

  /// Fallback user ID fields to try if primary field not found
  final List<String> userIdFieldFallbacks;

  /// UI Configuration
  final double scrollThreshold;
  final double inputAreaDefaultHeight;
  final double maxImageWidth;
  final double maxImageHeight;

  /// Message type configuration
  final String messageTypeText;
  final String attachmentTypeImage;
  final String attachmentTypeFile;
  final String attachmentTypeVoice;
  final String attachmentTypeAudio;
  final String attachmentTypeVideo;

  /// Convenience helper returning auth headers for direct HTTP requests to
  /// [baseUrl] (e.g. `NetworkImage`, `CachedNetworkImage`, raw downloads).
  ///
  /// Returns `{'Authorization': 'Bearer <token>'}` when [httpClientApiKey] is
  /// set, otherwise an empty map so it can be spread into headers unconditionally.
  Map<String, String> httpAuthHeaders() {
    final headers = requestHeaders?.call();
    if (headers != null) return headers;
    final token = httpClientApiKey;
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  /// The member's chat id: the host's session, else the app's stored user.
  String? resolveUserId() {
    final fromSession = session?.userId;
    if (fromSession != null) return fromSession;
    final json = storage.getString(userDataKey);
    if (json == null) return null;
    final userData = jsonDecode(json) as Map<String, dynamic>;
    for (final field in [userIdField, ...userIdFieldFallbacks]) {
      final value = userData[field]?.toString();
      if (value != null) return value;
    }
    return null;
  }

  /// Where an uploaded object ([fullPath] from `/chat/resource`) is served.
  /// Fetch it with [httpAuthHeaders].
  String resourceUrl(String? fullPath) => '$baseUrl/chat/resource/$fullPath';

  const ChatConfig({
    required this.baseUrl,
    required this.apiKey,
    this.httpClientApiKey,
    this.channelType = const SupportChannelType(),
    required this.socketBaseUrl,
    this.session,
    this.tokenProvider,
    this.requestHeaders,
    this.membersProvider,
    this.attachmentsEnabled = true,
    required this.theme,
    required this.logger,
    required this.storage,
    this.userDataKey = 'userData',
    this.messageCacheKey = 'messagesCache',
    this.themeKey = 'selectedTheme',
    this.userIdField = 'official_code',
    this.userIdFieldFallbacks = const ['user_id', 'id'],
    this.scrollThreshold = 100,
    this.inputAreaDefaultHeight = 56,
    this.maxImageWidth = 1080,
    this.maxImageHeight = 1080,
    this.messageTypeText = 'text',
    this.attachmentTypeImage = 'image',
    this.attachmentTypeFile = 'file',
    this.attachmentTypeVoice = 'voiceRecording',
    this.attachmentTypeAudio = 'audio',
    this.attachmentTypeVideo = 'video',
  });

  /// Create a copy with modified fields
  ChatConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? httpClientApiKey,
    ChannelType? channelType,
    String? socketBaseUrl,
    ChatSession? session,
    Future<String?> Function()? tokenProvider,
    Map<String, String> Function()? requestHeaders,
    Future<List<ChatMember>> Function()? membersProvider,
    bool? attachmentsEnabled,
    ChatTheme? theme,
    ChatLogger? logger,
    ChatStorageAdapter? storage,
    String? userDataKey,
    String? themeKey,
    String? userIdField,
    List<String>? userIdFieldFallbacks,
  }) {
    return ChatConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      httpClientApiKey: httpClientApiKey ?? this.httpClientApiKey,
      channelType: channelType ?? this.channelType,
      socketBaseUrl: socketBaseUrl ?? this.socketBaseUrl,
      session: session ?? this.session,
      tokenProvider: tokenProvider ?? this.tokenProvider,
      requestHeaders: requestHeaders ?? this.requestHeaders,
      membersProvider: membersProvider ?? this.membersProvider,
      attachmentsEnabled: attachmentsEnabled ?? this.attachmentsEnabled,
      theme: theme ?? this.theme,
      logger: logger ?? this.logger,
      storage: storage ?? this.storage,
      userDataKey: userDataKey ?? this.userDataKey,
      themeKey: themeKey ?? this.themeKey,
      userIdField: userIdField ?? this.userIdField,
      userIdFieldFallbacks: userIdFieldFallbacks ?? this.userIdFieldFallbacks,
    );
  }

  /// Debug-friendly representation.
  ///
  /// Secrets (`apiKey`, `httpClientApiKey`) are redacted to avoid leaking
  /// credentials into logs.
  @override
  String toString() {
    String redact(String? value) {
      if (value == null || value.isEmpty) return 'null';
      if (value.length <= 4) return '****';
      return '****${value.substring(value.length - 4)}';
    }

    return 'ChatConfig('
        'baseUrl: $baseUrl, '
        'apiKey: ${redact(apiKey)}, '
        'httpClientApiKey: ${redact(httpClientApiKey)}, '
        'channelType: ${channelType.runtimeType}, '
        'socketBaseUrl: $socketBaseUrl, '
        'session: ${session?.channelId}, '
        'theme: ${theme.runtimeType}, '
        'logger: ${logger.runtimeType}, '
        'storage: ${storage.runtimeType}, '
        'userDataKey: $userDataKey, '
        'messageCacheKey: $messageCacheKey, '
        'themeKey: $themeKey, '
        'userIdField: $userIdField, '
        'userIdFieldFallbacks: $userIdFieldFallbacks, '
        'scrollThreshold: $scrollThreshold, '
        'inputAreaDefaultHeight: $inputAreaDefaultHeight, '
        'maxImageWidth: $maxImageWidth, '
        'maxImageHeight: $maxImageHeight, '
        'messageTypeText: $messageTypeText, '
        'attachmentTypeImage: $attachmentTypeImage, '
        'attachmentTypeFile: $attachmentTypeFile, '
        'attachmentTypeVoice: $attachmentTypeVoice, '
        'attachmentTypeAudio: $attachmentTypeAudio, '
        'attachmentTypeVideo: $attachmentTypeVideo)';
  }
}
