import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import '../config/chat_logger.dart';

/// Callback for app-specific UI feedback (snackbars, toasts, etc)
typedef OnUIFeedback = Function(String title, String message);

/// Callback for showing a system dialog to open a downloaded file
typedef OnFileDownloaded =
    Future<bool> Function(String fileName, String filePath);

class FileDownloadHandler {
  final ChatLogger _logger;
  final OnUIFeedback? onError;
  final OnUIFeedback? onSuccess;
  final OnFileDownloaded? onFileDownloaded;

  FileDownloadHandler({
    required ChatLogger logger,
    this.onError,
    this.onSuccess,
    this.onFileDownloaded,
  }) : _logger = logger;

  Future<void> downloadFileWithSystemFallback(
    Message message,
    Map<String, dynamic> attachment,
    String attachmentType,
  ) async {
    try {
      // Generic files use original filename (sanitized)
      // Images, videos, and audio use prefix convention
      final fileName = attachment['title'] as String? ?? 'File';
      final fileUrl =
          attachment['asset_url'] as String? ??
          attachment['image_url'] as String?;

      if (fileUrl == null) {
        _logger.e('No asset URL in attachment');
        onError?.call('Error', 'No file data available');
        return;
      }

      // Determine if this should use prefix convention based on attachment type
      // attachmentType is already determined by caller: 'image', 'video', 'audio', 'voiceRecording', 'file'
      final shouldUsePrefixConvention =
          attachmentType == 'image' ||
          attachmentType == 'video' ||
          attachmentType == 'audio' ||
          attachmentType == 'voiceRecording';

      final generatedFileName = shouldUsePrefixConvention
          ? _generatePrefixedFileName(
              message,
              attachmentType,
              attachment['mime_type'] as String?,
            )
          : fileName;

      // Sanitize the filename
      final sanitizedFileName = generatedFileName.replaceAll(
        RegExp(r'[<>:"/\\|?*]'),
        '_',
      );
      _logger.d(
        'Filename: $fileName, final: $sanitizedFileName, type: $attachmentType, usePrefix: $shouldUsePrefixConvention',
      );

      // Get downloads directory
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        _logger.e('Downloads directory not available');
        onError?.call(
          'Error',
          'Downloads directory not available on this platform',
        );
        return;
      }

      final filePath = '${downloadsDir.path}/$sanitizedFileName';
      final file = File(filePath);

      // Check if file already exists - skip download if cached
      if (await file.exists()) {
        _logger.i('File already exists in downloads: $filePath');
        await _handleFileReady(sanitizedFileName, filePath);
        return;
      }

      // Download file bytes - handle both base64 data URIs and HTTP URLs
      Uint8List? fileBytes;

      // Handle base64 data URI (e.g., data:application/octet-stream;base64,ABC...)
      if (fileUrl.startsWith('data:') && fileUrl.contains(';base64,')) {
        _logger.d('Processing base64 data URI');
        final parts = fileUrl.split(';base64,');
        if (parts.length == 2) {
          final base64Data = parts[1];
          final padded = _addBase64Padding(base64Data);
          fileBytes = base64Decode(padded);
        }
      }
      // Handle HTTP/HTTPS URL
      else if (fileUrl.startsWith('http://') ||
          fileUrl.startsWith('https://')) {
        _logger.d('Downloading from HTTP URL: $fileUrl');
        try {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(fileUrl));
          final response = await request.close();
          if (response.statusCode == 200) {
            fileBytes ??= Uint8List.fromList(
              await response.expand((e) => e).toList(),
            );
          } else {
            _logger.e('Failed to download file: HTTP ${response.statusCode}');
          }
          httpClient.close();
        } catch (e) {
          _logger.e('Error downloading from HTTP URL: $e');
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        _logger.e('Failed to extract file bytes from attachment');
        onError?.call('Error', 'Failed to process file data');
        return;
      }

      // Write file to downloads directory
      await file.writeAsBytes(fileBytes);
      _logger.i('File downloaded and saved to: $filePath');

      // Notify about file ready
      await _handleFileReady(sanitizedFileName, filePath);
    } catch (e) {
      _logger.e('Error downloading file: $e');
      onError?.call('Error', 'Failed to download file: $e');
    }
  }

  /// Generate prefixed filename based on attachment type and message timestamp
  String _generatePrefixedFileName(
    Message message,
    String attachmentType,
    String? mimeType,
  ) {
    // Determine prefix based on attachment type
    final prefix = _getPrefixFromAttachmentType(attachmentType);

    // Get extension from MIME type, or infer from attachment type
    final extension = mimeType != null
        ? _getExtensionFromMimeType(mimeType)
        : _getExtensionFromAttachmentType(attachmentType);

    // Generate timestamp-based unique ID
    final dateString = message.updatedAt ?? message.createdAt;
    final dateTime = dateString != null
        ? DateTime.parse(dateString)
        : DateTime.now();
    final uniqueId = dateTime.millisecondsSinceEpoch.toString();

    return '${prefix}_$uniqueId.$extension';
  }

  /// Get prefix based on attachment type
  String _getPrefixFromAttachmentType(String attachmentType) {
    switch (attachmentType.toLowerCase()) {
      case 'image':
        return 'image';
      case 'video':
        return 'video';
      case 'audio':
        return 'audio';
      case 'voicerecording':
        return 'audio';
      default:
        return 'file';
    }
  }

  /// Get file extension based on attachment type as fallback
  String _getExtensionFromAttachmentType(String attachmentType) {
    switch (attachmentType.toLowerCase()) {
      case 'image':
        return 'jpg';
      case 'video':
        return 'mp4';
      case 'audio':
      case 'voicerecording':
        return 'ogg';
      default:
        return 'bin';
    }
  }

  /// Add padding to base64 string if needed for proper decoding
  String _addBase64Padding(String base64String) {
    final padLength = base64String.length % 4;
    if (padLength != 0) {
      return base64String + ('=' * (4 - padLength));
    }
    return base64String;
  }

  /// Get file extension from MIME type
  String _getExtensionFromMimeType(String? mimeType) {
    if (mimeType == null) return 'bin';

    final mimeTypeMap = {
      // Images
      'image/jpeg': 'jpg',
      'image/jpg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
      'image/bmp': 'bmp',
      'image/tiff': 'tiff',
      'image/svg+xml': 'svg',
      // Videos
      'video/mp4': 'mp4',
      'video/mpeg': 'mpeg',
      'video/quicktime': 'mov',
      'video/x-msvideo': 'avi',
      'video/x-matroska': 'mkv',
      'video/webm': 'webm',
      // Audio
      'audio/mpeg': 'mp3',
      'audio/mp4': 'm4a',
      'audio/ogg': 'ogg',
      'audio/wav': 'wav',
      'audio/aac': 'aac',
      'audio/flac': 'flac',
      // Documents
      'application/pdf': 'pdf',
      'application/msword': 'doc',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
          'docx',
      'application/vnd.ms-excel': 'xls',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
          'xlsx',
      'application/vnd.ms-powerpoint': 'ppt',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation':
          'pptx',
      'text/plain': 'txt',
      'text/csv': 'csv',
      'application/json': 'json',
      'application/zip': 'zip',
      'application/x-rar-compressed': 'rar',
    };

    return mimeTypeMap[mimeType] ?? 'bin';
  }

  Future<void> _handleFileReady(String fileName, String filePath) async {
    // Ask app if it wants to open the file
    final shouldOpen =
        await onFileDownloaded?.call(fileName, filePath) ?? false;

    if (shouldOpen) {
      await openFileWithSystem(filePath);
    }
  }

  Future<void> openFileWithSystem(String filePath) async {
    try {
      _logger.i('Opening file with system player: $filePath');
      final result = await OpenFile.open(filePath);
      if (result.type == ResultType.error) {
        _logger.e('Error opening file: ${result.message}');
        onError?.call('Error', 'Could not open file');
      } else {
        _logger.i(
          'File opened successfully with system player: ${result.type}, message: ${result.message}',
        );
      }
    } catch (e) {
      _logger.e('Error opening file with system: $e');
      onError?.call('Error', 'Could not open file: $e');
    }
  }
}
