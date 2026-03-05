import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models.dart';

class AttachmentMenuHandler {
  final BuildContext context;
  final Function(Message, Map<String, dynamic>, String) onVideoPlay;
  final Function(Message, Map<String, dynamic>) onFileDownload;

  AttachmentMenuHandler({
    required this.context,
    required this.onVideoPlay,
    required this.onFileDownload,
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
            'Download',
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
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
            'Play Video',
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
            'Download',
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
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
            'Download',
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
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
            'Download',
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
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
            'Download',
            style: TextStyle(fontSize: 16.sp),
          ),
          onTap: () {
            Navigator.pop(context);
            onFileDownload(message, attachment);
          },
        ),
      ],
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
