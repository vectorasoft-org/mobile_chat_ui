import 'package:flutter/material.dart';
import 'audio_player_widget.dart';

/// Widget for rendering voice recording attachments in message bubbles
class VoiceAttachmentWidget extends StatelessWidget {
  final String messageId;
  final Map<String, dynamic> attachment;
  final bool isSelf;

  const VoiceAttachmentWidget({
    super.key,
    required this.messageId,
    required this.attachment,
    this.isSelf = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = attachment['asset_url'] as String?;
    // Duration from API is in seconds under custom.duration, convert to milliseconds
    final durationSeconds =
        (attachment['custom'] as Map?)?['duration'] as int? ??
        attachment['duration'] as int?;
    final durationMs = durationSeconds != null ? durationSeconds * 1000 : 0;

    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }

    return AudioPlayerWidget(
      messageId: messageId,
      audioUrl: url,
      durationMilliseconds: durationMs,
      isSelf: isSelf,
    );
  }
}
