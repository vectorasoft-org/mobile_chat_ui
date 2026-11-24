import 'package:flutter/foundation.dart';
import 'package:vs_chat_flutter/chat/config/chat_config.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:vs_chat_flutter/chat/models.dart';
import 'package:vs_chat_flutter/chat/services/chat_service.dart';

class StreamChatSocketIoClient {
  final ChatConfig config;
  IO.Socket? _socket;
  String? _firstToken;
  String? _joinedChannel;

  /// SEEN TICKS: the latest moment any OTHER member read the joined room.
  /// The engine says so on join (`channel-reads`) and live (`read-receipt`);
  /// every own message sent up to then shows two ticks. Same rule as the web
  /// widget (vschat.js noteSeen).
  final ValueNotifier<DateTime?> seenAt = ValueNotifier<DateTime?>(null);

  void Function(Message)? onNewMessage;
  void Function(List<String>)? onDeletedMessages;

  /// After a reconnect has re-joined the channel: messages sent while the
  /// socket was down never replay on their own, so the service resyncs.
  void Function()? onReconnected;

  StreamChatSocketIoClient({
    required this.config,
    this.onNewMessage,
    this.onDeletedMessages,
    this.onReconnected,
  });

  Future<void> initialize({
    required String token,
  }) async {
    _firstToken = token;
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
          // A token is spent on use: the first connect uses [token], every
          // reconnect asks the host for a new one (config.tokenProvider).
          .setAuthFn((callback) {
            final first = _firstToken;
            _firstToken = null;
            (first != null
                    ? Future.value(first)
                    : (config.tokenProvider?.call() ?? Future.value(token)))
                .then((t) => callback({"api_key": config.apiKey, "token": t}))
                .catchError((Object e) {
                  config.logger.e("[socket] token refresh failed", error: e);
                });
          })
          .enableForceNew()
          .build(),
    );
    config.logger.i(
      "StreamChatSocketIoClient initialized with socketBaseUrl: ${config.socketBaseUrl}",
    );

    // The server forgets the joined channel with the old connection.
    _socket!.onReconnect((_) {
      final channelId = _joinedChannel;
      if (channelId != null) {
        joinChannel(channelId)
            .then((_) => onReconnected?.call())
            .catchError((_) {});
      }
    });
    _socket!.onConnect((_) => online.value = true);
    _socket!.onDisconnect((_) => online.value = false);
    _socket!.onConnectError((_) => online.value = false);
    _socket!.on('new-message', _handleNewMessage);
    // Plural: the server emits 'deleted-messages' (one event, many ids).
    // The singular name meant mobile never saw a delete.
    _socket!.on('deleted-messages', _handleDeletedMessages);
    _socket!.on('read-receipt', (dynamic p) {
      if (p is Map && p['channel_id']?.toString() == _joinedChannel) {
        _noteSeen(p['user_id'], p['last_read_at']);
      }
    });
    _socket!.on('ping', (_) => config.logger.d("socket ping"));
    _socket!.on('pong', (_) => config.logger.d("socket pong"));
    _socket!.connect();
    config.logger.d("[socket] finished connecting");
  }

  /// Is the transport actually up? The outbox asks this before it decides
  /// whether a message can go now or has to wait for a reconnect.
  bool get connected => _socket?.connected ?? false;

  /// The same answer as a listenable, so the room can show its "no
  /// connection" strip the moment the wire drops - before the user types into
  /// a dead socket, not after.
  final ValueNotifier<bool> online = ValueNotifier<bool>(false);

  void dispose() {
    _socket?.disconnect().clearListeners();
  }

  void _noteSeen(dynamic userId, dynamic at) {
    if (userId == null || userId.toString() == config.resolveUserId()) return;
    final t = DateTime.tryParse(at?.toString() ?? '');
    final had = seenAt.value;
    if (t != null && (had == null || t.isAfter(had))) seenAt.value = t;
  }

  void _handleNewMessage(dynamic ackRes) {
    final newMessage = Message.fromStreamChatJson(ackRes);
    // Attachment URLs are minted by the sender's surface; make them
    // fetchable from THIS app before anything renders or caches them.
    config.rebaseAttachments(newMessage.attachments);
    onNewMessage?.call(newMessage);
  }

  void _handleDeletedMessages(dynamic ackRes) {
    // The payload's List is List<dynamic>; a raw pass-through would throw
    // on the List<String> callback the first time a delete ever arrived.
    final ids = ackRes is Map ? ackRes['message_ids'] : null;
    onDeletedMessages?.call([
      for (final x in (ids is List ? ids : const [])) x.toString(),
    ]);
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
      _joinedChannel = channelId;
      config.logger.d("Connected to channel `$channelId`");
      // An engine without seen ticks never answers: the ticks stay single.
      _socket!.emitWithAck('channel-reads', [], ack: (dynamic res) {
        final reads = res is Map && res['data'] is Map ? res['data']['reads'] : null;
        for (final r in (reads is List ? reads : const [])) {
          if (r is Map) _noteSeen(r['user_id'], r['last_read_at']);
        }
      });
    }
  }

  Future<List<Message>> getMessages({
    int limit = 20,
    MessageFilter? filter,
  }) async {
    if (_socket == null) {
      throw Exception("socketClient is not initialized");
    }
    /* Paging BACKWARDS (id_lt / id_lte) must ask for newest-first: the engine
       orders, then limits, so the default asc + limit returned the OLDEST
       page of the whole room - lazy loading jumped to the start and stopped.
       The page is flipped back to ascending below, as the cache expects. */
    final backwards =
        filter != null && filter.refMessageOpt.startsWith('id_l');
    final data = await _socket!.emitWithAckAsync("replay-history", {
      "limit": limit,
      "refMessageOpt": ?filter?.refMessageOpt,
      "refMessageId": ?filter?.refMessageId,
      if (backwards) "messageOrder": "desc",
    });
    if (data['status_code'] != 200) {
      throw Exception(
        'Failed to fetch messages: ${data['status_code']} ${data['message']} ${data['data']}',
      );
    } else {
      final messagesJson = data['data']! as List<dynamic>;
      var messages = messagesJson
          .map((js) => Message.fromStreamChatJson(js))
          .toList();
      if (backwards) messages = messages.reversed.toList();
      // History rows carry whatever URL the sender's surface minted -
      // rebase each onto this app's own resource route.
      for (final m in messages) {
        config.rebaseAttachments(m.attachments);
      }
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
