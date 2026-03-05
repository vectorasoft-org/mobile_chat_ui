import 'package:image_picker/image_picker.dart';

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
      id: json['id'] ?? '',
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

class UploadFileResponse {
  final String fileUrl;

  UploadFileResponse({
    required this.fileUrl,
  });
}
