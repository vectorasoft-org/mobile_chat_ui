import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';

import '../config/chat_config.dart';
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
  final ChatConfig? chatConfig;

  RealImageResolver({this.chatService, this.chatConfig});

  /// Headers for loading images served from the chat backend.
  Map<String, String> get _httpHeaders =>
      chatConfig?.httpAuthHeaders() ?? const {};

  @override
  Widget buildWidget(Map<String, dynamic> attachment, Message message) {
    final imageUrl = attachment['image_url'] ?? attachment['url'] ?? '';

    return Builder(
      builder: (context) {
        return GestureDetector(
          onTap: () => showImageViewer(context, message, imageUrl: imageUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 350,
              child: _isDataUri(imageUrl)
                  ? _buildDataUriImage(imageUrl, 350, _maxImageHeight)
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      httpHeaders: _httpHeaders,
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
      child: _isDataUri(imageUrl)
          ? _buildDataUriImage(imageUrl, 40, 40)
          : CachedNetworkImage(
              imageUrl: imageUrl,
              httpHeaders: _httpHeaders,
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

  bool _isDataUri(String url) => url.startsWith('data:');

  Widget _buildDataUriImage(String dataUri, double width, double height) {
    final bytes = _decodeDataUri(dataUri);
    if (bytes == null) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: const Icon(Icons.image_not_supported),
      );
    }
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }

  Uint8List? _decodeDataUri(String dataUri) {
    final commaIndex = dataUri.indexOf(',');
    if (commaIndex == -1) return null;
    final base64Part = dataUri.substring(commaIndex + 1);
    try {
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> extractImageBytes(
    Map<String, dynamic> attachment,
    bool isAsset,
  ) async {
    return null;
  }

  void showImageViewer(
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
    if (url.startsWith('data:')) {
      final bytes = _decodeDataUri(url);
      if (bytes != null) {
        return MemoryImage(bytes);
      }
    }
    return NetworkImage(url, headers: _httpHeaders);
  }
}

class ImageDimensions {
  final int width;
  final int height;

  ImageDimensions({required this.width, required this.height});
}
