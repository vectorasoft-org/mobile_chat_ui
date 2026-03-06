import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models.dart';
import '../config/chat_theme_provider.dart';
import 'file_attachment_preview.dart';

class FileListWidget extends StatelessWidget {
  final List<Map<String, dynamic>> attachments;
  final bool isSelf;
  final Message message;
  final Future<void> Function(Message, Map<String, dynamic>, String)
  onAttachmentTap;
  final void Function(Message, Map<String, dynamic>, String)
  onAttachmentLongPress;

  const FileListWidget({
    super.key,
    required this.attachments,
    required this.isSelf,
    required this.message,
    required this.onAttachmentTap,
    required this.onAttachmentLongPress,
  });

  String _getFileName(Map<String, dynamic> attachment) {
    return attachment['title'] as String? ?? attachment['fallback'] ?? 'File';
  }

  Icon _getFileIcon(String mimeType) {
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

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    final hasCaption = message.text != null && message.text!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        color: message.isDeleted
            ? theme.messageDeletedBackground
            : Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: isSelf
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // File list - render each file using FileAttachmentPreview
            ...attachments.map((attachment) {
              // For deleted messages, show placeholder
              if (message.isDeleted) {
                final fileName = _getFileName(attachment);
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.messageDeletedBackground,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: theme.borderColor, width: 1),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.insert_drive_file,
                          color: theme.messageDeletedText,
                          size: 20,
                        ),
                        SizedBox(width: 12.w),
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
                                  color: theme.messageDeletedText,
                                  decoration: TextDecoration.lineThrough,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                '[Deleted]',
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  color: theme.messageDeletedText,
                                  fontStyle: FontStyle.italic,
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

              // For regular messages, use FileAttachmentPreview delegate
              return FileAttachmentPreview(
                attachment: attachment,
                isSelf: isSelf,
                message: message,
                previewBuilder: (att) => _getFileIcon(
                  att['mime_type'] as String? ?? 'application/octet-stream',
                ),
                onTap: () => onAttachmentTap(
                  message,
                  attachment,
                  _getFileName(attachment),
                ),
                onLongPress: () => onAttachmentLongPress(
                  message,
                  attachment,
                  _getFileName(attachment),
                ),
              );
            }),
            // Caption text below list (if message has text)
            if (hasCaption)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
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
                        decorationColor: message.isDeleted
                            ? theme.messageDeletedText
                            : null,
                        fontStyle: message.isDeleted ? FontStyle.italic : null,
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
          ],
        ),
      ),
    );
  }
}
