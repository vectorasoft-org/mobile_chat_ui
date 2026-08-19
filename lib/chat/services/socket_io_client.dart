import 'package:vs_chat_flutter/chat/config/chat_config.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vs_chat_flutter/chat/models.dart';
import 'package:vs_chat_flutter/chat/services/chat_service.dart';

class StreamChatSocketIoClient {
  final ChatConfig config;
  IO.Socket? _socket;

  StreamChatSocketIoClient({required this.config});

  Future<void> initialize({
    required String token,
  }) async {
    final currentSocket = _socket;
    if (currentSocket != null) {
      currentSocket.destroy();
    }
    _socket = IO.io(
      config.socketBaseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({
            "api_key": config.apiKey,
            "token": token,
          })
          .build(),
    );
    config.logger.i(
      "StreamChatSocketIoClient initialized with socketBaseUrl: ${config.socketBaseUrl}",
    );

    _socket!.connect();
  }

  Future<void> joinChannel(String channelId) async {
    if (_socket == null) {
      throw Exception("socketClient is not initialized");
    }
    final data = await _socket!.emitWithAckAsync(
      "join-channel",
      [
        channelId,
      ],
    );
    if (data['status_code'] != 200) {
      throw Exception(
        "Failed to join channel `$channelId`: ${data['status_code']} ${data['message']}",
      );
    } else {
      config.logger.d("Connected to channel `$channelId`");
    }
  }

  Future<List<Message>> getMessages({
    int limit = 20,
    MessageFilter? filter,
  }) async {
    if (_socket == null) {
      throw Exception("socketClient is not initialized");
    }
    final data = await _socket!.emitWithAckAsync("replay-history", {
      "refMessageOpt": ?filter?.refMessageOpt,
      "refMessageId": ?filter?.refMessageId,
    });
    if (data['status_code'] != 200) {
      throw Exception(
        'Failed to fetch messages: ${data['status_code']} ${data['message']}',
      );
    } else {
      final messagesJson = data['data']! as List<Map<String, dynamic>>;
      final messages = messagesJson
          .map((js) => Message.fromStreamChatJson(js))
          .toList();
      return messages;
    }
  }

  Future<Map<String, dynamic>> sendMessage({
    String? text,
    List<Map<String, dynamic>>? attachments,
  }) async {
    if (_socket == null) {
      throw Exception("socketClient is not initialized");
    }
    final metadata = {};
    if (attachments != null && attachments.isNotEmpty) {
      metadata['attachments'] = attachments;
    }
    final data = await _socket!.emitWithAckAsync("send-message", {
      "text": text,
      "metadata": metadata,
    });
    if (data['status_code'] != 201) {
      throw Exception(
        'Failed to send message: ${data['status_code']} ${data['message']}',
      );
    } else {
      return data;
    }
  }
}
