import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../config/chat_config.dart';
import '../config/chat_logger.dart';

class AudioCacheService {
  static AudioCacheService? _instance;
  late final ChatLogger _logger;
  final ChatConfig? _config;
  final Dio _dio = Dio();

  // Track active downloads to allow cancellation
  final Map<String, CancelToken> _downloadTokens = {};

  factory AudioCacheService({required ChatLogger logger, ChatConfig? config}) {
    _instance ??= AudioCacheService._internal(logger, config);
    return _instance!;
  }

  AudioCacheService._internal(ChatLogger logger, ChatConfig? config)
    : _logger = logger,
      _config = config;

  /// Get the cache file for an audio URL
  Future<File> _getCacheFile(String audioUrl) async {
    final cacheDir = await getTemporaryDirectory();
    final fileName = _generateCacheName(audioUrl);
    return File('${cacheDir.path}/$fileName');
  }

  /// Generate a deterministic cache file name from URL
  String _generateCacheName(String audioUrl) {
    // Simple hash-based approach - use a portion of the URL
    final hash = audioUrl.hashCode.abs().toString().padLeft(10, '0');
    return 'audio_cache_$hash.m4a';
  }

  /// Check if audio is already cached
  Future<bool> isCached(String audioUrl) async {
    try {
      final file = await _getCacheFile(audioUrl);
      return await file.exists();
    } catch (e) {
      _logger.e('Error checking cache for $audioUrl', error: e);
      return false;
    }
  }

  /// Download audio to cache with progress callback
  Future<File> downloadAudio(
    String audioUrl, {
    required ValueChanged<double> onProgress,
  }) async {
    try {
      final file = await _getCacheFile(audioUrl);

      // If already cached, return immediately
      if (await file.exists()) {
        _logger.i('[AUDIO_CACHE] File already cached: ${file.path}');
        onProgress(100.0);
        return file;
      }

      _logger.i('[AUDIO_CACHE] Starting download: $audioUrl');

      // Create parent directory if needed
      await file.parent.create(recursive: true);

      // Create or reuse cancel token for this URL
      final cancelToken = _downloadTokens[audioUrl] ?? CancelToken();
      _downloadTokens[audioUrl] = cancelToken;

      try {
        // Download with progress
        await _dio.download(
          audioUrl,
          file.path,
          cancelToken: cancelToken,
          options: Options(
            headers: _config?.httpAuthHeaders() ?? const {},
          ),
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = (received / total) * 100;
              onProgress(progress);
              _logger.d(
                '[AUDIO_CACHE] Download progress: ${progress.toStringAsFixed(1)}%',
              );
            }
          },
        );

        _logger.i('[AUDIO_CACHE] Download completed: ${file.path}');
        onProgress(100.0);
        _downloadTokens.remove(audioUrl);
        return file;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          _logger.i('[AUDIO_CACHE] Download cancelled: $audioUrl');
          // Clean up partial file
          if (await file.exists()) {
            await file.delete();
          }
        }
        rethrow;
      }
    } catch (e) {
      _logger.e('[AUDIO_CACHE] Download error for $audioUrl', error: e);
      rethrow;
    }
  }

  /// Get the local file path for an audio (downloads if necessary)
  Future<File> getAudioFile(
    String audioUrl, {
    required ValueChanged<double> onProgress,
  }) async {
    return downloadAudio(audioUrl, onProgress: onProgress);
  }

  /// Cancel download for a specific URL
  Future<void> cancelDownload(String audioUrl) async {
    final cancelToken = _downloadTokens[audioUrl];
    if (cancelToken != null && !cancelToken.isCancelled) {
      _logger.i('[AUDIO_CACHE] Cancelling download: $audioUrl');
      cancelToken.cancel();
      _downloadTokens.remove(audioUrl);
    }
  }

  /// Cancel all active downloads
  Future<void> cancelAllDownloads() async {
    _logger.i('[AUDIO_CACHE] Cancelling all downloads');
    for (final token in _downloadTokens.values) {
      if (!token.isCancelled) {
        token.cancel();
      }
    }
    _downloadTokens.clear();
  }

  /// Clear cache for a specific audio
  Future<void> clearCache(String audioUrl) async {
    try {
      await cancelDownload(audioUrl);
      final file = await _getCacheFile(audioUrl);
      if (await file.exists()) {
        await file.delete();
        _logger.i('[AUDIO_CACHE] Cleared cache: ${file.path}');
      }
    } catch (e) {
      _logger.e('Error clearing cache for $audioUrl', error: e);
    }
  }

  /// Clear all audio cache
  Future<void> clearAllCache() async {
    try {
      await cancelAllDownloads();
      final cacheDir = await getTemporaryDirectory();
      final files = cacheDir.listSync();
      for (final file in files) {
        if (file is File && file.path.contains('audio_cache_')) {
          await file.delete();
        }
      }
      _logger.i('[AUDIO_CACHE] Cleared all audio cache');
    } catch (e) {
      _logger.e('Error clearing all cache', error: e);
    }
  }
}
