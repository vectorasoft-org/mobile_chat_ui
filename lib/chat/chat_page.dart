import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:loading_overlay/loading_overlay.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'config/chat_config.dart';
import 'config/chat_theme.dart';
import 'config/chat_theme_provider.dart';
import 'message_bubble.dart';
import 'models.dart';
import 'widgets/chat_input_section.dart';
import 'widgets/audio_player_widget.dart';
import 'pages/video_player_page.dart';
import 'pages/chat_channel_info_page.dart';
import 'controllers/recording_controller.dart';
import 'widgets/audio_player_controller.dart';
import 'services/chat_reactive_adapter.dart';
import 'services/chat_service.dart';
import 'services/real_chat_service.dart';
import 'services/audio_cache_service.dart';
import 'handlers/attachment_menu_handler.dart';
import 'handlers/file_download_handler.dart';
import 'resolvers/image_resolver.dart';
import 'services/chat_localizations.dart';
import 'widgets/file_attachment_preview.dart';
import 'widgets/location_map_preview.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.channelId,
    required this.rxdartAdapter,
  });

  final String channelId;
  final ChatReactiveAdapter rxdartAdapter;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatService _chatService = widget.rxdartAdapter.chatService;
  late final ChatConfig _chatConfig;
  late final ChatReactiveAdapter _rxdartAdapter = widget.rxdartAdapter;
  late String _channelName;
  late ChatTheme _currentTheme;

  bool initializing = true;

  @override
  void initState() {
    super.initState();
    // Initialize _chatConfig from the service
    _chatConfig = (_chatService as RealChatService).config;
    _channelName = widget.channelId;
    _currentTheme = _chatService.getSelectedTheme();

    // Load theme after first frame to avoid build errors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedTheme();
    });

    // Load user info once into the service
    _loadAndCacheUserInfo();
    _chatService
        .initialize()
        .then((_) {
          return _chatService
              .joinChannel(widget.channelId)
              .then((_) {
                _chatConfig.logger.i("Joined channel `${widget.channelId}`");
                return _chatService
                    .getChannelName(channelId: widget.channelId)
                    .then((name) {
                      if (name != null && mounted) {
                        setState(() {
                          _channelName = name;
                          _chatService.setChannelName(name);
                        });
                      }
                    })
                    .catchError((e) {
                      _chatConfig.logger.e(
                        'Error fetching channel name',
                        error: e,
                      );
                    });
              })
              .catchError((e) {
                _chatConfig.logger.e(
                  "Error joining channel `${widget.channelId}`",
                  error: e,
                );
              });
        })
        .whenComplete(() {
          setState(() {
            initializing = false;
          });
        });
  }

  @override
  void dispose() {
    _chatService.dispose();
    super.dispose();
  }

  void _loadSavedTheme() {
    try {
      final themeJson = _chatConfig.storage.getString(_chatConfig.themeKey);
      if (themeJson != null && themeJson.isNotEmpty) {
        final themeData = jsonDecode(themeJson) as Map<String, dynamic>;
        final color = themeData['color'] as String?;

        ChatTheme theme;
        switch (color) {
          case 'blue':
            theme = ChatTheme.blue();
            break;
          case 'green':
            theme = ChatTheme.green();
            break;
          case 'red':
          default:
            theme = ChatTheme.houExpress();
        }

        _chatService.setSelectedTheme(theme);
      }
    } catch (e) {
      _chatConfig.logger.e('Error loading saved theme: $e');
    }
  }

  void _loadAndCacheUserInfo() {
    try {
      final userDataJson = _chatConfig.storage.getString(
        _chatConfig.userDataKey,
      );
      if (userDataJson != null) {
        final userData = jsonDecode(userDataJson) as Map<String, dynamic>;

        // Extract user code
        String? code = userData[_chatConfig.userIdField]?.toString();
        if (code == null) {
          for (final fallbackField in _chatConfig.userIdFieldFallbacks) {
            final fallbackValue = userData[fallbackField]?.toString();
            if (fallbackValue != null) {
              code = fallbackValue;
              break;
            }
          }
        }

        // Extract other user data
        final String? fullName = userData['full_name']?.toString();
        final String? avatarUrl = userData['image_url']?.toString();

        // Cache in service
        if (code != null) _chatService.setUserCode(code);
        if (fullName != null) _chatService.setUserName(fullName);
        if (avatarUrl != null) _chatService.setUserAvatarUrl(avatarUrl);
      }
    } catch (e) {
      _chatConfig.logger.e('Error loading user info: $e');
    }
  }

  void _openChannelInfoPage() async {
    final result = await Navigator.of(context).push<ChatTheme>(
      MaterialPageRoute(
        builder: (context) => ChatThemeProvider(
          theme: _currentTheme,
          child: ChatChannelInfoPage(
            channelId: widget.channelId,
            chatService: _chatService,
            chatConfig: _chatConfig,
          ),
        ),
      ),
    );

    // If a theme was returned from the info page, apply it
    if (result != null && mounted) {
      setState(() {
        _currentTheme = result;
      });
    }
  }

  /// Theme selection and cache clearing moved to ChatChannelInfoPage
  /// See: lib/v2/Chat/v2/pages/chat_channel_info_page.dart

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatTheme>(
      stream: _rxdartAdapter.themeStream,
      initialData: _rxdartAdapter.currentTheme,
      builder: (context, themeSnapshot) {
        final primaryColor = themeSnapshot.data?.primaryColor ?? Colors.blue;
        // Create a light tint of the primary color by blending with white
        final backgroundColor =
            Color.lerp(Colors.white, primaryColor, 0.08) ?? Colors.white;

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: AppBar(
              title: Text(
                _channelName,
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: themeSnapshot.data?.primaryColor ?? Colors.blue,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outlined),
                  onPressed: _openChannelInfoPage,
                ),
              ],
            ),
          ),
          body: Builder(
            builder: (context) {
              if (initializing) {
                return Center(child: const CircularProgressIndicator());
              }
              return ChatThemeProvider(
                theme: themeSnapshot.data ?? _chatService.getSelectedTheme(),
                child: ChatView(
                  channelId: widget.channelId,
                  rxdartAdapter: _rxdartAdapter,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.channelId,
    required this.rxdartAdapter,
  });

  final String channelId;
  final ChatReactiveAdapter rxdartAdapter;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late final ChatService _chatService = widget.rxdartAdapter.chatService;
  late final ChatConfig _chatConfig;
  late final ChatReactiveAdapter _rxdartAdapter = widget.rxdartAdapter;
  late AudioPlayerController _audioPlayerController;
  late AudioCacheService _audioCacheService;
  late ScrollController _scrollController;
  late AttachmentResolver _imageResolver;
  late ValueNotifier<bool> _isAtBottomNotifier;
  late ValueNotifier<double> _inputAreaHeightNotifier;
  late ValueNotifier<bool> _isLoadingMoreNotifier;
  final GlobalKey _inputAreaKey = GlobalKey();
  final List<XFile> _selectedImages = [];
  final List<PlatformFile> _selectedFiles = [];
  late Future<List<Message>> _messagesFuture;
  late RecordingController _recordingController;
  bool _hasMoreMessages = true;
  late AttachmentMenuHandler _menuHandler;
  late FileDownloadHandler _downloadHandler;
  late String _currentUserOfficialCode = 'unknown';

  @override
  void initState() {
    super.initState();
    // Initialize late final _chatConfig
    _chatConfig = (widget.rxdartAdapter.chatService as RealChatService).config;
    _chatConfig.logger.i('ChatView initState - channelId: ${widget.channelId}');
    _scrollController = ScrollController();
    _isAtBottomNotifier = ValueNotifier<bool>(true);
    _isLoadingMoreNotifier = ValueNotifier<bool>(false);
    _inputAreaHeightNotifier = ValueNotifier<double>(56);
    _scrollController.addListener(_scrollListener);

    // Instantiate service dependencies directly (no GetX)
    _audioPlayerController = AudioPlayerController(logger: _chatConfig.logger);
    _audioCacheService = AudioCacheService(logger: _chatConfig.logger);
    _imageResolver = RealImageResolver(chatService: _chatService);
    _recordingController = RecordingController(logger: _chatConfig.logger);
    _downloadHandler = FileDownloadHandler(logger: _chatConfig.logger);

    _menuHandler = AttachmentMenuHandler(
      context: context,
      onVideoPlay: (message, attachment, videoUrl) {
        final thumbUrl = attachment['thumb_url'] as String?;
        final fileName = attachment['title'] as String? ?? 'video.mp4';
        _openVideoPlayer(videoUrl, thumbUrl, fileName);
      },
      onFileDownload: (message, attachment) {
        final attachmentType = attachment['type'] as String? ?? 'file';
        _downloadHandler.downloadFileWithSystemFallback(
          message,
          attachment,
          attachmentType,
        );
      },
      onDelete: (message) {
        _deleteMessage(message);
      },
    );

    // Load user official code - will show error dialog if not found
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final loaded = _loadCurrentUserOfficialCode();
      if (!loaded && mounted) {
        _showUserIdentificationErrorDialog();
      }
    });

    // Use injected chat service
    _chatConfig.logger.i('ChatService provided: ${_chatService.runtimeType}');

    _messagesFuture = _chatService.getMessages(channelId: widget.channelId);

    _chatConfig.logger.i('Messages future created, awaiting results...');

    // Measure input area height
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureInputAreaHeight();
    });
  }

  /// Show a snackbar message with optional detail and action button
  void _showSnackbar(String message, [String? detail]) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          detail != null && detail.isNotEmpty ? '$message\n$detail' : message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF323232),
      ),
    );
  }

  /// Request microphone permission for audio recording
  Future<bool> requestMicrophonePermission() async {
    try {
      _chatConfig.logger.i('Requesting microphone permission');
      final status = await Permission.microphone.request();

      if (!mounted) return false;

      if (status.isDenied) {
        _chatConfig.logger.w('Microphone permission denied');
        _showSnackbar(
          ChatLocalizations.micPermissionRequired(context),
          ChatLocalizations.micPermissionRequiredMessage(context),
        );
        return false;
      } else if (status.isPermanentlyDenied) {
        _chatConfig.logger.w('Microphone permission permanently denied');
        _showSnackbar(
          ChatLocalizations.micPermissionDenied(context),
          ChatLocalizations.micPermissionDeniedMessage(context),
        );
        return false;
      } else if (status.isGranted) {
        _chatConfig.logger.i('Microphone permission granted');
        return true;
      } else if (status.isRestricted) {
        _chatConfig.logger.w('Microphone permission restricted');
        _showSnackbar(
          ChatLocalizations.micPermissionRestricted(context),
          ChatLocalizations.micPermissionRestrictedMessage(context),
        );
        return false;
      }
      return false;
    } catch (e) {
      _chatConfig.logger.e('Error requesting microphone permission: $e');
      if (mounted) {
        _showSnackbar(
          ChatLocalizations.micPermissionError(context),
          ChatLocalizations.micPermissionErrorMessage(context),
        );
      }
      return false;
    }
  }

  /// Check if microphone permission is already granted
  Future<bool> hasMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      _chatConfig.logger.d('Microphone permission status: $status');
      return status.isGranted;
    } catch (e) {
      _chatConfig.logger.e('Error checking microphone permission: $e');
      return false;
    }
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;

    final isAtBottom = _scrollController.position.pixels <= 100;
    final isAtTop =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;

    if (isAtBottom != _isAtBottomNotifier.value) {
      _chatConfig.logger.d('Scroll position changed: isAtBottom=$isAtBottom');
      _isAtBottomNotifier.value = isAtBottom;
    }

    // Load more messages when scrolling to top
    if (isAtTop && !_isLoadingMoreNotifier.value && _hasMoreMessages) {
      _chatConfig.logger.d(
        'Reached top of message list, loading more messages',
      );
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMoreNotifier.value) return;

    _isLoadingMoreNotifier.value = true;
    try {
      final messages = _chatService.getMessagesCache();

      if (messages.isEmpty) {
        _chatConfig.logger.d('No messages to paginate from');
        _hasMoreMessages = false;
        return;
      }

      // Get the oldest message from current cache
      final oldestMessage = messages.first;

      _chatConfig.logger.d('Loading messages before: ${oldestMessage.id}');

      // Fetch older messages
      final olderMessages = await _chatService.getMessages(
        channelId: widget.channelId,
        limit: 20,
        getMessageOpt: GetMessageOpt.lt,
        optMessageId: oldestMessage.id,
      );

      if (olderMessages.isEmpty) {
        _chatConfig.logger.d('No older messages available');
        _hasMoreMessages = false;
      } else {
        _chatConfig.logger.d('Loaded ${olderMessages.length} older messages');
      }
    } catch (e) {
      _chatConfig.logger.e('Error loading more messages', error: e);
    } finally {
      _isLoadingMoreNotifier.value = false;
    }
  }

  @override
  void dispose() {
    _chatConfig.logger.d('ChatView dispose');
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _isAtBottomNotifier.dispose();
    _isLoadingMoreNotifier.dispose();
    _inputAreaHeightNotifier.dispose();

    // Clean up manually created services
    _recordingController.dispose();

    super.dispose();
  }

  /// Load the current user's official code from storage
  /// Returns true if successfully loaded, false if not found
  bool _loadCurrentUserOfficialCode() {
    try {
      final userDataJson = _chatConfig.storage.getString(
        _chatConfig.userDataKey,
      );
      if (userDataJson == null) {
        _chatConfig.logger.e('No user data found in storage - critical error');
        return false;
      }

      final userData = jsonDecode(userDataJson) as Map<String, dynamic>;

      // Try primary field first
      String? code = userData[_chatConfig.userIdField]?.toString();

      // If primary field not found, try fallback fields
      if (code == null) {
        for (final fallbackField in _chatConfig.userIdFieldFallbacks) {
          final fallbackValue = userData[fallbackField]?.toString();
          if (fallbackValue != null) {
            code = fallbackValue;
            break;
          }
        }
      }

      // If we still don't have a code, this is a critical error
      if (code == null) {
        _chatConfig.logger.e(
          'Unable to identify user - none of the identification fields found: '
          '${_chatConfig.userIdField}, ${_chatConfig.userIdFieldFallbacks}',
        );
        return false;
      }

      _currentUserOfficialCode = code;
      _chatConfig.logger.i(
        'Loaded current user code: $_currentUserOfficialCode',
      );
      return true;
    } catch (e) {
      _chatConfig.logger.e('Error loading user data', error: e);
      return false;
    }
  }

  /// Show undismissable error dialog when user cannot be identified
  void _showUserIdentificationErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          ChatLocalizations.errorLabel(context),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Unable to identify your account. Please contact support or try logging in again.',
          style: TextStyle(color: Colors.red.shade100),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _chatConfig.logger.w(
                'User pressed Go Back due to identification error',
              );
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: const Text(
              'Go Back',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> sendVoiceRecording(
    String filePath,
    int durationMilliseconds,
  ) async {
    try {
      _chatConfig.logger.i(
        'Sending voice recording: $filePath, duration: $durationMilliseconds ms',
      );
      final chatService = _chatService;

      // Send voice recording via ChatService
      await chatService.sendVoiceRecording(
        channelId: widget.channelId,
        filePath: filePath,
        durationMilliseconds: durationMilliseconds,
      );

      _chatConfig.logger.i('Voice recording sent successfully');
      _scrollToBottom();
    } catch (e) {
      _chatConfig.logger.e('Error sending voice recording: $e');
      _showSnackbar('Error', 'Failed to send voice recording');
    }
  }

  void _handleRecordingStart() {
    _chatConfig.logger.i('Recording started');
  }

  void _handleRecordingCancel() {
    _chatConfig.logger.i('Recording cancelled');
  }

  void _measureInputAreaHeight() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inputBox =
          _inputAreaKey.currentContext?.findRenderObject() as RenderBox?;
      if (inputBox != null && inputBox.hasSize) {
        _inputAreaHeightNotifier.value = inputBox.size.height;
      }
    });
  }

  void _removeImage(int index) {
    _chatConfig.logger.d('Removing image at index: $index');
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeFile(int index) {
    _chatConfig.logger.d('Removing file at index: $index');
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        _isAtBottomNotifier.value = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: _buildMessagesList()),
            _buildInputDivider(theme),
            _buildInputArea(),
            _buildMinPadding(theme),
          ],
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _isAtBottomNotifier,
          builder: (context, isAtBottom, child) {
            return ValueListenableBuilder<double>(
              valueListenable: _inputAreaHeightNotifier,
              builder: (context, inputHeight, _) {
                return Positioned(
                  right: 16,
                  bottom: inputHeight + 16,
                  child: AnimatedOpacity(
                    opacity: isAtBottom ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    child: AnimatedSlide(
                      offset: isAtBottom ? const Offset(0, 2) : Offset.zero,
                      duration: const Duration(milliseconds: 300),
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: theme.primaryColor,
                        onPressed: _scrollToBottom,
                        child: const Icon(
                          Icons.arrow_downward,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    return FutureBuilder<List<Message>>(
      future: _messagesFuture,
      builder: (context, snapshot) {
        // _chatConfig.logger.d(
        //   'FutureBuilder state: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, hasData=${snapshot.hasData}',
        // );

        if (snapshot.connectionState == ConnectionState.waiting) {
          _chatConfig.logger.i('FutureBuilder: waiting for messages...');
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          _chatConfig.logger.e('FutureBuilder error: ${snapshot.error}');
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        _chatConfig.logger.i(
          'FutureBuilder: completed with ${snapshot.data?.length ?? 0} messages',
        );

        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              // Unfocus text field when tapping on message area
              FocusScope.of(context).unfocus();
            },
            child: ValueListenableBuilder<bool>(
              valueListenable: _isLoadingMoreNotifier,
              builder: (context, isLoadingMore, _) {
                return StreamBuilder<List<Message>>(
                  stream: _rxdartAdapter.messagesStream,
                  initialData: _rxdartAdapter.currentMessages,
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? [];
                    // Trigger rebuild only when message count changes
                    final itemCount = messages.length + (isLoadingMore ? 1 : 0);

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      itemCount: itemCount,
                      // Use unique keys so Flutter doesn't rebuild cached items
                      itemBuilder: (context, index) {
                        // With reverse: true and loading indicator, the loading indicator
                        // appears at the top (highest visual position, last in reverse order)
                        if (isLoadingMore && index == messages.length) {
                          return Container(
                            key: const ValueKey('loading_indicator'),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }

                        // With reverse: true, index 0 is the newest message at bottom
                        // So we access from the end: messages[messages.length - 1 - index]
                        final message = messages[messages.length - 1 - index];
                        final isSelf =
                            message.sender == _currentUserOfficialCode;

                        // Show sender name if current sender is different from the NEXT message (newer, below in reverse display)
                        final nextMessage = index > 0
                            ? messages[messages.length - index]
                            : null;
                        final showSenderName =
                            nextMessage == null ||
                            nextMessage.sender != message.sender;

                        return Column(
                          key: ValueKey('${message.id}_col'),
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RepaintBoundary(
                              key: ValueKey(message.id),
                              child: MessageBubble(
                                message: message,
                                isSelf: isSelf,
                                showSenderName: showSenderName,
                                onAttachmentTap: (attachment, fileName) =>
                                    _downloadAndOpenFile(
                                      message,
                                      attachment,
                                      fileName,
                                    ),
                                buildAttachmentWidget: _buildAttachmentWidget,
                                onAttachmentLongPress: _showAttachmentMenu,
                                onMessageLongPress: _showMessageActions,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputDivider(ChatTheme theme) {
    return Divider(
      height: 1,
      thickness: 1,
      color: theme.getThemeAwareDividerColor(),
    );
  }

  Widget _buildAttachmentWidget(
    Map<String, dynamic> attachment,
    bool isSelf,
    Message message,
  ) {
    // _chatConfig.logger.d('Building attachment widget - type: ${attachment['type']}');
    // _chatConfig.logger.d("Attachment data: $attachment");
    switch (attachment['type']) {
      case 'image':
        // _chatConfig.logger.d('Rendering image attachment');
        final fileName = attachment['fallback'] ?? 'image';
        return AnimatedOpacity(
          opacity: message.isSending ? 0.5 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onLongPress: () =>
                _showAttachmentMenu(message, attachment, fileName),
            child: _imageResolver.buildWidget(attachment, message),
          ),
        );
      case 'file':
        // _chatConfig.logger.d('Rendering file attachment');
        return _buildFileAttachmentWidget(attachment, isSelf, message);
      case 'voiceRecording':
        // _chatConfig.logger.d('Rendering voice recording attachment');
        return _buildVoiceRecordingWidget(attachment, isSelf, message);
      case 'audio':
        // _chatConfig.logger.d('Rendering audio file attachment');
        return _buildAudioFileWidget(attachment, isSelf, message);
      case 'video':
        // _chatConfig.logger.d('Rendering video attachment');
        return _buildVideoAttachmentWidget(attachment, isSelf, message);
      case 'location':
        // _chatConfig.logger.d('Rendering location attachment');
        return _buildLocationAttachmentWidget(attachment, isSelf, message);
      default:
        // _chatConfig.logger.d('Rendering unsupported attachment type: ${attachment['type']}');
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              attachment['fallback'] ?? '[Unsupported Attachment]',
              style: TextStyle(fontSize: 12.sp),
            ),
          ),
        );
    }
  }

  Widget _buildFileAttachmentWidget(
    Map<String, dynamic> attachment,
    bool isSelf,
    Message message,
  ) {
    final mimeType =
        attachment['mime_type'] as String? ?? 'application/octet-stream';
    final fileName = attachment['title'] as String? ?? 'File';
    final fileSize = attachment['file_size'] as int? ?? 0;

    // _chatConfig.logger.d(
    //   'File attachment - name: $fileName, size: ${_formatFileSize(fileSize)}, mime: $mimeType',
    // );

    // Check if it's an image MIME type
    final isImageType = _isImageMimeType(mimeType);
    // _chatConfig.logger.d('Is image type: $isImageType');

    if (isImageType) {
      // _chatConfig.logger.d('Rendering as image file preview using resolver');
      // For image files, ensure image_url is set for the resolver
      if (attachment.containsKey('asset_url')) {
        return _buildImageFilePreview(
          attachment,
          fileName,
          fileSize,
          isSelf,
          message,
        );
      }
    }

    // _chatConfig.logger.d('Rendering as generic file preview');
    return _buildGenericFilePreview(
      attachment,
      fileName,
      fileSize,
      isSelf,
      message,
    );
  }

  bool _isImageMimeType(String mimeType) {
    final imageMimes = [
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/bmp',
      'image/tiff',
      'image/svg+xml',
    ];
    final result = imageMimes.any(
      (mime) => mimeType.toLowerCase().startsWith(mime),
    );
    // _chatConfig.logger.d('MIME type check - $mimeType is image: $result');
    return result;
  }

  Widget _buildImageFilePreview(
    Map<String, dynamic> attachment,
    String fileName,
    int fileSize,
    bool isSelf,
    Message message,
  ) {
    return FileAttachmentPreview(
      attachment: attachment,
      isSelf: isSelf,
      message: message,
      logger: _chatConfig.logger,
      previewBuilder: (att) => ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: _imageResolver.buildSmallPreview(att),
      ),
      onTap: () => _downloadAndOpenFile(message, attachment, fileName),
      onLongPress: () => _showAttachmentMenu(message, attachment, fileName),
    );
  }

  Widget _buildGenericFilePreview(
    Map<String, dynamic> attachment,
    String fileName,
    int fileSize,
    bool isSelf,
    Message message,
  ) {
    final mimeType =
        attachment['mime_type'] as String? ?? 'application/octet-stream';
    return FileAttachmentPreview(
      attachment: attachment,
      isSelf: isSelf,
      message: message,
      logger: _chatConfig.logger,
      previewBuilder: (att) => _buildFileIcon(mimeType, isForPreview: true),
      onTap: () => _downloadAndOpenFile(message, attachment, fileName),
      onLongPress: () => _showAttachmentMenu(message, attachment, fileName),
    );
  }

  /// Build icon for file attachments based on MIME type
  /// Colors are bold/saturated to contrast with pale backgrounds
  Icon _buildFileIcon(String mimeType, {bool isForPreview = false}) {
    final lowerType = mimeType.toLowerCase();
    const size = 20.0;

    if (lowerType.startsWith('image/')) {
      return Icon(Icons.image, size: size, color: Colors.blue);
    }
    if (lowerType.startsWith('audio/')) {
      return Icon(Icons.audio_file, size: size, color: Colors.orange);
    }
    if (lowerType.startsWith('video/')) {
      return Icon(Icons.video_file, size: size, color: Colors.purple);
    }
    if (lowerType.startsWith('application/pdf')) {
      return Icon(Icons.picture_as_pdf, size: size, color: Colors.red);
    }
    if (lowerType.contains('word') || lowerType.contains('document')) {
      return Icon(Icons.description, size: size, color: Colors.blue);
    }
    if (lowerType.contains('sheet') || lowerType.contains('excel')) {
      return Icon(Icons.table_chart, size: size, color: Colors.green);
    }
    if (lowerType.contains('presentation') ||
        lowerType.contains('powerpoint')) {
      return Icon(Icons.slideshow, size: size, color: Colors.red);
    }
    if (lowerType.contains('zip') ||
        lowerType.contains('rar') ||
        lowerType.contains('compress')) {
      return Icon(Icons.folder_zip, size: size, color: Colors.amber);
    }

    return Icon(Icons.insert_drive_file, size: size, color: Colors.indigo);
  }

  Widget _buildVoiceRecordingWidget(
    Map<String, dynamic> attachment,
    bool isSelf,
    Message message,
  ) {
    // Prefer granular millisecond duration if present, otherwise fall back to
    // the seconds-based duration field (kept for backward compatibility).
    final durationMillis =
        (attachment['custom'] as Map?)?['duration_millis'] as int? ??
        attachment['duration_millis'] as int?;
    final durationSeconds =
        (attachment['custom'] as Map?)?['duration'] as int? ??
        attachment['duration'] as int?;
    final durationMs =
        durationMillis ??
        (durationSeconds != null ? durationSeconds * 1000 : null);
    final assetUrl = attachment['asset_url'] as String?;

    // Check for malformed voice recording (missing URL or duration)
    if (assetUrl == null || durationMs == null) {
      _chatConfig.logger.w(
        'Malformed voice recording - assetUrl: ${assetUrl != null}, durationMs: ${durationMs != null}',
      );
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red[100],
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.red[300]!, width: 1),
          ),
          child: Text(
            '[Malformed Attachment]',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.red[700],
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _showAttachmentMenu(
        message,
        attachment,
        'audio_${DateTime.now().millisecondsSinceEpoch}.ogg',
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: RepaintBoundary(
          child: AnimatedOpacity(
            opacity: message.isSending ? 0.5 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: AudioPlayerWidget(
              messageId: message.id,
              audioUrl: assetUrl,
              durationMilliseconds: durationMs,
              isSelf: isSelf,
              controller: _audioPlayerController,
              cacheService: _audioCacheService,
              logger: _chatConfig.logger,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioFileWidget(
    Map<String, dynamic> attachment,
    bool isSelf,
    Message message,
  ) {
    final fileName = attachment['title'] as String? ?? 'audio.ogg';
    final fileSize = attachment['file_size'] as int? ?? 0;
    final assetUrl = attachment['asset_url'] as String?;

    _chatConfig.logger.d(
      'Audio file attachment - name: $fileName, size: ${_formatFileSize(fileSize)}',
    );

    if (assetUrl == null) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _chatConfig.theme.getThemeAwareGrey(300),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Text(
            'Audio file (invalid)',
            style: TextStyle(fontSize: 12.sp, color: Colors.black54),
          ),
        ),
      );
    }

    final fileSizeStr = _formatFileSize(fileSize);

    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: message.isSending ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: GestureDetector(
            onTap: () =>
                _downloadFileWithSystemFallback(message, attachment, 'audio'),
            onLongPress: () =>
                _showAttachmentMenu(message, attachment, fileName),
            child: Container(
              decoration: BoxDecoration(
                color: isSelf
                    ? _chatConfig.theme.primaryColor
                    : (message.isSending
                          ? _chatConfig.theme.getThemeAwareGrey(300)
                          : _chatConfig.theme.getThemeAwareWhite()),
                borderRadius: BorderRadius.circular(8.r),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: Colors.amber[300],
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.audio_file,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fileName,
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            overflow: TextOverflow.ellipsis,
                            color: isSelf ? Colors.white : Colors.black,
                          ),
                          maxLines: 1,
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          fileSizeStr,
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: isSelf ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoAttachmentWidget(
    Map<String, dynamic> attachment,
    bool isSelf,
    Message message,
  ) {
    final thumbUrl = attachment['thumb_url'] as String?;
    final assetUrl = attachment['asset_url'] as String?;
    final fileName = attachment['title'] as String? ?? 'video.mp4';

    if (thumbUrl == null && assetUrl == null) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Text(
            'Video (invalid)',
            style: TextStyle(fontSize: 12.sp, color: Colors.black54),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: assetUrl != null
            ? () => _openVideoPlayer(assetUrl, thumbUrl, fileName)
            : null,
        onLongPress: () => _showAttachmentMenu(message, attachment, fileName),
        child: AnimatedOpacity(
          opacity: message.isSending ? 0.5 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Video thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: SizedBox(
                  width: 350.w,
                  child: _isDataUri(thumbUrl ?? '')
                      ? Image.memory(
                          _decodeDataUri(thumbUrl!),
                          width: 350.w,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 250,
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image),
                            );
                          },
                        )
                      : CachedNetworkImage(
                          imageUrl: thumbUrl ?? '',
                          fit: BoxFit.contain,
                          errorWidget: (context, url, error) {
                            return Container(
                              height: 250,
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image),
                            );
                          },
                        ),
                ),
              ),
              // Play button overlay
              Container(
                width: 60.w,
                height: 60.w,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow, size: 36.sp, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isDataUri(String url) => url.startsWith('data:');

  Uint8List _decodeDataUri(String dataUri) {
    final commaIndex = dataUri.indexOf(',');
    if (commaIndex == -1) return Uint8List(0);
    final base64Part = dataUri.substring(commaIndex + 1);
    try {
      return base64Decode(base64Part);
    } catch (_) {
      return Uint8List(0);
    }
  }

  /// Build a location attachment widget showing the coordinates and a link to
  /// open the location in a maps application.
  Widget _buildLocationAttachmentWidget(
    Map<String, dynamic> attachment,
    bool isSelf,
    Message message,
  ) {
    final latitude = attachment['latitude'] as num?;
    final longitude = attachment['longitude'] as num?;
    final title = attachment['title'] as String? ?? 'Location';
    final thumbUrl = attachment['thumb_url'] as String? ?? '';

    if (latitude == null || longitude == null) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Text(
            'Location (invalid)',
            style: TextStyle(fontSize: 12.sp, color: Colors.black54),
          ),
        ),
      );
    }

    final lat = latitude.toDouble();
    final lng = longitude.toDouble();
    final coords = '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

    // Use the currently selected theme (not the static config theme) so the
    // bubble respects theme changes.
    final theme = ChatThemeProvider.of(context);

    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: message.isSending ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        // No outer padding: the location bubble has no message text, and the
        // MessageBubble already provides the themed, rounded background.
        child: GestureDetector(
          onTap: () => _openLocationInMaps(lat, lng),
          onLongPress: () => _showAttachmentMenu(message, attachment, title),
          child: Container(
            width: 260.w,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Static map preview (non-movable); fills the container
                // width and derives its height from the 16:9 aspect ratio.
                LocationMapPreview(
                  latitude: lat,
                  longitude: lng,
                  thumbnailUrl: thumbUrl,
                  onTap: () => _openLocationInMaps(lat, lng),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          overflow: TextOverflow.ellipsis,
                          color: isSelf
                              ? theme.messageSentText
                              : theme.messageReceivedText,
                        ),
                        maxLines: 1,
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        coords,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: isSelf
                              ? theme.messageSentText.withValues(alpha: 0.7)
                              : theme.messageReceivedText.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Open the given coordinates in the platform's maps application.
  Future<void> _openLocationInMaps(double latitude, double longitude) async {
    try {
      final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      );
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _chatConfig.logger.e('Failed to open maps URL: $uri');
        if (mounted) {
          _showSnackbar('Error', 'Failed to open maps');
        }
      }
    } catch (e) {
      _chatConfig.logger.e('Error opening maps: $e');
      if (mounted) {
        _showSnackbar('Error', 'Failed to open maps: $e');
      }
    }
  }

  /// Open video player with custom VideoPlayerWidget
  Future<void> _openVideoPlayer(
    String videoUrl,
    String? thumbnailUrl,
    String title,
  ) async {
    try {
      _chatConfig.logger.i('Opening video player for: $videoUrl');

      if (!mounted) return;

      final theme = ChatThemeProvider.of(context);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatThemeProvider(
            theme: theme,
            child: RepaintBoundary(
              child: VideoPlayerPage(
                videoUrl: videoUrl,
                thumbnailUrl: thumbnailUrl,
                title: title,
                logger: _chatConfig.logger,
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      _chatConfig.logger.e('Error opening video player: $e');
      if (mounted) {
        _showSnackbar('Error', 'Failed to open video player');
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB'];
    final i = (log(bytes) / log(1024)).floor();
    final size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(1)} ${sizes[i]}';
  }

  /// Extract file extension from MIME type
  String _getExtensionFromMimeType(String? mimeType) {
    if (mimeType == null) return 'bin';

    final mimeTypeMap = {
      // Images
      'image/jpeg': 'jpg',
      'image/jpg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
      'image/bmp': 'bmp',
      'image/tiff': 'tiff',
      'image/svg+xml': 'svg',
      // Videos
      'video/mp4': 'mp4',
      'video/mpeg': 'mpeg',
      'video/quicktime': 'mov',
      'video/x-msvideo': 'avi',
      'video/x-matroska': 'mkv',
      'video/webm': 'webm',
      // Audio
      'audio/mpeg': 'mp3',
      'audio/mp4': 'm4a',
      'audio/ogg': 'ogg',
      'audio/wav': 'wav',
      'audio/aac': 'aac',
      'audio/flac': 'flac',
      // Documents
      'application/pdf': 'pdf',
      'application/msword': 'doc',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
          'docx',
      'application/vnd.ms-excel': 'xls',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
          'xlsx',
      'application/vnd.ms-powerpoint': 'ppt',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation':
          'pptx',
      'text/plain': 'txt',
      'text/csv': 'csv',
      'application/json': 'json',
      'application/zip': 'zip',
      'application/x-rar-compressed': 'rar',
    };

    return mimeTypeMap[mimeType] ?? 'bin';
  }

  /// Handle OpenFile.open() result and show appropriate error message
  Future<void> _openFileAndHandleErrors(
    String filePath,
    String fileType,
  ) async {
    try {
      final result = await OpenFile.open(filePath);
      _chatConfig.logger.i('$fileType open result: ${result.message}');

      // Check if file was opened successfully
      if (result.type.toString() != 'ResultType.done') {
        // Handle different error types
        String errorMessage;
        final resultType = result.type.toString();

        if (resultType.contains('noAppToOpen')) {
          errorMessage = 'No app found to open this file type';
        } else if (resultType.contains('permissionDenied')) {
          errorMessage = 'Permission denied - cannot open file';
        } else if (resultType.contains('fileNotFound')) {
          errorMessage = 'File not found';
        } else {
          errorMessage = result.message.isNotEmpty
              ? result.message
              : 'Failed to open file';
        }

        _chatConfig.logger.e(
          'Error opening $fileType: $resultType - ${result.message}',
        );
        _showSnackbar('Cannot Open File', errorMessage);
      }
    } catch (e) {
      _chatConfig.logger.e('Exception opening $fileType: $e');
      _showSnackbar('Error', 'Failed to open file: $e');
    }
  }

  /// Download and open image attachment
  Future<void> _downloadImage(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) async {
    try {
      _chatConfig.logger.d('Downloading image: $fileName');
      final chatService = _chatService;
      final imageUrl =
          (attachment['image_url'] ?? attachment['asset_url']) as String?;
      final mimeType = attachment['mime_type'] as String?;

      if (imageUrl == null) {
        _chatConfig.logger.e('No image URL in attachment');
        _showSnackbar('Error', 'No image data available');
        return;
      }

      final extension = _getExtensionFromMimeType(mimeType);
      final filePath = await chatService.downloadFile(
        message: message,
        imageUrl: imageUrl,
        fileExtension: extension,
      );

      if (filePath == null || filePath.isEmpty) {
        _chatConfig.logger.e('Failed to download image');
        _showSnackbar('Error', 'Failed to download image');
        return;
      }

      await _openFileAndHandleErrors(filePath, 'Image');
    } catch (e) {
      _chatConfig.logger.e('Error downloading image: $e');
      _showSnackbar('Error', 'Failed to download image: $e');
    }
  }

  /// Download and open video attachment
  Future<void> _downloadVideo(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) async {
    try {
      _chatConfig.logger.d('Downloading video: $fileName');
      final chatService = _chatService;
      final videoUrl = attachment['asset_url'] as String?;
      final mimeType = attachment['mime_type'] as String?;

      if (videoUrl == null) {
        _chatConfig.logger.e('No video URL in attachment');
        _showSnackbar('Error', 'No video data available');
        return;
      }

      final extension = _getExtensionFromMimeType(mimeType);
      final filePath = await chatService.downloadFile(
        message: message,
        imageUrl: videoUrl,
        fileExtension: extension,
      );

      if (filePath == null || filePath.isEmpty) {
        _chatConfig.logger.e('Failed to download video');
        _showSnackbar('Error', 'Failed to download video');
        return;
      }

      await _openFileAndHandleErrors(filePath, 'Video');
    } catch (e) {
      _chatConfig.logger.e('Error downloading video: $e');
      _showSnackbar('Error', 'Failed to download video: $e');
    }
  }

  /// Download and open voice recording attachment
  Future<void> _downloadVoiceRecording(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) async {
    try {
      _chatConfig.logger.d('Downloading voice recording: $fileName');
      final chatService = _chatService;
      final audioUrl = attachment['asset_url'] as String?;
      final mimeType = attachment['mime_type'] as String?;

      if (audioUrl == null) {
        _chatConfig.logger.e('No audio URL in attachment');
        _showSnackbar('Error', 'No audio data available');
        return;
      }

      final extension = _getExtensionFromMimeType(mimeType);
      final filePath = await chatService.downloadFile(
        message: message,
        imageUrl: audioUrl,
        fileExtension: extension,
      );

      if (filePath == null || filePath.isEmpty) {
        _chatConfig.logger.e('Failed to download voice recording');
        _showSnackbar('Error', 'Failed to download voice recording');
        return;
      }

      await _openFileAndHandleErrors(filePath, 'Voice Recording');
    } catch (e) {
      _chatConfig.logger.e('Error downloading voice recording: $e');
      _showSnackbar('Error', 'Failed to download voice recording: $e');
    }
  }

  /// Download and open generic file attachment (preserves original filename)
  /// Download and open generic file attachment (preserves original filename)
  Future<void> _downloadGenericFile(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) async {
    try {
      _chatConfig.logger.d('Downloading generic file: $fileName');
      final assetUrl = attachment['asset_url'] as String?;

      if (assetUrl == null) {
        _chatConfig.logger.e('No asset URL in attachment');
        _showSnackbar('Error', 'No file data available');
        return;
      }

      // Sanitize the original filename - preserve it for user experience
      final sanitizedFileName = fileName.replaceAll(
        RegExp(r'[<>:"/\\|?*]'),
        '_',
      );
      _chatConfig.logger.d(
        'Original filename: $fileName, sanitized: $sanitizedFileName',
      );

      // Get downloads directory
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        _chatConfig.logger.e('Downloads directory not available');
        _showSnackbar(
          'Error',
          'Downloads directory not available on this platform',
        );
        return;
      }

      final filePath = '${downloadsDir.path}/$sanitizedFileName';
      final file = File(filePath);

      // Check if file already exists - skip download if cached
      if (await file.exists()) {
        _chatConfig.logger.i('File already exists in downloads: $filePath');
        await _openFileAndHandleErrors(filePath, 'File');
        return;
      }

      // Extract file bytes from various source formats
      Uint8List? fileBytes;

      // Handle base64 data URI (e.g., data:application/octet-stream;base64,ABC...)
      if (assetUrl.startsWith('data:') && assetUrl.contains(';base64,')) {
        _chatConfig.logger.d('Processing base64 data URI for generic file');
        final parts = assetUrl.split(';base64,');
        if (parts.length == 2) {
          final base64Data = parts[1];
          final padded = _addBase64Padding(base64Data);
          fileBytes = base64Decode(padded);
        }
      }
      // Handle HTTP/HTTPS URL
      else if (assetUrl.startsWith('http://') ||
          assetUrl.startsWith('https://')) {
        _chatConfig.logger.d(
          'Downloading generic file from HTTP URL: $assetUrl',
        );
        try {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(assetUrl));
          final response = await request.close();
          if (response.statusCode == 200) {
            fileBytes ??= Uint8List.fromList(
              await response.expand((e) => e).toList(),
            );
          } else {
            _chatConfig.logger.e(
              'Failed to download file: HTTP ${response.statusCode}',
            );
          }
          httpClient.close();
        } catch (e) {
          _chatConfig.logger.e('Error downloading from HTTP URL: $e');
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        _chatConfig.logger.e('Failed to extract file bytes from attachment');
        _showSnackbar('Error', 'Failed to process file data');
        return;
      }

      // Write file to downloads directory
      await file.writeAsBytes(fileBytes);
      _chatConfig.logger.i('File downloaded and saved to: $filePath');

      await _openFileAndHandleErrors(filePath, 'File');
    } catch (e) {
      _chatConfig.logger.e('Error downloading file: $e');
      _showSnackbar('Error', 'Failed to download file: $e');
    }
  }

  /// Add padding to base64 string if needed for proper decoding
  String _addBase64Padding(String base64String) {
    final padLength = base64String.length % 4;
    if (padLength != 0) {
      return base64String + ('=' * (4 - padLength));
    }
    return base64String;
  }

  Future<void> _downloadAndOpenFile(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) async {
    final attachmentType = attachment['type'] as String? ?? 'file';
    switch (attachmentType) {
      case 'image':
        return _downloadImage(message, attachment, fileName);
      case 'video':
        return _downloadVideo(message, attachment, fileName);
      case 'voiceRecording':
        return _downloadVoiceRecording(message, attachment, fileName);
      default:
        return _downloadGenericFile(message, attachment, fileName);
    }
  }

  Future<void> _downloadFileWithSystemFallback(
    Message message,
    Map<String, dynamic> attachment,
    String attachmentType,
  ) {
    return _downloadHandler.downloadFileWithSystemFallback(
      message,
      attachment,
      attachmentType,
    );
  }

  /// Show a bottom modal with actions for a message (e.g. delete)
  void _showMessageActions(Message message) {
    if (message.isSending) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(16.r),
        ),
      ),
      builder: (context) {
        final hasText = message.text != null && message.text!.isNotEmpty;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasText)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(
                    ChatLocalizations.copyMessage(context),
                    style: TextStyle(fontSize: 16.sp),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _copyMessageText(message.text!);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(
                  ChatLocalizations.deleteMessage(context),
                  style: TextStyle(fontSize: 16.sp),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyMessageText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        _showSnackbar(
          ChatLocalizations.copyMessageSuccess(context),
          ChatLocalizations.copyMessageSuccessMessage(context),
        );
      }
    } catch (e) {
      _chatConfig.logger.e('Error copying message text: $e');
      if (mounted) {
        _showSnackbar(
          ChatLocalizations.copyMessageError(context),
          ChatLocalizations.copyMessageErrorMessage(context),
        );
      }
    }
  }

  Future<void> _deleteMessage(Message message) async {
    try {
      _chatConfig.logger.i('Deleting message: ${message.id}');
      await _chatService.deleteMessage(
        channelId: widget.channelId,
        messageId: message.id,
      );
      _chatConfig.logger.i('Message deleted: ${message.id}');
    } catch (e) {
      _chatConfig.logger.e('Error deleting message', error: e);
      if (mounted) {
        _showSnackbar(
          ChatLocalizations.deleteMessageError(context),
          e.toString(),
        );
      }
    }
  }

  void _showAttachmentMenu(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) {
    final attachmentType = attachment['type'] as String? ?? '';

    switch (attachmentType) {
      case 'image':
        _menuHandler.showImageAttachmentMenu(message, attachment, fileName);
        break;
      case 'video':
        _menuHandler.showVideoAttachmentMenu(message, attachment, fileName);
        break;
      case 'voiceRecording':
        _menuHandler.showVoiceRecordingMenu(message, attachment, fileName);
        break;
      case 'audio':
        _menuHandler.showAudioFileMenu(message, attachment, fileName);
        break;
      default:
        _menuHandler.showGenericFileMenu(message, attachment, fileName);
    }
  }

  Widget _buildInputArea() {
    return Container(
      key: _inputAreaKey,
      color: Colors.grey[50],
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected images preview
          if (_selectedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(
                    _selectedImages.length,
                    (index) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: Image.file(
                              File(_selectedImages[index].path),
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: -8,
                            right: -8,
                            child: IconButton(
                              icon: Icon(
                                Icons.close,
                                color: _chatConfig.theme.primaryColor,
                              ),
                              iconSize: 20,
                              padding: EdgeInsets.zero,
                              onPressed: () => _removeImage(index),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // File preview strip
          if (_selectedFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
              child: SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedFiles.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8.r),
                          child: Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey[300],
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.insert_drive_file, size: 20),
                                Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Text(
                                      _selectedFiles[index].name
                                          .split('.')
                                          .last
                                          .toUpperCase(),
                                      style: TextStyle(fontSize: 8.sp),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -8,
                          child: IconButton(
                            icon: Icon(
                              Icons.close,
                              color: _chatConfig.theme.primaryColor,
                            ),
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            onPressed: () => _removeFile(index),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Text input and buttons - isolated widget with its own state
          ChatInputSection(
            channelId: widget.channelId,
            chatConfig: _chatConfig,
            chatService: _chatService,
            recordingController: _recordingController,
            hasPermission: hasMicrophonePermission,
            requestPermission: requestMicrophonePermission,
            onRecordingStart: _handleRecordingStart,
            onRecordingCancel: _handleRecordingCancel,
            onRecordingComplete: sendVoiceRecording,
            onMessageSent: _scrollToBottom,
          ),
        ],
      ),
    );
  }

  Widget _buildMinPadding(ChatTheme theme) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: bottomPadding,
      // color should be the same color as the input bar
      color: Colors.grey[50],
    );
  }
}

// Note: MockChatService, image resolvers, and related classes have been
// extracted to separate files for better maintainability.
//
// New files:
// - resolvers/image_resolver.dart - RealImageResolver and ImageDimensions
// - resolvers/mock_image_resolver.dart - MockImageResolver
// - services/mock_chat_service.dart - MockChatService

// Note: Legacy preview helpers were removed from the chat module.
