import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import '../config/chat_config.dart';
import '../services/chat_service.dart';
import 'location_map_preview.dart';

/// Result of the send-location confirmation dialog: the resolved [Position]
/// plus the [thumbnailBytes] of the map preview PNG that was downloaded for
/// the dialog preview (so the send flow doesn't have to download it again).
class SendLocationResult {
  final Position position;
  final Uint8List? thumbnailBytes;

  const SendLocationResult({required this.position, this.thumbnailBytes});
}

/// A confirmation dialog for sending the current location.
///
/// It opens immediately (so the user isn't left waiting on location lookups)
/// and resolves the current position in the background. Once the position is
/// known, the map preview PNG is downloaded once and shown from the in-memory
/// bytes. Tapping "Send" resolves the dialog with a [SendLocationResult]
/// carrying the position and the preview bytes; "Cancel" (or dismiss)
/// resolves to `null` and the bytes simply get garbage-collected.
class SendLocationDialog extends StatefulWidget {
  /// Fetches the raw preview thumbnail PNG bytes for a location.
  final ChatService chatService;
  final String Function(double latitude, double longitude) buildThumbnailUrl;
  final ChatConfig? chatConfig;

  const SendLocationDialog({
    super.key,
    required this.chatService,
    required this.buildThumbnailUrl,
    this.chatConfig,
  });

  /// Show the dialog and resolve with a [SendLocationResult], or `null` if
  /// the user cancels / the dialog is dismissed.
  static Future<SendLocationResult?> show(
    BuildContext context, {
    required ChatService chatService,
    required String Function(double latitude, double longitude)
    buildThumbnailUrl,
    ChatConfig? chatConfig,
  }) {
    return showDialog<SendLocationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SendLocationDialog(
        chatService: chatService,
        buildThumbnailUrl: buildThumbnailUrl,
        chatConfig: chatConfig,
      ),
    );
  }

  @override
  State<SendLocationDialog> createState() => _SendLocationDialogState();
}

class _SendLocationDialogState extends State<SendLocationDialog> {
  Position? _position;
  Uint8List? _thumbnailBytes;
  bool _downloadingPreview = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolvePosition();
  }

  Future<void> _resolvePosition() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _position = position;
        _loading = false;
      });
      // Fetch the preview PNG once; the bytes are kept in memory and handed
      // to the send flow on confirm so the image is never downloaded twice.
      _downloadPreview(position);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to get your current location: $e';
        _loading = false;
      });
    }
  }

  Future<void> _downloadPreview(Position position) async {
    setState(() => _downloadingPreview = true);
    try {
      final url = widget.buildThumbnailUrl(
        position.latitude,
        position.longitude,
      );
      final bytes = url.isEmpty
          ? null
          : await widget.chatService.fetchLocationThumbnailBytes(url);
      if (!mounted) return;
      setState(() {
        _thumbnailBytes = bytes;
        _downloadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloadingPreview = false);
      widget.chatConfig?.logger.e(
        'Failed to download location preview',
        error: e,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;

    return AlertDialog(
      title: const Text('Send Location'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fills the dialog's content width; height derived from the map's
          // 16:9 aspect ratio instead of a hard-coded value.
          _buildPreview(position),
          SizedBox(height: 12.h),
          if (_loading)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Flexible(
                  child: Text('Getting your current location...'),
                ),
              ],
            )
          else if (position != null)
            Text(
              'Send your current location '
              '(${position.latitude.toStringAsFixed(6)}, '
              '${position.longitude.toStringAsFixed(6)})?',
            )
          else
            Text(_error ?? 'Waiting for location...'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        // Disable Send until we have a valid position.
        TextButton(
          onPressed: position != null
              ? () => Navigator.of(context).pop(
                  SendLocationResult(
                    position: position,
                    thumbnailBytes: _thumbnailBytes,
                  ),
                )
              : null,
          child: const Text('Send'),
        ),
      ],
    );
  }

  /// Build the preview. Stages:
  /// 1. No position yet (resolving) -> placeholder.
  /// 2. Position resolved, preview bytes downloaded -> render from memory.
  /// 3. Position resolved but bytes pending/failed -> placeholder.
  Widget _buildPreview(Position? position) {
    if (position == null) {
      return const LocationMapPreview(latitude: 0, longitude: 0);
    }
    return LocationMapPreview.fromBytes(
      latitude: position.latitude,
      longitude: position.longitude,
      thumbnailBytes: _thumbnailBytes,
      isLoading: _downloadingPreview,
    );
  }
}
