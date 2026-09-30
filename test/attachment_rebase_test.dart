import 'package:flutter_test/flutter_test.dart';
import 'package:vs_chat_flutter/chat/config/chat_config.dart';
import 'package:vs_chat_flutter/chat/config/chat_logger.dart';
import 'package:vs_chat_flutter/chat/config/chat_theme.dart';
import 'package:vs_chat_flutter/chat/storage/impl/memory_storage_adapter.dart';

// An attachment URL is minted by the SENDER's surface and stored on the
// message verbatim. These tests pin the receiver-side rebase: whatever
// surface minted the URL, this config's own /chat/resource/ route serves it.
void main() {
  final config = ChatConfig(
    baseUrl: 'https://dms.example.com/api/merchant/v2',
    apiKey: 'k',
    socketBaseUrl: 'https://chat.example.com',
    theme: ChatTheme.houExpress(),
    logger: ConsoleLogger(),
    storage: MemoryStorageAdapter(),
  );

  const own = 'https://dms.example.com/api/merchant/v2/chat/resource';

  group('rebaseAttachmentUrl', () {
    test('rebases the OTHER app class onto this app', () {
      expect(
        config.rebaseAttachmentUrl(
            'https://dms.example.com/api/driver/v2/chat/resource/77/room-1/photo.jpg'),
        '$own/77/room-1/photo.jpg',
      );
    });

    test('is idempotent on this app\'s own URLs', () {
      expect(
        config.rebaseAttachmentUrl('$own/77/room-1/photo.jpg'),
        '$own/77/room-1/photo.jpg',
      );
    });

    test('rebases a storage public URL and drops its query', () {
      expect(
        config.rebaseAttachmentUrl(
            'https://storage.example.com/resource/77/room-1/voice.m4a?x=1'),
        '$own/77/room-1/voice.m4a',
      );
    });

    test('handles the legacy chat-service root', () {
      expect(
        config.rebaseAttachmentUrl(
            'https://dms.example.com/api/driver/v2/chat/resource/chat-service/room-1/a.png'),
        '$own/chat-service/room-1/a.png',
      );
    });

    test('falls back to object.full_path for unrecognised mints', () {
      expect(
        config.rebaseAttachmentUrl(
            'https://chat.example.com/server/static/abc?signature=s&expires=1',
            {'full_path': '77/room-1/a.png'}),
        '$own/77/room-1/a.png',
      );
    });

    test('passes unknown shapes and data URIs through', () {
      expect(
        config.rebaseAttachmentUrl('https://elsewhere.example.com/x/y.png'),
        'https://elsewhere.example.com/x/y.png',
      );
      expect(config.rebaseAttachmentUrl('data:image/png;base64,AAA'),
          'data:image/png;base64,AAA');
      expect(config.rebaseAttachmentUrl(null), null);
    });
  });

  group('rebaseAttachments', () {
    test('rewrites every url key in place, object only on the primary', () {
      final atts = [
        {
          'type': 'video',
          'asset_url':
              'https://dms.example.com/api/driver/v2/chat/resource/77/r/clip.mp4',
          'thumb_url':
              'https://dms.example.com/api/driver/v2/chat/resource/77/r/clip_thumb.jpg',
          'object': {'full_path': '77/r/clip.mp4'},
        },
        {
          'type': 'image',
          'image_url': 'https://chat.example.com/server/static/abc?signature=s',
          'object': {'full_path': '77/r/pic.png'},
        },
      ];
      config.rebaseAttachments(atts);
      expect(atts[0]['asset_url'], '$own/77/r/clip.mp4');
      expect(atts[0]['thumb_url'], '$own/77/r/clip_thumb.jpg');
      expect(atts[1]['image_url'], '$own/77/r/pic.png');
    });
  });
}
