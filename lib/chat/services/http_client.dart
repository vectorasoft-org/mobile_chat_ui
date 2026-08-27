import 'dart:convert';
import 'package:dio/dio.dart';
import '../config/chat_config.dart';

class StreamChatHttpClient {
  final ChatConfig config;
  late final Dio _dio;

  StreamChatHttpClient({required this.config}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        validateStatus: (_) => true,
      ),
    );
    config.logger.i(
      'StreamChatHttpClient initialized with baseUrl: ${config.baseUrl}',
    );
  }

  /// Fetch messages from Stream Chat API
  /// Returns the parsed JSON response containing messages array
  Future<Map<String, dynamic>> getMessages({
    required String channelId,
    int limit = 20,
    String? refMessageId,
    String? op,
  }) async {
    try {
      final queryParams = {
        'channel_id': channelId,
        'limit': limit.toString(),
      };

      // Add pagination parameters if provided
      if (refMessageId != null && op != null) {
        queryParams['ref_message_id'] = refMessageId;
        queryParams['op'] = op;
      }

      config.logger.i(
        'HTTP GET /server/chat/history with params: $queryParams',
      );

      final response = await _dio.get(
        '/server/chat/history',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'x-api-key': config.apiKey,
            'Accept': 'application/json',
          },
        ),
      );

      config.logger.i('HTTP response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('Response keys: ${(jsonData as Map).keys.toList()}');

        return jsonData as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to fetch messages: ${response.statusCode} ${response.statusMessage}',
        );
      }
    } catch (e) {
      config.logger.e('HTTP client error', error: e);
      rethrow;
    }
  }

  /// Download file from URL (works with external CDN URLs)
  /// Returns raw bytes of the file
  Future<List<int>> downloadFileFromUrl(String fileUrl) async {
    try {
      config.logger.i('Downloading file from URL: $fileUrl');

      final response = await _dio.get<List<int>>(
        fileUrl,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        config.logger.i(
          'File downloaded successfully: ${response.data?.length ?? 0} bytes',
        );
        return response.data!;
      } else {
        throw Exception(
          'Failed to download file: ${response.statusCode} ${response.statusMessage}',
        );
      }
    } catch (e) {
      config.logger.e('Error downloading file from URL', error: e);
      rethrow;
    }
  }

  /// Upload an image file to the chat API
  /// Sends multipart form data to /chat/upload-image endpoint
  /// Returns response with uploaded image URL
  Future<Map<String, dynamic>> uploadImage({
    required String channelId,
    required String userId,
    required String filePath,
    required List<String> namespace,
    required String key,
  }) async {
    try {
      config.logger.i(
        'HTTP POST /chat/resource for channel: $channelId',
      );

      final formData = FormData.fromMap({
        // 'channel_id': channelId,
        // 'user_id': userId,
        'file': await MultipartFile.fromFile(filePath),
      });

      config.logger.d('Uploading image file: $filePath');

      final uploadPath = [...namespace, key].join("/");

      final response = await _dio.post(
        // '/server/chat/upload-image',
        '/chat/resource/$uploadPath',
        data: formData,
        options: Options(
          headers: {
            'x-api-key': config.apiKey,
          },
        ),
      );

      config.logger.i('HTTP upload response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('Image uploaded successfully');
        return jsonData as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to upload image: ${response.statusCode} ${response.statusMessage}',
        );
      }
    } catch (e) {
      config.logger.e('Error uploading image', error: e);
      rethrow;
    }
  }

  /// Upload a file to the chat API
  /// Sends multipart form data to /chat/upload-file endpoint
  /// Returns response with uploaded file URL (and thumb_url for videos)
  Future<Map<String, dynamic>> uploadFile({
    required String channelId,
    required String userId,
    required String filePath,
    required List<String> namespace,
    required String key,
  }) async {
    try {
      config.logger.i(
        'HTTP POST /server/chat/upload-file for channel: $channelId',
      );

      final formData = FormData.fromMap({
        // 'channel_id': channelId,
        // 'user_id': userId,
        'file': await MultipartFile.fromFile(filePath),
      });

      config.logger.d('Uploading file: $filePath');

      final uploadPath = [...namespace, key].join("/");

      final response = await _dio.post(
        "/chat/resource/$uploadPath",
        data: formData,
        options: Options(
          headers: {
            'x-api-key': config.apiKey,
          },
        ),
      );

      config.logger.i('HTTP upload response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('File uploaded successfully');
        return jsonData as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to upload file: ${response.statusCode} ${response.statusMessage}',
        );
      }
    } catch (e) {
      config.logger.e('Error uploading file', error: e);
      rethrow;
    }
  }

  /// Fetch channel details including name
  Future<Map<String, dynamic>> getChannelDetails({
    required String channelId,
  }) async {
    try {
      config.logger.i(
        'HTTP GET /server/chat/channel-details for channel: $channelId',
      );

      final response = await _dio.get(
        '/server/chat/channel-details',
        queryParameters: {
          'channel_id': channelId,
        },
        options: Options(
          headers: {
            'x-api-key': config.apiKey,
            'Accept': 'application/json',
          },
        ),
      );

      config.logger.i('HTTP response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('Channel details fetched successfully');
        return jsonData as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to get channel details: ${response.statusCode} ${response.statusMessage}',
        );
      }
    } catch (e) {
      config.logger.e('Error fetching channel details', error: e);
      rethrow;
    }
  }

  /// Supports text-only messages or messages with attachments
  /// Attachments are sent in metadata.attachments array
  Future<Map<String, dynamic>> sendMessage({
    required String channelId,
    required String userId,
    String? text,
    List<Map<String, dynamic>>? attachments,
  }) async {
    try {
      config.logger.i(
        'HTTP POST /server/chat/send-message for channel: $channelId',
      );

      // Build metadata with attachments if present
      final metadata = <String, dynamic>{};
      if (attachments != null && attachments.isNotEmpty) {
        metadata['attachments'] = attachments;
        config.logger.d(
          'Adding ${attachments.length} attachment(s) to metadata',
        );
      }

      final body = {
        'channel_id': channelId,
        'user_id': userId,
        'text': text ?? '',
        'message_type': 'text',
        'metadata': metadata,
      };

      config.logger.d('Request body: $body');

      final response = await _dio.post(
        '/server/chat/send-message',
        data: body,
        options: Options(
          headers: {
            'x-api-key': config.apiKey,
            'Accept': 'application/json',
          },
        ),
      );

      config.logger.i('HTTP response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('Message sent successfully');
        return jsonData as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to send message: ${response.statusCode} ${response.statusMessage}',
        );
      }
    } catch (e) {
      config.logger.e('Error sending message', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSignedJwtToken({
    required String userId,
  }) async {
    try {
      config.logger.i('HTTP POST /chat/sign-jwt for user: $userId');

      final body = {
        'user_id': userId,
      };

      config.logger.d('Request body: $body');

      final response = await _dio.post(
        '/chat/sign-jwt',
        data: body,
        options: Options(
          headers: {
            // 'x-api-key': config.apiKey,
            // 'x-api-key': "b8kry8sm9qxm",
            'Accept': 'application/json',
          },
        ),
      );

      config.logger.i('HTTP response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('Got signed token');
        return jsonData as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to get signed token: ${response.statusCode} ${response.statusMessage}',
        );
      }
    } catch (e) {
      config.logger.e('Error getting signed token', error: e);
      rethrow;
    }
  }
}
