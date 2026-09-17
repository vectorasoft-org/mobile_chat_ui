import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/video_player_widget.dart';
import '../config/chat_config.dart';
import '../config/chat_logger.dart';

class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final String title;
  final ChatLogger logger;
  final ChatConfig? chatConfig;
  final VoidCallback Function(String videoUrl)? onOpenWithSystem;

  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.title,
    required this.logger,
    this.chatConfig,
    this.onOpenWithSystem,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final ChatLogger _logger;

  @override
  void initState() {
    super.initState();
    _logger = widget.logger;
    // Hide status bar and lock to landscape during fullscreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  String _safeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  String _inferExtension(String url) {
    final parsed = Uri.tryParse(url);
    final path = parsed?.path ?? '';
    if (path.contains('.')) {
      final ext = path.split('.').last.toLowerCase();
      if (ext.length <= 5) {
        return ext;
      }
    }
    return 'mp4';
  }

  Future<void> _handleDownloadVideo(String videoUrl) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final ext = _inferExtension(videoUrl);
      final rawTitle = widget.title.isNotEmpty ? widget.title : 'video';
      final fileName = '${_safeFileName(rawTitle)}.$ext';
      final filePath = '${docsDir.path}/$fileName';

      _logger.i('Downloading video to: $filePath');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading video...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      await Dio().download(
        videoUrl,
        filePath,
        options: Options(
          headers: widget.chatConfig?.httpAuthHeaders() ?? const {},
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded: $fileName'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              OpenFile.open(filePath);
            },
          ),
        ),
      );
    } catch (e) {
      _logger.e('Error downloading video: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    // Restore normal UI and orientation
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _handleOpenWithSystem(String videoUrl) {
    _openVideoWithSystem(videoUrl);
  }

  Future<void> _openVideoWithSystem(String videoUrl) async {
    try {
      _logger.i('Opening video with system player: $videoUrl');
      await OpenFile.open(videoUrl);
    } catch (e) {
      _logger.e('Error opening file with system player: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open video: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: VideoPlayerWidget(
            videoUrl: widget.videoUrl,
            thumbnailUrl: widget.thumbnailUrl,
            title: widget.title,
            logger: _logger,
            chatConfig: widget.chatConfig,
            onClose: () => Navigator.of(context).pop(),
            onOpenWithSystem: _handleOpenWithSystem,
            onDownload: _handleDownloadVideo,
          ),
        ),
      ),
    );
  }
}
