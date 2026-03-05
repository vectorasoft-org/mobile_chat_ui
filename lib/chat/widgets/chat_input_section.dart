import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../config/chat_config.dart';
import '../services/chat_service.dart';
import 'chat_input_bar.dart';
import 'chat_input_content.dart';
import '../controllers/recording_controller.dart';

class ChatInputSection extends StatefulWidget {
  final String channelId;
  final ChatConfig chatConfig;
  final ChatService chatService;
  final RecordingController recordingController;
  final VoidCallback onMessageSent;
  final VoidCallback onRecordingStart;
  final VoidCallback onRecordingCancel;
  final Future<bool> Function() hasPermission;
  final Future<bool> Function() requestPermission;
  final Future<void> Function(String filePath, int durationMilliseconds)
  onRecordingComplete;

  const ChatInputSection({
    super.key,
    required this.channelId,
    required this.chatConfig,
    required this.chatService,
    required this.recordingController,
    required this.onMessageSent,
    required this.onRecordingStart,
    required this.onRecordingCancel,
    required this.hasPermission,
    required this.requestPermission,
    required this.onRecordingComplete,
  });

  @override
  State<ChatInputSection> createState() => _ChatInputSectionState();
}

class _ChatInputSectionState extends State<ChatInputSection> {
  late TextEditingController textInputMessageController;
  late FocusNode _textInputFocusNode;
  final ImagePicker _imagePicker = ImagePicker();
  bool _isRecording = false;
  int _recordingDurationSeconds = 0;
  Timer? _recordingTimer;
  Stream<double>? _volumeStream;
  String? _pendingRecordingPath;
  int? _pendingRecordingDurationMs;

  @override
  void initState() {
    super.initState();
    textInputMessageController = TextEditingController();
    _textInputFocusNode = FocusNode();
    _textInputFocusNode.addListener(_onFocusChange);

    // Wire up amplitude stream from recording controller
    _volumeStream = widget.recordingController.amplitudeStream;
  }

  @override
  void dispose() {
    textInputMessageController.dispose();
    _textInputFocusNode.removeListener(_onFocusChange);
    _textInputFocusNode.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _handleRecordingStart() {
    setState(() {
      _isRecording = true;
      _recordingDurationSeconds = 0;
    });

    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      setState(() {
        _recordingDurationSeconds = timer.tick;
      });
    });

