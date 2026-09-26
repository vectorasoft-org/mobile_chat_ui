import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'config/chat_theme_provider.dart';
import 'models.dart';
import 'widgets/media_gallery_widget.dart';
import 'widgets/file_list_widget.dart';

enum _AttachmentCategory { single, multipleMedia, multipleFiles }

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isSelf;
  final bool showSenderName;
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
    required this.showSenderName,
    required this.onAttachmentTap,
    required this.buildAttachmentWidget,
    required this.onAttachmentLongPress,
    required this.onMessageLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    final hasAttachments = message.attachments != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Align(
        alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: () => onMessageLongPress(message),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.of(context).size.width *
                  (hasAttachments ? 0.75 : 0.60),
            ),
            child: Column(
              crossAxisAlignment: isSelf
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
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
                            : (isSelf
                                  ? theme.messageSentBackground
                                  : (message.isSending
                                        ? theme.getThemeAwareMessageBackground()
                                        : theme
                                              .getThemeAwareMessageBackground())),
                        borderRadius: BorderRadius.circular(8.r),
                        border: message.isDeleted
                            ? Border.all(color: theme.borderColor, width: 1)
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                if (message.attachments != null &&
                    message.attachments!.isNotEmpty)
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
                          return message.text != null &&
                                  message.text!.isNotEmpty
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
                                            color:
                                                theme.messageDeletedBackground,
                                            child: Center(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.image_not_supported,
                                                    color: theme
                                                        .messageDeletedText,
                                                    size: 40,
                                                  ),
                                                  SizedBox(height: 8),
                                                  Text(
                                                    '[Deleted Attachment]',
                                                    style: TextStyle(
                                                      color: theme
                                                          .messageDeletedText,
                                                      fontStyle:
                                                          FontStyle.italic,
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
                                                            ? theme
                                                                  .messageSentText
                                                            : theme
                                                                  .messageReceivedText),
                                                  decoration: message.isDeleted
                                                      ? TextDecoration
                                                            .lineThrough
                                                      : null,
                                                  decorationColor:
                                                      message.isDeleted
                                                      ? theme.messageDeletedText
                                                      : null,
                                                  fontStyle: message.isDeleted
                                                      ? FontStyle.italic
                                                      : null,
                                                ),
                                              ),
                                              if (message.isDeleted)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    '[Deleted]',
                                                    style: TextStyle(
                                                      fontSize: 12.sp,
                                                      color: theme
                                                          .messageDeletedText,
                                                      fontStyle:
                                                          FontStyle.italic,
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
                                        : theme
                                              .getThemeAwareMessageBackground(),
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
                // Show sender name independently of attachment type
                if (showSenderName)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    child: Text(
                      message.author ?? message.sender,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: theme.messageSenderName,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
