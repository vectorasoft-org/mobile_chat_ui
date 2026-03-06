import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models.dart';
import '../config/chat_theme_provider.dart';

class MediaGalleryWidget extends StatefulWidget {
  final List<Map<String, dynamic>> attachments;
  final bool isSelf;
  final Message message;
  final Widget Function(Map<String, dynamic>, bool, Message)
  buildAttachmentWidget;
  final void Function(Message, Map<String, dynamic>, String)
  onAttachmentLongPress;

  const MediaGalleryWidget({
    super.key,
    required this.attachments,
    required this.isSelf,
    required this.message,
    required this.buildAttachmentWidget,
    required this.onAttachmentLongPress,
  });

  @override
  State<MediaGalleryWidget> createState() => _MediaGalleryWidgetState();
}

class _MediaGalleryWidgetState extends State<MediaGalleryWidget> {
  String _getAttachmentFileName(Map<String, dynamic> attachment) {
    final type = attachment['type'] as String? ?? '';
    switch (type) {
      case 'image':
        return attachment['fallback'] ?? 'image';
      case 'video':
        return attachment['title'] ?? 'video';
      default:
        return attachment['title'] ?? attachment['fallback'] ?? 'file';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    final hasCaption =
        widget.message.text != null && widget.message.text!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.isSelf
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Media gallery grid
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: widget.attachments.length,
                itemBuilder: (context, index) {
                  final attachment = widget.attachments[index];
                  final fileName = _getAttachmentFileName(attachment);

                  return GestureDetector(
                    onLongPress: () {
                      widget.onAttachmentLongPress(
                        widget.message,
                        attachment,
                        fileName,
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.r),
                      child: Container(
                        color: widget.message.isDeleted
                            ? theme.messageDeletedBackground
                            : Colors.grey[300],
                        child: widget.message.isDeleted
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.image_not_supported,
                                      color: theme.messageDeletedText,
                                      size: 28,
                                    ),
                                    SizedBox(height: 4.h),
                                    Text(
                                      '[Deleted]',
                                      style: TextStyle(
                                        color: theme.messageDeletedText,
                                        fontStyle: FontStyle.italic,
                                        fontSize: 10.sp,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : widget.buildAttachmentWidget(
                                attachment,
                                widget.isSelf,
                                widget.message,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Caption text below grid (if message has text)
            if (hasCaption)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      widget.message.text!,
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: widget.message.isDeleted
                            ? theme.messageDeletedText
                            : (widget.isSelf
                                  ? theme.messageSentText
                                  : theme.messageReceivedText),
                        decoration: widget.message.isDeleted
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: widget.message.isDeleted
                            ? theme.messageDeletedText
                            : null,
                        fontStyle: widget.message.isDeleted
                            ? FontStyle.italic
                            : null,
                      ),
                    ),
                    if (widget.message.isDeleted)
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
          ],
        ),
      ),
    );
  }
}
