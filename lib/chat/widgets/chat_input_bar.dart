import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'chat_input_actions.dart';
import 'chat_input_content.dart';
import 'record_button_v2.dart';
import '../controllers/recording_controller.dart';
import '../config/chat_logger.dart';

class ChatInputBar extends StatelessWidget {
  final bool isRecording;
  final bool hasFocus;
  final bool hasPendingRecording;
  final RecordingController recordingController;
  final TextEditingController textController;
  final FocusNode focusNode;
  final Stream<double> volumeStream;
  final String timerText;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickLocation;
  final VoidCallback onTextFocusOut;
  final RecordButtonCallbacks recordCallbacks;
  final Stream<double> Function() getVolumeStream;
  final Future<bool> Function() hasPermission;
  final Future<bool> Function() requestPermission;
  final ChatLogger logger;
  final VoidCallback? onSendMessage;

  const ChatInputBar({
    super.key,
    required this.isRecording,
    this.hasPendingRecording = false,
    required this.hasFocus,
    required this.recordingController,
    required this.textController,
    required this.focusNode,
    required this.volumeStream,
    required this.timerText,
    required this.onPickFile,
    required this.onPickImage,
    required this.onTakePhoto,
    required this.onPickLocation,
    required this.onTextFocusOut,
    required this.recordCallbacks,
    required this.getVolumeStream,
    required this.hasPermission,
    required this.requestPermission,
    required this.logger,
    required this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChatInputActions(
          hasFocus: hasFocus,
          onPickFile: onPickFile,
          onPickImage: onPickImage,
          onTakePhoto: onTakePhoto,
          onPickLocation: onPickLocation,
        ),
        ChatInputImageButton(
          hasFocus: hasFocus,
          onPressed: onPickImage,
        ),
        Visibility(
          visible: !hasFocus,
          maintainSize: false,
          maintainAnimation: true,
          maintainState: true,
          child: RecordButtonV2(
            recordingController: recordingController,
            onRecordingComplete: (filePath, duration) =>
                recordCallbacks.onRecordingComplete(filePath, duration),
            onRecordingStart: recordCallbacks.onRecordingStart,
            onRecordingCancel: recordCallbacks.onRecordingCancel,
            requestPermission: requestPermission,
            hasPermission: hasPermission,
            logger: logger,
          ),
        ),
        ChatInputSpacing(hasFocus: hasFocus),
        ChatInputContent(
          isRecording: isRecording,
          textController: textController,
          focusNode: focusNode,
          volumeStream: volumeStream,
          timerText: timerText,
          onTextFocusOut: onTextFocusOut,
        ),
        SizedBox(width: 4.w),
        ListenableBuilder(
          listenable: recordingController,
          builder: (context, _) => ChatInputSendButton(
            isRecording: isRecording,
            hasPendingRecording: hasPendingRecording,
            isTapping: recordingController.isTapMode,
            isHolding: recordingController.isHoldMode,
            onPressed: onSendMessage,
          ),
        ),
      ],
    );
  }
}
