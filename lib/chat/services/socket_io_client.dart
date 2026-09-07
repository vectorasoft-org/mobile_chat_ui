import 'package:vs_chat_flutter/chat/config/chat_config.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vs_chat_flutter/chat/models.dart';
import 'package:vs_chat_flutter/chat/services/chat_reactive_adapter.dart';
import 'package:vs_chat_flutter/chat/services/chat_service.dart';

class StreamChatSocketIoClient {
  final ChatConfig config;
  IO.Socket? _socket;

  void Function(Message)? onNewMessage;
  void Function(List<String>)? onDeletedMessages;

  StreamChatSocketIoClient({
    required this.config,
    this.onNewMessage,
    this.onDeletedMessages,
  });

  Future<void> initialize({
    required String token,
  }) async {
    final currentSocket = _socket;
    if (currentSocket != null) {
      config.logger.w("Found old socket");
      currentSocket.dispose();
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
          .enableForceNew()
          .build(),
    );
    config.logger.i(
      "StreamChatSocketIoClient initialized with socketBaseUrl: ${config.socketBaseUrl}",
    );

    _socket!.on('new-message', _handleNewMessage);
    _socket!.on('deleted-message', _handleDeletedMessages);
    _socket!.on('ping', (_) => config.logger.d("socket ping"));
    _socket!.on('pong', (_) => config.logger.d("socket pong"));
    _socket!.connect();
    config.logger.d("[socket] finished connecting");
  }

  void dispose() {
    _socket?.disconnect().clearListeners();
  }

  void _handleNewMessage(dynamic ackRes) {
    final newMessage = Message.fromStreamChatJson(ackRes);
    onNewMessage?.call(newMessage);
  }

  void _handleDeletedMessages(dynamic ackRes) {
    onDeletedMessages?.call(ackRes['message_ids'] ?? []);
  }

  Future<void> joinChannel(String channelId) async {
    if (_socket == null) {
      throw Exception("socketClient is not initialized");
    }
    final data = await _socket!
        .emitWithAckAsync(
          "join-channel",
          [
            channelId,
          ],
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw Exception("Could not join channel in time");
          },
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
        'Failed to fetch messages: ${data['status_code']} ${data['message']} ${data['data']}',
      );
    } else {
      final messagesJson = data['data']! as List<dynamic>;
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

  Future<Map<String, dynamic>> getChannelDetails() async {
    if (_socket == null) {
      throw Exception("socketClient is not initialized");
    }
    final data = await _socket!.emitWithAckAsync("channel-details", null);
    if (data['status_code'] != 200) {
      throw Exception(
        'Failed to get channel details: $data ${data['status_code']} ${data['message']}',
      );
    } else {
      return data;
    }
  }

  Future<Map<String, dynamic>> deleteMessages({
    required List<String> messageIds,
  }) async {
    if (_socket == null) {
      throw Exception("socketClient is not initialized");
    }
    final data = await _socket!.emitWithAckAsync("delete-messages", [
      messageIds,
    ]);
    if (data['status_code'] != 200) {
      throw Exception(
        "Failed to delete messages: ${data['status_code']} ${data['message']}",
      );
    } else {
      return data;
    }
  }
}
