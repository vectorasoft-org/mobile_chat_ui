import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'location_map_preview.dart';

/// A confirmation dialog for sending the current location.
///
/// It opens immediately (so the user isn't left waiting on location lookups)
/// and resolves the current position in the background. While resolving it
/// shows a loading preview; once the position is known, it swaps in a map
/// preview built via [buildThumbnailUrl]. Tapping "Send" resolves the dialog
/// with the resolved [Position]; "Cancel" (or dismiss) resolves to `null`.
class SendLocationDialog extends StatefulWidget {
  /// Builds the raw preview thumbnail URL for a location (no storage hit).
  final String Function(double latitude, double longitude) buildThumbnailUrl;

  const SendLocationDialog({super.key, required this.buildThumbnailUrl});

  /// Show the dialog and resolve with the resolved [Position], or `null` if
  /// the user cancels / the dialog is dismissed.
  static Future<Position?> show(
    BuildContext context, {
    required String Function(double latitude, double longitude)
    buildThumbnailUrl,
  }) {
    return showDialog<Position>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SendLocationDialog(
        buildThumbnailUrl: buildThumbnailUrl,
      ),
    );
  }

  @override
  State<SendLocationDialog> createState() => _SendLocationDialogState();
}

class _SendLocationDialogState extends State<SendLocationDialog> {
  Position? _position;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to get your current location: $e';
        _loading = false;
      });
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
              ? () => Navigator.of(context).pop(position)
              : null,
          child: const Text('Send'),
        ),
      ],
    );
  }

  /// Build the preview. Stages:
  /// 1. No thumbnail yet (resolving) -> placeholder.
  /// 2. Position resolved -> show the raw generator URL (no storage hit) as a
  ///    preview; the storage-resolved URL is only used after sending.
  /// Build the preview. Stages:
  /// 1. No thumbnail yet (resolving) -> placeholder.
  /// 2. Position resolved -> show the raw generator URL (no storage hit) as a
  ///    preview; the storage-resolved URL is only used after sending.
  Widget _buildPreview(Position? position) {
    if (position == null) {
      return const LocationMapPreview(
        latitude: 0,
        longitude: 0,
        thumbnailUrl: '',
      );
    }
    return LocationMapPreview(
      latitude: position.latitude,
      longitude: position.longitude,
      thumbnailUrl: widget.buildThumbnailUrl(
        position.latitude,
        position.longitude,
      ),
    );
  }
}
