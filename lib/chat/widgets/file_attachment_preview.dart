import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:marquee/marquee.dart';
import '../models.dart';
import '../config/chat_theme_provider.dart';
import '../config/chat_logger.dart';

/// Reusable widget for rendering a single file attachment with consistent styling.
/// Handles all aspects: background color, padding, icon/preview, text styling, etc.
class FileAttachmentPreview extends StatefulWidget {
  final Map<String, dynamic> attachment;
  final bool isSelf;
  final Message message;
  final Widget Function(Map<String, dynamic>) previewBuilder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ChatLogger? logger;

  // Marquee animation customization
  final Duration marqueeInitialPauseDuration;
  final double marqueeScrollSpeed; // pixels per second

  const FileAttachmentPreview({
    super.key,
    required this.attachment,
    required this.isSelf,
    required this.message,
    required this.previewBuilder,
    required this.onTap,
    required this.onLongPress,
    this.logger,
    this.marqueeInitialPauseDuration = const Duration(seconds: 2),
    this.marqueeScrollSpeed = 50.0, // reasonable default: 50px/s
  });

  @override
  State<FileAttachmentPreview> createState() => _FileAttachmentPreviewState();
}

class _FileAttachmentPreviewState extends State<FileAttachmentPreview> {
  String _getFileName() {
    return widget.attachment['title'] as String? ??
        widget.attachment['fallback'] ??
        'File';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  Color _getIconContainerColor() {
    final mimeType =
        widget.attachment['mime_type'] as String? ?? 'application/octet-stream';
    final lowerType = mimeType.toLowerCase();

    if (lowerType.startsWith('image/')) {
      return Colors.blue[100]!;
    }
    if (lowerType.startsWith('audio/')) {
      return Colors.orange[100]!;
    }
    if (lowerType.startsWith('video/')) {
      return Colors.purple[100]!;
    }
    if (lowerType.startsWith('application/pdf')) {
      return Colors.red[100]!;
    }
    if (lowerType.contains('word') || lowerType.contains('document')) {
      return Colors.blue[100]!;
    }
    if (lowerType.contains('sheet') || lowerType.contains('excel')) {
      return Colors.green[100]!;
    }
    if (lowerType.contains('presentation') ||
        lowerType.contains('powerpoint')) {
      return Colors.red[100]!;
    }
    if (lowerType.contains('zip') ||
        lowerType.contains('rar') ||
        lowerType.contains('compress')) {
      return Colors.amber[100]!;
    }

    return Colors.indigo[100]!;
  }

  Widget _buildMarqueeFileName(TextStyle textStyle) {
    return ShaderMask(
      shaderCallback: (bounds) {
        const fadeWidth = 16.0; // Width of fade at each edge
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [
            0.0,
            (bounds.width - fadeWidth) / bounds.width,
            1.0,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: Marquee(
        text: _getFileName(),
        style: textStyle,
        scrollAxis: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.center,
        blankSpace: 20.0,
        velocity: widget.marqueeScrollSpeed,
        pauseAfterRound: widget.marqueeInitialPauseDuration,
        startPadding: 0.0,
        accelerationDuration: const Duration(milliseconds: 0),
        accelerationCurve: Curves.linear,
        decelerationDuration: const Duration(milliseconds: 0),
        decelerationCurve: Curves.linear,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    final fileName = _getFileName();
    final fileSize = widget.attachment['file_size'] as int? ?? 0;
    final fileSizeStr = _formatFileSize(fileSize);
    final textColor = widget.isSelf ? Colors.white : Colors.black;

    // Get full text style from Material theme
    final materialTheme = Theme.of(context);
    final baseTextStyle =
        materialTheme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 14, fontFamily: 'Roboto');

    final textStyle = baseTextStyle.copyWith(
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      color: textColor,
      backgroundColor: Colors.transparent,
      inherit: true, // Ensure inherited properties are applied
    );

    widget.logger?.d(
      'FileAttachmentPreview textStyle: '
      'color=$textColor, fontSize=14.sp, fontWeight=w500, '
      'baseFamily=${baseTextStyle.fontFamily}, '
      'finalStyle=$textStyle',
    );

    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: widget.message.isSending ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Container(
              decoration: BoxDecoration(
                color: widget.isSelf
                    ? theme.primaryColor
                    : (widget.message.isSending
                          ? theme.getThemeAwareGrey(300)
                          : theme.getThemeAwareAttachmentBackground()),
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
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Center(
                      child: widget.previewBuilder(widget.attachment),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Measure actual text width
                        final textPainter = TextPainter(
                          text: TextSpan(text: fileName, style: textStyle),
                          textDirection: TextDirection.ltr,
                        );
                        textPainter.layout();
                        final textWidth = textPainter.width;

                        // Calculate actual available width accounting for constraints
                        // Add buffer for safety and to be conservative about when to show marquee
                        final buffer =
                            16.0; // Increased buffer to be more conservative
                        final availableWidth = constraints.maxWidth - buffer;

                        // Check if text actually overflows
                        final needsMarquee = textWidth > availableWidth;

                        // Log overflow detection
                        widget.logger?.d(
                          'FileAttachmentPreview Marquee Check: fileName="$fileName", '
                          'textWidth=${textWidth.toStringAsFixed(2)}px, '
                          'constraintsMaxWidth=${constraints.maxWidth.toStringAsFixed(2)}px, '
                          'availableWidth=${availableWidth.toStringAsFixed(2)}px (with ${buffer}px buffer), '
                          'needsMarquee=$needsMarquee',
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (needsMarquee)
                              SizedBox(
                                height: 20.h,
                                child: _buildMarqueeFileName(textStyle),
                              )
                            else
                              // Display full text at natural width without constraint
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    fileName,
                                    style: textStyle,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            SizedBox(height: 4.h),
                            Text(
                              fileSizeStr,
                              style: TextStyle(
                                fontSize: 10.sp,
                                color: widget.isSelf
                                    ? Colors.white70
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        );
                      },
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
