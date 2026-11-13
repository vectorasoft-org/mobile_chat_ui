import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'config/chat_theme_provider.dart';
import 'models.dart';
import 'widgets/media_gallery_widget.dart';
import 'widgets/file_list_widget.dart';

enum _AttachmentCategory { single, multipleMedia, multipleFiles }

/// Who a received message is from, as the room shows it: their name, the
/// colour it and their avatar take, and their role when the room has one.
class MessageSender {
  final String name;
  final Color color;
  final String? role;

  const MessageSender({required this.name, required this.color, this.role});
}

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isSelf;

  /// The first message of a run from one sender: it carries the avatar and
  /// the name, and the run's later messages stack under it.
  final bool startsRun;

  /// Null on the reader's own messages - the right-hand side already says
  /// whose they are.
  final MessageSender? sender;

  /// An own message another member has read: two ticks instead of one.
  final bool seen;
  final Future<void> Function(Map<String, dynamic>, String) onAttachmentTap;
  final Widget Function(Map<String, dynamic>, bool, Message)
  buildAttachmentWidget;
  final void Function(Message, Map<String, dynamic>, String)
  onAttachmentLongPress;
  final void Function(Message) onMessageLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSelf,
    required this.startsRun,
    this.sender,
    this.seen = false,
    required this.onAttachmentTap,
    required this.buildAttachmentWidget,
    required this.onAttachmentLongPress,
    required this.onMessageLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    final hasAttachments = message.attachments != null;

    final sender = this.sender;
    final bubble = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => onMessageLongPress(message),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              (hasAttachments ? 0.75 : 0.70),
        ),
        child: Column(
          crossAxisAlignment: isSelf
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (sender != null && startsRun) _SenderLine(sender: sender),
            // Text-only message (no attachments)
            if (message.text != null && message.attachments == null)
              Opacity(
                opacity: message.isSending
                    ? 0.6
                    : (message.isDeleted ? 0.5 : 1.0),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: message.isDeleted
                        ? theme.messageDeletedBackground
                        : (isSelf ? theme.messageSentBackground : Colors.white),
                    borderRadius: BorderRadius.circular(8.r),
                    // A received bubble is plain white on the room's
                    // tinted canvas: the sender's colour is on the name
                    // and avatar, never on the bubble.
                    border: message.isDeleted
                        ? Border.all(color: theme.borderColor, width: 1)
                        : (isSelf
                              ? null
                              : Border.all(
                                  color: theme.getThemeAwareDividerColor(),
                                  width: 0.5,
                                )),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The time (and an own message's tick) rides on the last line
                      // when it fits, else drops below it.
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 8,
                        children: [
                          Text(
                            message.text!,
                            style: TextStyle(
                              fontSize: 16.sp,
                              color: message.isDeleted
                                  ? theme.messageDeletedText
                                  : (isSelf
                                        ? theme.messageSentText
                                        : theme.messageReceivedText),
                              decoration: message.isDeleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: theme.messageDeletedText,
                              fontStyle: message.isDeleted
                                  ? FontStyle.italic
                                  : null,
                            ),
                          ),
                          _MessageMeta(
                            message: message,
                            isSelf: isSelf,
                            seen: seen,
                            color: isSelf && !message.isDeleted
                                ? theme.messageSentText.withValues(alpha: 0.8)
                                : theme.messageTimestamp,
                          ),
                        ],
                      ),
                      if (message.isDeleted)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '[Deleted]',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: theme.messageDeletedText,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // Attachments (routing based on category)
            if (message.attachments != null && message.attachments!.isNotEmpty)
              Opacity(
                opacity: message.isSending
                    ? 0.6
                    : (message.isDeleted ? 0.5 : 1.0),
                child: () {
                  final category = _getAttachmentCategory(
                    message.attachments!,
                  );

                  switch (category) {
                    case _AttachmentCategory.multipleMedia:
                      // Multiple images/videos: show gallery grid
                      return MediaGalleryWidget(
                        attachments: message.attachments!,
                        isSelf: isSelf,
                        message: message,
                        buildAttachmentWidget: buildAttachmentWidget,
                        onAttachmentLongPress: onAttachmentLongPress,
                      );
                    case _AttachmentCategory.multipleFiles:
                      // Multiple files: show file list
                      return FileListWidget(
                        attachments: message.attachments!,
                        isSelf: isSelf,
                        message: message,
                        onAttachmentTap: (msg, att, fileName) async {
                          await onAttachmentTap(att, fileName);
                        },
                        onAttachmentLongPress: onAttachmentLongPress,
                      );
                    case _AttachmentCategory.single:
                      // Single attachment: use original logic
                      final attachment = message.attachments!.first;
                      return message.text != null && message.text!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8.r),
                              child: Container(
                                color: message.isDeleted
                                    ? theme.messageDeletedBackground
                                    : (isSelf
                                          ? theme.messageSentBackground
                                          : theme
                                                .getThemeAwareMessageBackground()),
                                child: Column(
                                  crossAxisAlignment: isSelf
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Attachment widget - full width, no padding
                                    if (!message.isDeleted)
                                      buildAttachmentWidget(
                                        attachment,
                                        isSelf,
                                        message,
                                      )
                                    else
                                      Container(
                                        height: 150,
                                        color: theme.messageDeletedBackground,
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.image_not_supported,
                                                color: theme.messageDeletedText,
                                                size: 40,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                '[Deleted Attachment]',
                                                style: TextStyle(
                                                  color:
                                                      theme.messageDeletedText,
                                                  fontStyle: FontStyle.italic,
                                                  fontSize: 12.sp,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    // Caption text at the bottom with margin
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        12,
                                        8,
                                        8,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            message.text!,
                                            style: TextStyle(
                                              fontSize: 16.sp,
                                              color: message.isDeleted
                                                  ? theme.messageDeletedText
                                                  : (isSelf
                                                        ? theme.messageSentText
                                                        : theme
                                                              .messageReceivedText),
                                              decoration: message.isDeleted
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              decorationColor: message.isDeleted
                                                  ? theme.messageDeletedText
                                                  : null,
                                              fontStyle: message.isDeleted
                                                  ? FontStyle.italic
                                                  : null,
                                            ),
                                          ),
                                          if (message.isDeleted)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Text(
                                                '[Deleted]',
                                                style: TextStyle(
                                                  fontSize: 12.sp,
                                                  color:
                                                      theme.messageDeletedText,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : !message.isDeleted
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8.r),
                              child: Container(
                                color: isSelf
                                    ? theme.messageSentBackground
                                    : theme.getThemeAwareMessageBackground(),
                                child: buildAttachmentWidget(
                                  attachment,
                                  isSelf,
                                  message,
                                ),
                              ),
                            )
                          : Container(
                              height: 150,
                              decoration: BoxDecoration(
                                color: theme.messageDeletedBackground,
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(
                                  color: theme.borderColor,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.image_not_supported,
                                      color: theme.messageDeletedText,
                                      size: 40,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      '[Deleted Attachment]',
                                      style: TextStyle(
                                        color: theme.messageDeletedText,
                                        fontStyle: FontStyle.italic,
                                        fontSize: 12.sp,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                  }
                }(),
              ),
            // A photo or file has no text line to carry it: under the card.
            if (hasAttachments)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _MessageMeta(
                  message: message,
                  isSelf: isSelf,
                  seen: seen,
                  color: theme.messageTimestamp,
                ),
              ),
          ],
        ),
      ),
    );

    // A new speaker gets air above; a run's own messages stay tight.
    final padding = EdgeInsets.only(top: startsRun ? 10 : 1, bottom: 1);
    if (sender == null) {
      return Padding(
        padding: padding,
        child: Align(
          alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
          child: bubble,
        ),
      );
    }
    // The avatar sits in a gutter the whole run keeps, so one sender's
    // messages read as one column.
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _SenderLine.avatarSize,
            child: startsRun ? _SenderAvatar(sender: sender) : null,
          ),
          const SizedBox(width: 4),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  _AttachmentCategory _getAttachmentCategory(
    List<Map<String, dynamic>> attachments,
  ) {
    if (attachments.isEmpty) return _AttachmentCategory.single;
    if (attachments.length == 1) return _AttachmentCategory.single;

    final types = attachments.map((a) => a['type'] as String? ?? '').toSet();

    // If all are media types (image or video)
    if (types.every((t) => t == 'image' || t == 'video')) {
      return _AttachmentCategory.multipleMedia;
    }

    // If all are files
    if (types.every((t) => t == 'file')) {
      return _AttachmentCategory.multipleFiles;
    }

    // Mixed types or other cases: default to media
    return _AttachmentCategory.multipleMedia;
  }
}

/// When a message was sent and, on an own message, how far it got: a clock
/// while sending, one tick once the engine has it, two once another member
/// has read it. The same three states as the web widget.
class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.message,
    required this.isSelf,
    required this.seen,
    required this.color,
  });

  final Message message;
  final bool isSelf;
  final bool seen;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final at = DateTime.tryParse(message.createdAt ?? '')?.toLocal();
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (time.isNotEmpty)
          Text(
            time,
            style: TextStyle(fontSize: 11.sp, color: color),
          ),
        if (isSelf && !message.isDeleted)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Icon(
              message.isSending
                  ? Icons.schedule
                  : (seen ? Icons.done_all : Icons.done),
              size: 14.sp,
              color: color,
            ),
          ),
      ],
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.sender});

  final MessageSender sender;

  @override
  Widget build(BuildContext context) {
    final name = sender.name.trim();
    return Container(
      width: _SenderLine.avatarSize,
      height: _SenderLine.avatarSize,
      margin: const EdgeInsets.only(top: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: sender.color, shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: 13.sp,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The sender's name in their colour, with their role as a chip beside it.
class _SenderLine extends StatelessWidget {
  const _SenderLine({required this.sender});

  static const double avatarSize = 28;

  final MessageSender sender;

  @override
  Widget build(BuildContext context) {
    final role = sender.role;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              sender.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                color: sender.color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (role != null)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: sender.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                role,
                maxLines: 1,
                style: TextStyle(fontSize: 11.sp, color: sender.color),
              ),
            ),
        ],
      ),
    );
  }
}
