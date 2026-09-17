import 'package:flutter/material.dart';
import 'config/chat_config.dart';
import 'controllers/recording_controller.dart';
import 'services/audio_cache_service.dart';
import 'handlers/attachment_menu_handler.dart';
import 'handlers/file_download_handler.dart';
import 'resolvers/image_resolver.dart';
import 'widgets/audio_player_controller.dart';

/// Container for chat-related dependencies
/// Replaces GetX service locator pattern with explicit dependency passing
class ChatDependencies {
  final ChatConfig chatConfig;
  final RecordingController recordingController;
  final AudioCacheService audioCacheService;
  final AttachmentMenuHandler? menuHandler;
  final FileDownloadHandler downloadHandler;
  final AttachmentResolver imageResolver;
  final AudioPlayerController audioPlayerController;

  ChatDependencies({
    required this.chatConfig,
    required this.recordingController,
    required this.audioCacheService,
    this.menuHandler,
    required this.downloadHandler,
    required this.imageResolver,
    required this.audioPlayerController,
  });

  /// Dispose all resources
  void dispose() {
    recordingController.dispose();
    audioPlayerController.dispose();
  }
}

/// Factory for creating ChatDependencies
class ChatDependenciesFactory {
  static ChatDependencies create({
    required ChatConfig chatConfig,
    required VoidCallback onVideoPlay,
    required Function(dynamic, dynamic) onFileDownload,
  }) {
    // Create instances directly without GetX
    final recordingController = RecordingController(logger: chatConfig.logger);
    final audioCacheService = AudioCacheService(
      logger: chatConfig.logger,
      config: chatConfig,
    );
    final downloadHandler = FileDownloadHandler(
      logger: chatConfig.logger,
      config: chatConfig,
    );
    final imageResolver = RealImageResolver(chatConfig: chatConfig);
    final audioPlayerController = AudioPlayerController(
      logger: chatConfig.logger,
      config: chatConfig,
    );

    return ChatDependencies(
      chatConfig: chatConfig,
      recordingController: recordingController,
      audioCacheService: audioCacheService,
      menuHandler: null, // Will be created by ChatPage with proper context
      downloadHandler: downloadHandler,
      imageResolver: imageResolver,
      audioPlayerController: audioPlayerController,
    );
  }
}
