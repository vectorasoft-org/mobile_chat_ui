import 'package:flutter/material.dart';
import 'volume_meter_widget.dart';
import 'chat_message_input.dart';

class ChatInputContent extends StatefulWidget {
  final bool isRecording;
  final TextEditingController textController;
  final FocusNode focusNode;
  final Stream<double> volumeStream;
  final String timerText;
  final VoidCallback onTextFocusOut;

  const ChatInputContent({
    super.key,
    required this.isRecording,
    required this.textController,
    required this.focusNode,
    required this.volumeStream,
    required this.timerText,
    required this.onTextFocusOut,
  });

  @override
  State<ChatInputContent> createState() => _ChatInputContentState();
}

class _ChatInputContentState extends State<ChatInputContent> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: widget.isRecording
          ? VolumeMeterWidget(
              volumeStream: widget.volumeStream,
              timerText: widget.timerText,
              maxDurationSeconds: 180,
            )
          : ChatMessageInput(
              controller: widget.textController,
              focusNode: widget.focusNode,
              onTapOutside: widget.onTextFocusOut,
            ),
    );
  }
}

class RecordButtonCallbacks {
  final Function(String, int) onRecordingComplete;
  final VoidCallback onRecordingStart;
  final VoidCallback onRecordingCancel;

  RecordButtonCallbacks({
    required this.onRecordingComplete,
    required this.onRecordingStart,
    required this.onRecordingCancel,
  });
}
