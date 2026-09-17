import 'dart:convert';
import 'package:dio/dio.dart';
import '../config/chat_config.dart';
import '../models.dart';

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

  /// Builds the common request headers.
  ///
  /// The backend proxies auth to the upstream chat service, so clients do not
  /// need to send `x-api-key`/`x-jwt-secret`. Only the optional
  /// `Authorization: Bearer` token from the host application is forwarded.
  Map<String, String> _baseHeaders() => config.httpAuthHeaders();

  /// Logs a failed HTTP response with as much diagnostic detail as possible:
  /// status code, status message and the response body (which usually contains
  /// the server's validation/error explanation).
  Exception _logAndThrowFailure(
    String operation,
    Response<dynamic> response,
  ) {
    final status = response.statusCode;
    final statusMessage = response.statusMessage;
    final body = response.data is String
        ? response.data as String
        : (response.data?.toString() ?? '<empty body>');

    config.logger.e(
      '$operation failed — statusCode: $status, statusMessage: $statusMessage, '
      'response body: $body',
    );

    return Exception(
      '$operation failed: $status $statusMessage. Body: $body',
    );
  }

  /// Logs a DioException (network/timeout/cancellation) with its details.
  void _logDioError(String operation, DioException e) {
    final response = e.response;
    config.logger.e(
      '$operation DioException — type: ${e.type}, message: ${e.message}, '
      'status: ${response?.statusCode}, '
      'body: ${response?.data ?? '<no response body>'}',
      error: e,
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
          headers: _baseHeaders(),
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
        throw _logAndThrowFailure('Fetch messages', response);
      }
    } on DioException catch (e) {
      _logDioError('Fetch messages', e);
      rethrow;
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
          headers: _baseHeaders(),
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
        throw _logAndThrowFailure('Download file from $fileUrl', response);
      }
    } on DioException catch (e) {
      _logDioError('Download file from URL', e);
      rethrow;
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
  }) async {
    try {
      config.logger.i(
        'HTTP POST /chat/resource for channel: $channelId',
      );

      final formData = FormData.fromMap({
        'channel_id': channelId,
        // 'user_id': userId,
        'file': await MultipartFile.fromFile(filePath),
      });

      config.logger.d('Uploading image file: $filePath');

      final response = await _dio.post(
        // '/server/chat/upload-image',
        '/chat/resource',
        data: formData,
        options: Options(
          headers: _baseHeaders(),
        ),
      );

      config.logger.i('HTTP upload response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('Image uploaded successfully');
        // The payload (key, full_path, namespace) lives under data.object.
        final data = jsonData['data'] as Map<String, dynamic>?;
        final object = data?['object'] as Map<String, dynamic>?;
        return object ?? jsonData as Map<String, dynamic>;
      } else {
        throw _logAndThrowFailure('Upload image ($filePath)', response);
      }
    } on DioException catch (e) {
      _logDioError('Upload image', e);
      rethrow;
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
  }) async {
    try {
      config.logger.i(
        'HTTP POST /server/chat/upload-file for channel: $channelId',
      );

      final formData = FormData.fromMap({
        'channel_id': channelId,
        // 'user_id': userId,
        'file': await MultipartFile.fromFile(filePath),
      });

      config.logger.d('Uploading file: $filePath');

      final response = await _dio.post(
        "/chat/resource",
        data: formData,
        options: Options(
          headers: _baseHeaders(),
        ),
      );

      config.logger.i('HTTP upload response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('File uploaded successfully');
        // The payload (key, full_path, namespace) lives under data.object.
        final data = jsonData['data'] as Map<String, dynamic>?;
        final object = data?['object'] as Map<String, dynamic>?;
        return object ?? jsonData as Map<String, dynamic>;
      } else {
        throw _logAndThrowFailure('Upload file ($filePath)', response);
      }
    } on DioException catch (e) {
      _logDioError('Upload file', e);
      rethrow;
    } catch (e) {
      config.logger.e('Error uploading file', error: e);
      rethrow;
    }
  }

  /// Upload binary data to the chat API without writing to a temp file.
  /// Sends multipart form data to /chat/upload-file endpoint.
  /// Returns response with uploaded file URL.
  Future<Map<String, dynamic>> uploadFileBytes({
    required String channelId,
    required String userId,
    required String fileName,
    required List<int> bytes,
  }) async {
    try {
      config.logger.i(
        'HTTP POST /chat/resource (bytes) for channel: $channelId',
      );

      final formData = FormData.fromMap({
        'channel_id': channelId,
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
        ),
      });

      config.logger.d(
        'Uploading bytes file: $fileName (${bytes.length} bytes)',
      );

      final response = await _dio.post(
        "/chat/resource",
        data: formData,
        options: Options(
          headers: _baseHeaders(),
        ),
      );

      config.logger.i('HTTP upload response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        config.logger.d('Bytes file uploaded successfully');
        // The payload (key, full_path, namespace) lives under data.object.
        final data = jsonData['data'] as Map<String, dynamic>?;
        final object = data?['object'] as Map<String, dynamic>?;
        return object ?? jsonData as Map<String, dynamic>;
      } else {
        throw _logAndThrowFailure(
          'Upload bytes file ($fileName, ${bytes.length} bytes)',
          response,
        );
      }
    } on DioException catch (e) {
      _logDioError('Upload bytes file', e);
      rethrow;
    } catch (e) {
      config.logger.e('Error uploading bytes file', error: e);
      rethrow;
    }
  }

  /// Create a channel on the chat API.
  ///
  /// Uses the bearer token from [ChatConfig.httpClientApiKey]. Returns the
  /// created channel id on success (HTTP 201).
  Future<String> createChannel({
    required ChannelType channelType,
  }) async {
    try {
      config.logger.i(
        'HTTP POST /chat/create-channel with type: ${channelType.toJson()}',
      );

      final body = {
        'channel_type': channelType.toJson(),
      };

      config.logger.d('Request body: $body');

      final response = await _dio.post(
        '/chat/create-channel',
        data: body,
        options: Options(
          headers: _baseHeaders(),
        ),
      );

      config.logger.i('HTTP response status: ${response.statusCode}');

      if (response.statusCode == 201) {
        final jsonData = response.data is String
            ? jsonDecode(response.data)
            : response.data;

        final data = jsonData['data'] as Map<String, dynamic>?;
        final channelId = data?['channel_id'] as String?;
        if (channelId == null || channelId.isEmpty) {
          throw Exception('Create channel response missing channel_id');
        }

        config.logger.d('Channel created successfully: $channelId');
        return channelId;
      } else {
        throw Exception(
          'Failed to create channel: ${response.statusCode} ${response.statusMessage}|${response.data}',
        );
      }
    } on DioException catch (e) {
      config.logger.e("Failed to create channel", error: e.response?.data);
      rethrow;
    } catch (e) {
      config.logger.e('Error creating channel', error: e);
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
          headers: _baseHeaders(),
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
        throw _logAndThrowFailure(
          'Get channel details ($channelId)',
          response,
        );
      }
    } on DioException catch (e) {
      _logDioError('Get channel details', e);
      rethrow;
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
          headers: _baseHeaders(),
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
        throw _logAndThrowFailure('Send message', response);
      }
    } on DioException catch (e) {
      _logDioError('Send message', e);
      rethrow;
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
          headers: _baseHeaders(),
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
        throw _logAndThrowFailure('Get signed token for $userId', response);
      }
    } on DioException catch (e) {
      _logDioError('Get signed token', e);
      rethrow;
    } catch (e) {
      config.logger.e('Error getting signed token', error: e);
      rethrow;
    }
  }
}
