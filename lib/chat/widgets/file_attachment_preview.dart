import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models.dart';
import '../config/chat_theme_provider.dart';

/// Reusable widget for rendering a single file attachment with consistent styling.
/// Handles all aspects: background color, padding, icon/preview, text styling, etc.
class FileAttachmentPreview extends StatelessWidget {
  final Map<String, dynamic> attachment;
  final bool isSelf;
  final Message message;
  final Widget Function(Map<String, dynamic>) previewBuilder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileAttachmentPreview({
    super.key,
    required this.attachment,
    required this.isSelf,
    required this.message,
    required this.previewBuilder,
    required this.onTap,
    required this.onLongPress,
  });

  String _getFileName() {
    return attachment['title'] as String? ?? attachment['fallback'] ?? 'File';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes.toString().length - 1) ~/ 3;
    return '${(bytes / (1000 * (1 << (i * 10)))).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Color _getIconContainerColor() {
    final mimeType =
        attachment['mime_type'] as String? ?? 'application/octet-stream';
    final lowerType = mimeType.toLowerCase();

    if (lowerType.startsWith('image/')) return Colors.blue[100]!;
    if (lowerType.startsWith('audio/')) return Colors.orange[100]!;
    if (lowerType.startsWith('video/')) return Colors.purple[100]!;
    if (lowerType.startsWith('application/pdf')) return Colors.red[100]!;
    if (lowerType.contains('word') || lowerType.contains('document'))
      return Colors.blue[100]!;
    if (lowerType.contains('sheet') || lowerType.contains('excel'))
      return Colors.green[100]!;
    if (lowerType.contains('presentation') || lowerType.contains('powerpoint'))
      return Colors.red[100]!;
    if (lowerType.contains('zip') ||
        lowerType.contains('rar') ||
        lowerType.contains('compress'))
      return Colors.amber[100]!;

    return Colors.grey[300]!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    final fileName = _getFileName();
    final fileSize = attachment['file_size'] as int? ?? 0;
    final fileSizeStr = _formatFileSize(fileSize);

    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: message.isSending ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              decoration: BoxDecoration(
                color: isSelf
                    ? theme.primaryColor
                    : (message.isSending ? Colors.grey[300] : Colors.white),
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
                      color: _getIconContainerColor(),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Center(
                      child: previewBuilder(attachment),
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
                            fontSize: 14.sp,
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
}
