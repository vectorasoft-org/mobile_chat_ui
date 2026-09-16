import 'package:image_picker/image_picker.dart';

/// Discriminated union describing the type of channel to create.
/// Mirrors the `channel_type` field in the create-channel API contract.
sealed class ChannelType {
  const ChannelType();

  /// Serializes this channel type to the API's `channel_type` JSON shape.
  Map<String, dynamic> toJson();
}

/// A support channel: `{ "type": "support" }`.
class SupportChannelType extends ChannelType {
  const SupportChannelType();

  @override
  Map<String, dynamic> toJson() => {'type': 'support'};
}

/// A package channel: `{ "type": "package", "package_id": <id> }`.
class PackageChannelType extends ChannelType {
  final int packageId;

  const PackageChannelType(this.packageId);

  @override
  Map<String, dynamic> toJson() => {'type': 'package', 'package_id': packageId};
}

class Message {
  final String id;
  final String sender;
  final String? text;
  final List<Map<String, dynamic>>? attachments;
  final bool isSending;
  final String? createdAt;
  final String? updatedAt;
  final bool isDeleted;

  Message({
    required this.id,
    required this.sender,
    this.text,
    this.attachments,
    this.isSending = false,
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
  });

  /// Factory constructor to parse Stream Chat API response format
  factory Message.fromStreamChatJson(Map<String, dynamic> json) {
    // Try multiple fields for user ID: official_code, user_id, then user.id
    final userId =
        json['official_code'] as String? ??
        json['author_id'] as String? ??
        json['user_id'] as String? ??
        json['user']?['id'] as String? ??
        'unknown';
    final messageText = json['text'] ?? '';
    final attachmentsData = json['attachments'] as List?;
    final deletedAt = json['deleted_at'];
    final isDeleted = deletedAt != null || (json['deleted'] as bool? ?? false);

    List<Map<String, dynamic>>? attachments;
    if (attachmentsData != null && attachmentsData.isNotEmpty) {
      attachments = attachmentsData.cast<Map<String, dynamic>>();
    }

    return Message(
      id: json['id'] ?? json['message_id'] ?? '',
      sender: userId,
      text: messageText.isEmpty ? null : messageText,
      attachments: attachments,
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      isDeleted: isDeleted,
    );
  }
}

class AttachmentFile {
  final String type;
  final XFile file;
  final String mimeType;

  AttachmentFile({
    required this.type,
    required this.file,
    required this.mimeType,
  });
}

/// A single image or video to be sent as part of a media message.
/// Multiple of these are grouped into one message with multiple attachments.
class MediaAttachment {
  final XFile file;
  final bool isVideo;
  final int imageWidth;
  final int imageHeight;

  MediaAttachment({
    required this.file,
    required this.isVideo,
    this.imageWidth = 1080,
    this.imageHeight = 1080,
  });
}

class UploadFileResponse {
  final String fileUrl;

  UploadFileResponse({
    required this.fileUrl,
  });
}
