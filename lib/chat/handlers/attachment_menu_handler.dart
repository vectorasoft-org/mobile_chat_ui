import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models.dart';
import '../services/chat_localizations.dart';

class AttachmentMenuHandler {
  final BuildContext context;
  final Function(Message, Map<String, dynamic>, String) onVideoPlay;
  final Function(Message, Map<String, dynamic>) onFileDownload;
  final Function(Message, Map<String, dynamic>) onOpenLocation;
  final Function(Message) onDelete;

  AttachmentMenuHandler({
    required this.context,
    required this.onVideoPlay,
    required this.onFileDownload,
    required this.onOpenLocation,
    required this.onDelete,
  });

  void showImageAttachmentMenu(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) {
    _showMenu(
      fileName,
      [
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: Text(
            ChatLocalizations.downloadAttachment(context),
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
        _buildDeleteTile(message),
      ],
    );
  }

  void showVideoAttachmentMenu(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) {
    _showMenu(
      fileName,
      [
        ListTile(
          leading: const Icon(Icons.play_circle_outline),
          title: Text(
            ChatLocalizations.playVideo(context),
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            final videoUrl = attachment['asset_url'] as String?;
            if (videoUrl != null) {
              onVideoPlay(message, attachment, videoUrl);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: Text(
            ChatLocalizations.downloadAttachment(context),
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
        _buildDeleteTile(message),
      ],
    );
  }

  void showVoiceRecordingMenu(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) {
    _showMenu(
      fileName,
      [
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: Text(
            ChatLocalizations.downloadAttachment(context),
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
        _buildDeleteTile(message),
      ],
    );
  }

  void showAudioFileMenu(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) {
    _showMenu(
      fileName,
      [
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: Text(
            ChatLocalizations.downloadAttachment(context),
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
        _buildDeleteTile(message),
      ],
    );
  }

  void showGenericFileMenu(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) {
    _showMenu(
      fileName,
      [
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: Text(
            ChatLocalizations.downloadAttachment(context),
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
        _buildDeleteTile(message),
      ],
    );
  }

  /// Show the menu for a location attachment. A location has no downloadable
  /// file, so it only offers opening the coordinates in a maps app and deleting
  /// the message.
  void showLocationMenu(
    Message message,
    Map<String, dynamic> attachment,
    String fileName,
  ) {
    _showMenu(
      fileName,
      [
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: Text(
            ChatLocalizations.openInMaps(context),
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onOpenLocation(message, attachment);
          },
        ),
        _buildDeleteTile(message),
      ],
    );
  }

  ListTile _buildDeleteTile(Message message) {
    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: Text(
        ChatLocalizations.deleteAttachment(context),
        style: TextStyle(fontSize: 16.sp),
      ),
      onTap: () {
        Navigator.pop(context);
        onDelete(message);
      },
    );
  }

  void _showMenu(String fileName, List<Widget> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(16.r),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...items,
            ],
          ),
        );
      },
    );
  }
}
