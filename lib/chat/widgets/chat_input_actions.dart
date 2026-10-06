import 'package:flutter/material.dart';
import '../config/chat_theme_provider.dart';
import '../config/chat_theme.dart';
import '../services/chat_localizations.dart';

/// Geometry shared by every control on the composer bar, so the `+`, the
/// capsule field, the mic and the send button sit on one optical line and
/// every one of them clears the 44pt touch minimum.
class ChatInputMetrics {
  const ChatInputMetrics._();

  static const double control = 44.0;
  static const double icon = 22.0;
  static const double gap = 4.0;
}

/// The single attachment entry point: one `+` that opens the attachment
/// sheet. It never hides - attaching no longer costs a keyboard dismissal.
class ChatInputActions extends StatelessWidget {
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickLocation;

  const ChatInputActions({
    super.key,
    required this.onPickFile,
    required this.onPickImage,
    required this.onTakePhoto,
    required this.onPickLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return ChatInputIconButton(
      icon: Icons.add_rounded,
      color: theme.inputIcon,
      tooltip: ChatLocalizations.text(context, 'attachTitle'),
      onPressed: () => _openSheet(context, theme),
    );
  }

  Future<void> _openSheet(BuildContext context, ChatTheme theme) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.inputBarBackground,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _AttachmentSheet(theme: theme),
    );
    if (choice == null) return;
    switch (choice) {
      case 'image':
        onPickImage();
        break;
      case 'camera':
        onTakePhoto();
        break;
      case 'file':
        onPickFile();
        break;
      case 'location':
        onPickLocation();
        break;
    }
  }
}

class _AttachmentSheet extends StatelessWidget {
  final ChatTheme theme;

  const _AttachmentSheet({required this.theme});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _tile(context, Icons.photo_outlined, 'attachPhoto', 'image'),
                _tile(context, Icons.photo_camera_outlined, 'attachCamera',
                    'camera'),
                _tile(context, Icons.description_outlined, 'attachFile',
                    'file'),
                _tile(context, Icons.location_on_outlined, 'attachLocation',
                    'location'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String labelKey,
    String value,
  ) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pop(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: theme.primaryColor),
              ),
              const SizedBox(height: 8),
              Text(
                ChatLocalizations.text(context, labelKey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: theme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A flat composer control: a neutral glyph in a full-size touch target.
class ChatInputIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? tooltip;
  final VoidCallback? onPressed;

  const ChatInputIconButton({
    super.key,
    required this.icon,
    required this.color,
    this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkResponse(
      onTap: onPressed,
      radius: ChatInputMetrics.control / 2,
      child: SizedBox(
        width: ChatInputMetrics.control,
        height: ChatInputMetrics.control,
        child: Icon(icon, size: ChatInputMetrics.icon, color: color),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Send: the one accent on the bar. Filled when there is something to send,
/// muted when there is not - the bar never promises an action it won't take.
class ChatInputSendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onPressed;

  const ChatInputSendButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: ChatInputMetrics.control,
        height: ChatInputMetrics.control,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: enabled ? theme.primaryColor : theme.inputFieldFill,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_upward_rounded,
              size: 20,
              color: enabled ? Colors.white : theme.disabledColor,
            ),
          ),
        ),
      ),
    );
  }
}
