import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';

import '../config/chat_theme_provider.dart';
import '../models.dart';
import '../services/chat_service.dart';

abstract class AttachmentResolver {
  Widget buildWidget(Map<String, dynamic> attachment, Message message);
  Widget buildSmallPreview(Map<String, dynamic> attachment);
  Future<Uint8List?> extractImageBytes(
    Map<String, dynamic> attachment,
    bool isAsset,
  );
}

class RealImageResolver implements AttachmentResolver {
  static const double _maxImageHeight = 350;

  final ChatService? chatService;

  RealImageResolver({this.chatService});

  @override
  Widget buildWidget(Map<String, dynamic> attachment, Message message) {
    final imageUrl = attachment['image_url'] ?? attachment['url'] ?? '';

    return Builder(
      builder: (context) {
        return GestureDetector(
          onTap: () => _showImageViewer(context, message, imageUrl: imageUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 350,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) {
                  final theme = ChatThemeProvider.of(context);
                  return Container(
                    width: 350,
                    height: _maxImageHeight,
                    decoration: BoxDecoration(
                      color: theme.inputBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.image_not_supported,
                      color: theme.textPrimary,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget buildSmallPreview(Map<String, dynamic> attachment) {
    final imageUrl = attachment['asset_url'] ?? attachment['url'] ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) {
          final theme = ChatThemeProvider.of(context);
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.inputBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.image,
              size: 20,
              color: theme.textPrimary,
            ),
          );
        },
      ),
    );
  }

  @override
  Future<Uint8List?> extractImageBytes(
    Map<String, dynamic> attachment,
    bool isAsset,
  ) async {
    return null;
  }

  void _showImageViewer(
    BuildContext context,
    Message message, {
    String? imageUrl,
    Uint8List? imageBytes,
  }) {
    final theme = ChatThemeProvider.of(context);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThemeProvider(
          theme: theme,
          child: Builder(
            builder: (innerContext) {
              return Scaffold(
                backgroundColor: theme.videoControlBackground,
                appBar: AppBar(
                  backgroundColor: theme.videoControlBackground,
                  iconTheme: IconThemeData(color: theme.videoControlIcon),
                  actions: [
                    IconButton(
                      icon: Icon(
                        Icons.download_rounded,
                        color: theme.videoControlIcon,
                      ),
                      onPressed: () async {
                        try {
                          final downloadsDir = await getDownloadsDirectory();
                          if (downloadsDir == null) {
                            if (innerContext.mounted) {
                              ScaffoldMessenger.of(innerContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Downloads directory not found',
                                  ),
                                ),
                              );
                            }
                            return;
                          }

                          if (chatService == null) {
                            if (innerContext.mounted) {
                              ScaffoldMessenger.of(innerContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Download service unavailable'),
                                ),
                              );
                            }
                            return;
                          }

                          final downloadedPath = await chatService!
                              .downloadFile(
                                message: message,
                                imageUrl: imageUrl,
                                fileExtension: 'jpg',
                              );

                          if (downloadedPath != null &&
                              downloadedPath.isNotEmpty &&
                              innerContext.mounted) {
                            ScaffoldMessenger.of(innerContext).showSnackBar(
                              const SnackBar(
                                content: Text('Image saved to Downloads'),
                                duration: Duration(milliseconds: 1500),
                              ),
                            );
                          }
                        } catch (_) {
                          if (innerContext.mounted) {
                            ScaffoldMessenger.of(innerContext).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to download image'),
                                duration: Duration(milliseconds: 1500),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
                body: PhotoView(
                  imageProvider: imageUrl != null
                      ? _getImageProvider(imageUrl)
                      : MemoryImage(imageBytes!) as ImageProvider,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('file://')) {
      final filePath = url.replaceFirst('file://', '');
      return FileImage(File(filePath));
    }
    return NetworkImage(url);
  }
}

class ImageDimensions {
  final int width;
  final int height;

  ImageDimensions({required this.width, required this.height});
}
