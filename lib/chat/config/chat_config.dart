import 'chat_logger.dart';
import '../storage/api/chat_storage_adapter.dart';
import 'chat_theme.dart';

/// Central configuration object for the chat module
/// All dependencies are supplied at instantiation time
/// See HomePage or similar for example initialization
class ChatConfig {
  /// API Configuration
  final String baseUrl;
  final String apiKey;

  final String socketBaseUrl;

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

  const ChatConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.socketBaseUrl,
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
    String? socketBaseUrl,
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
      socketBaseUrl: socketBaseUrl ?? this.socketBaseUrl,
      theme: theme ?? this.theme,
      logger: logger ?? this.logger,
      storage: storage ?? this.storage,
      userDataKey: userDataKey ?? this.userDataKey,
      themeKey: themeKey ?? this.themeKey,
      userIdField: userIdField ?? this.userIdField,
      userIdFieldFallbacks: userIdFieldFallbacks ?? this.userIdFieldFallbacks,
    );
  }
}
