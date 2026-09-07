import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../config/chat_theme_provider.dart';

class ChatInputActions extends StatelessWidget {
  final bool hasFocus;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickLocation;

  const ChatInputActions({
    super.key,
    required this.hasFocus,
    required this.onPickFile,
    required this.onPickImage,
    required this.onTakePhoto,
    required this.onPickLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      child: hasFocus
          ? const SizedBox.shrink()
          : PopupMenuButton<String>(
              icon: Icon(Icons.add, color: theme.buttonIcon),
              iconSize: 18,
              padding: const EdgeInsets.all(2),
              onSelected: (String value) {
                // Unfocus any focused widget before calling callbacks
                FocusManager.instance.primaryFocus?.unfocus();
                if (value == 'file') {
                  onPickFile();
                } else if (value == 'camera') {
                  onTakePhoto();
                } else if (value == 'location') {
                  onPickLocation();
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  value: 'camera',
                  child: Row(
                    children: [
                      Icon(
                        Icons.camera_alt,
                        size: 18,
                        color: Colors.black87,
                      ),
                      SizedBox(width: 8.w),
                      const Text('Take Photo'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'file',
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_file,
                        size: 18,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 8),
                      const Text('Add File'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'location',
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 8),
                      const Text('Add Location'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class ChatInputImageButton extends StatelessWidget {
  final bool hasFocus;
  final VoidCallback onPressed;

  const ChatInputImageButton({
    super.key,
    required this.hasFocus,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      child: hasFocus
          ? const SizedBox.shrink()
          : IconButton(
              icon: const Icon(Icons.image),
              iconSize: 18,
              padding: const EdgeInsets.all(2),
              color: theme.buttonIcon,
              onPressed: onPressed,
            ),
    );
  }
}

class ChatInputSpacing extends StatelessWidget {
  final bool hasFocus;

  const ChatInputSpacing({
    super.key,
    required this.hasFocus,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      child: hasFocus ? const SizedBox.shrink() : SizedBox(width: 4.w),
    );
  }
}

class ChatInputSendButton extends StatelessWidget {
  final bool isRecording;
  final bool hasPendingRecording;
  final bool isTapping;
  final bool isHolding;
  final VoidCallback? onPressed;

  const ChatInputSendButton({
    super.key,
    required this.isRecording,
    this.hasPendingRecording = false,
    this.isTapping = false,
    this.isHolding = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    // Disable send button only when in hold mode (not tap mode)
    // Allow send in: tap mode, hold mode with pending recording, or not recording
    final isDisabled = isHolding && !hasPendingRecording;
    return GestureDetector(
      onTap: isDisabled ? null : onPressed,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.send,
          size: 18,
          color: isDisabled ? theme.disabledColor : theme.primaryColor,
        ),
      ),
    );
  }
}