    widget.onRecordingStart();
  }

  void _handleRecordingCancel() {
    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordingDurationSeconds = 0;
    });
    widget.onRecordingCancel();
  }

  String _formatRecordingTime(int tenthsOfSeconds) {
    final seconds = tenthsOfSeconds ~/ 10;
    final tenths = tenthsOfSeconds % 10;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    return ChatInputBar(
      isRecording: _isRecording,
      hasPendingRecording: _pendingRecordingPath != null,
      hasFocus: _textInputFocusNode.hasFocus,
      recordingController: widget.recordingController,
      textController: textInputMessageController,
      focusNode: _textInputFocusNode,
      volumeStream: _volumeStream ?? Stream.empty(),
      timerText: _formatRecordingTime(_recordingDurationSeconds),
      onPickFile: () async {
        widget.recordingController.cancel();
        try {
          final result = await FilePicker.platform.pickFiles();
          if (result != null && result.files.isNotEmpty) {
            final file = result.files.first;
            final chatService = widget.chatService;

            // Get optional message text from input
            final messageText = textInputMessageController.text.trim();

            // Fire and forget - don't await
            chatService
                .sendFile(
                  channelId: widget.channelId,
                  file: file.xFile,
                  messageText: messageText.isNotEmpty ? messageText : null,
                )
                .then((_) {
                  // File sent successfully
                  textInputMessageController.clear();
                })
                .catchError((e) {
                  widget.chatConfig.logger.e('Error sending file', error: e);
                });

            // Return to chat immediately
            widget.onMessageSent();
          }
        } catch (e) {
          widget.chatConfig.logger.e('Error picking file', error: e);
        }
      },
      onPickImage: () async {
        widget.recordingController.cancel();
        try {
          final pickedFile = await _imagePicker.pickImage(
            source: ImageSource.gallery,
          );
          if (pickedFile != null) {
            final chatService = widget.chatService;

            // Fire and forget - don't await
            chatService
                .sendImage(
                  channelId: widget.channelId,
                  imageFile: pickedFile,
                  imageWidth: 1080,
                  imageHeight: 1080,
                )
                .then((_) {
                  // Image sent successfully
                })
                .catchError((e) {
                  widget.chatConfig.logger.e('Error sending image', error: e);
                });

            // Return to chat immediately
            widget.onMessageSent();
          }
        } catch (e) {
          widget.chatConfig.logger.e(
            'Error picking image from gallery',
            error: e,
          );
        }
      },
      onTakePhoto: () async {
        widget.recordingController.cancel();
        try {
          final photo = await _imagePicker.pickImage(
            source: ImageSource.camera,
          );
          if (photo != null) {
            final chatService = widget.chatService;

            // Fire and forget - don't await
            chatService
                .sendImage(
                  channelId: widget.channelId,
                  imageFile: photo,
                  imageWidth: 1080,
                  imageHeight: 1080,
                )
                .then((_) {
                  // Photo sent successfully
                })
                .catchError((e) {
                  widget.chatConfig.logger.e('Error sending photo', error: e);
                });

            // Return to chat immediately
            widget.onMessageSent();
          }
        } catch (e) {
          widget.chatConfig.logger.e(
            'Error taking photo with camera',
            error: e,
          );
        }
      },
      onTextFocusOut: () => _textInputFocusNode.unfocus(),
      recordCallbacks: RecordButtonCallbacks(
        onRecordingComplete: (filePath, durationMs) async {
          widget.chatConfig.logger.d(
            'onRecordingComplete: filePath=$filePath, durationMs=$durationMs, sendRequested=${widget.recordingController.sendRequested}',
          );
          _recordingTimer?.cancel();

          // Check if this was triggered by send button press (sendRequested flag)
          // vs automatic completion
          final shouldSendImmediately =
              widget.recordingController.sendRequested;

          if (shouldSendImmediately) {
            // Send button was pressed: send immediately (fire and forget)
            widget.chatConfig.logger.d(
              'Sending voice message via chatService',
            );
            final chatService = widget.chatService;
            // Don't await - let chat service handle the message state independently
            chatService
                .sendVoiceRecording(
                  channelId: widget.channelId,
                  filePath: filePath,
                  durationMilliseconds: durationMs,
                )
                .then((_) {
                  widget.chatConfig.logger.i('Voice message sent successfully');
                })
                .catchError((e) {
                  widget.chatConfig.logger.e(
                    'Error sending audio message',
                    error: e,
                  );
                });

            // Reset button state immediately
            setState(() {
              _isRecording = false;
              _recordingDurationSeconds = 0;
            });
            widget.onMessageSent();
          } else {
            // Recording completed without send button: store for later sending
            setState(() {
              _isRecording = false;
              _recordingDurationSeconds = 0;
              _pendingRecordingPath = filePath;
              _pendingRecordingDurationMs = durationMs;
            });
          }
        },
        onRecordingStart: _handleRecordingStart,
        onRecordingCancel: _handleRecordingCancel,
      ),
      getVolumeStream: () => _volumeStream ?? Stream.empty(),
      hasPermission: widget.hasPermission,
      requestPermission: widget.requestPermission,
      logger: widget.chatConfig.logger,
      onSendMessage: () async {
        // Handle tap mode: request the recording button to stop and send
        if (widget.recordingController.isTapMode) {
          widget.recordingController.onSendButtonPressed();
          return;
        }

        // Check if there's a pending recording to send (hold mode)
        if (_pendingRecordingPath != null &&
            _pendingRecordingDurationMs != null) {
          _recordingTimer?.cancel();
          try {
            final chatService = widget.chatService;
            await chatService.sendVoiceRecording(
              channelId: widget.channelId,
              filePath: _pendingRecordingPath!,
              durationMilliseconds: _pendingRecordingDurationMs!,
            );
            // Clear pending recording and reset state
            setState(() {
              _isRecording = false;
              _recordingDurationSeconds = 0;
              _pendingRecordingPath = null;
              _pendingRecordingDurationMs = null;
            });
          } catch (e) {
            widget.chatConfig.logger.e('Error sending audio message', error: e);
          }
          widget.onMessageSent();
          return;
        }

        final messageText = textInputMessageController.text.trim();
        if (messageText.isNotEmpty) {
          // Get ChatService from Get and send message
          final chatService = widget.chatService;
          chatService.sendMessage(
            channelId: widget.channelId,
            messageText: messageText,
          );
          textInputMessageController.clear();
          widget.onMessageSent();
        }
      },
    );
  }
}
