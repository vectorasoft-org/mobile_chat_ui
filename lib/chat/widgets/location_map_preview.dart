import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// A non-interactive map preview that renders a static map thumbnail for the
/// given coordinates.
///
/// The thumbnail is a PNG uploaded to the storage service (served from
/// `/chat/resource/...`), whose URL is cached in the external storage service
/// keyed by coordinates. The map is intentionally static (not
/// movable/scrollable) and is meant to be used as a lightweight preview.
/// Tapping it is handled by the caller (e.g. to open the location in the full
/// Google Maps app).
class LocationMapPreview extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String thumbnailUrl;
  final VoidCallback? onTap;

  const LocationMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.thumbnailUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        // Uses AspectRatio so the preview scales to its parent's width instead
        // of relying on hard-coded dimensions.
        child: AspectRatio(
          aspectRatio: 16 / 9,
          // Static map thumbnail. Uses CachedNetworkImage so the browser /
          // gallery caches the image. If no thumbnail URL is available yet
          // (the placeholder stage), show a loading/placeholder preview. If
          // the URL fails to load, fall back to the placeholder.
          child: thumbnailUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => _buildPlaceholder(),
                  errorWidget: (context, url, error) => _buildPlaceholder(),
                )
              : _buildPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map, size: 32.sp, color: Colors.grey[600]),
            SizedBox(height: 4.h),
            Text(
              'Map preview unavailable',
              style: TextStyle(fontSize: 11.sp, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}
