import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../config/chat_logger.dart';
import '../config/chat_theme.dart';
import '../config/chat_theme_provider.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final String title;
  final ChatLogger logger;
  final VoidCallback onClose;
  final void Function(String videoUrl)? onOpenWithSystem;
  final Future<void> Function(String videoUrl)? onDownload;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.title,
    required this.logger,
    required this.onClose,
    this.onOpenWithSystem,
    this.onDownload,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late VideoPlayerController _controller;
  late AnimationController _controlsAnimation;
  Timer? _hideControlsTimer;
  bool _isInitializing = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isSeeking = false;
  bool _controlsVisible = true;
  late final ChatLogger _logger;

  @override
  void initState() {
    super.initState();
    _logger = widget.logger;

    _controlsAnimation = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _logger.i('Initializing video: ${widget.videoUrl}');
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller.initialize();

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
        _totalDuration = _controller.value.duration;
      });

      _setupListeners();
      _showControls();
    } catch (e) {
      _logger.e('Error initializing video: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _setupListeners() {
    _controller.addListener(() {
      if (!mounted) return;

      setState(() {
        _isPlaying = _controller.value.isPlaying;
        if (!_isSeeking) {
          _currentPosition = _controller.value.position;
        }
        _totalDuration = _controller.value.duration;
      });

      if (_isPlaying) {
        _hideControlsTimer?.cancel();
        _startHideControlsTimer();
      }
    });
  }

  void _showControls() {
    _controlsVisible = true;
    _controlsAnimation.forward();
    _startHideControlsTimer();
  }

  void _hideControls() {
    _controlsVisible = false;
    _controlsAnimation.reverse();
  }

  void _toggleControls() {
    // Only toggle if not tapping on the play button
    if (_controlsAnimation.isCompleted) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (_isPlaying && mounted) {
        _hideControls();
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _seek(Duration position) async {
    try {
      await _controller.seekTo(position);
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      _logger.e('Error seeking video: $e');
    }
  }

  void _skipBackward() {
    final currentMs = _currentPosition.inMilliseconds;
    final skipMs = 10 * 1000; // 10 seconds
    final newMs = (currentMs - skipMs).clamp(0, _totalDuration.inMilliseconds);
    _seek(Duration(milliseconds: newMs));
  }

  void _skipForward() {
    final currentMs = _currentPosition.inMilliseconds;
    final skipMs = 10 * 1000; // 10 seconds
    final newMs = (currentMs + skipMs).clamp(0, _totalDuration.inMilliseconds);
    _seek(Duration(milliseconds: newMs));
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _controller.pause();
      } else {
        await _controller.play();
      }
    } catch (e) {
      _logger.e('Error toggling playback: $e');
    }
  }

  void _handleTap(TapDownDetails details) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final tapPosition = details.globalPosition.dx;
    final tapY = details.globalPosition.dy;
    final leftThird = screenWidth / 3;
    final rightThird = screenWidth - leftThird;
    final topBlockedHeight = max(kToolbarHeight + 24.h, screenHeight * 0.16);
    final bottomBlockedHeight = max(120.h, screenHeight * 0.18);
    final isTopControlZone = tapY < topBlockedHeight;
    final isBottomControlZone = tapY > (screenHeight - bottomBlockedHeight);

    if (isTopControlZone || isBottomControlZone) {
      return;
    }

    // Double-tap on video area
    if (tapPosition < leftThird) {
      _skipBackward();
    } else if (tapPosition > rightThird) {
      _skipForward();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _controlsAnimation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final topBlockedHeight = max(kToolbarHeight + 24.h, screenHeight * 0.16);
    final bottomBlockedHeight = max(120.h, screenHeight * 0.18);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player background
        Container(
          color: theme.videoControlBackground,
          child: _isInitializing
              ? Center(
                  child: CircularProgressIndicator(
                    color: theme.videoControlIcon,
                  ),
                )
              : _hasError
              ? _buildErrorWidget(theme)
              : Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),
        ),

        Positioned.fill(
          top: topBlockedHeight,
          bottom: bottomBlockedHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onDoubleTapDown: _handleTap,
          ),
        ),

        // Controls overlay
        if (!_isInitializing)
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: FadeTransition(
              opacity: _controlsAnimation,
              child: Stack(
                children: [
                  IgnorePointer(
                    ignoring: true,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.videoOverlay.withValues(alpha: 0.35),
                            Colors.transparent,
                            theme.videoOverlay.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 8.h,
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: widget.onClose,
                              child: Padding(
                                padding: EdgeInsets.all(8.w),
                                child: Icon(
                                  Icons.arrow_back,
                                  color: theme.videoControlIcon,
                                  size: 24.w,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.w),
                                child: Text(
                                  widget.title,
                                  style: TextStyle(
                                    color: theme.videoControlIcon,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              color: theme.recordMeterBackground,
                              onSelected: (value) async {
                                if (value == 'download' &&
                                    widget.onDownload != null) {
                                  await widget.onDownload!(widget.videoUrl);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem<String>(
                                  value: 'download',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.download,
                                        color: theme.textPrimary,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Download',
                                        style: TextStyle(
                                          color: theme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              child: Padding(
                                padding: EdgeInsets.all(8.w),
                                child: Icon(
                                  Icons.more_vert,
                                  color: theme.videoControlIcon,
                                  size: 22.w,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: _togglePlayPause,
                      child: Container(
                        width: 80.w,
                        height: 80.w,
                        decoration: BoxDecoration(
                          color: theme.videoControlBackground.withValues(
                            alpha: 0.55,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 46.w,
                          color: theme.videoControlIcon,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 8.h,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3.h,
                                thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 5.w,
                                  elevation: 0,
                                ),
                                overlayShape: RoundSliderOverlayShape(
                                  overlayRadius: 10.w,
                                ),
                                activeTrackColor: theme.videoProgressBar,
                                inactiveTrackColor: theme.videoProgressTrack,
                                thumbColor: theme.videoProgressBar,
                              ),
                              child: Slider(
                                value: _currentPosition.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                      0,
                                      _totalDuration.inMilliseconds.toDouble(),
                                    ),
                                max: max(
                                  1,
                                  _totalDuration.inMilliseconds,
                                ).toDouble(),
                                onChanged: (value) {
                                  setState(() {
                                    _isSeeking = true;
                                    _currentPosition = Duration(
                                      milliseconds: value.toInt(),
                                    );
                                  });
                                },
                                onChangeEnd: (value) {
                                  _seek(Duration(milliseconds: value.toInt()));
                                  setState(() {
                                    _isSeeking = false;
                                  });
                                },
                              ),
                            ),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _togglePlayPause,
                                  child: Padding(
                                    padding: EdgeInsets.all(8.w),
                                    child: Icon(
                                      _isPlaying
                                          ? Icons.pause_circle_filled
                                          : Icons.play_circle_filled,
                                      color: theme.videoControlIcon,
                                      size: 30.w,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}',
                                  style: TextStyle(
                                    color: theme.videoControlIcon,
                                    fontSize: 12.sp,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {},
                                  child: Padding(
                                    padding: EdgeInsets.all(8.w),
                                    child: Icon(
                                      Icons.fullscreen,
                                      color: theme.videoControlIcon,
                                      size: 22.w,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorWidget(ChatTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 60.w,
            color: theme.videoControlIcon.withValues(alpha: 0.7),
          ),
          SizedBox(height: 16.h),
          Text(
            'Error playing video',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.videoControlIcon.withValues(alpha: 0.7),
              fontSize: 16.sp,
            ),
          ),
          if (_errorMessage != null) ...[
            SizedBox(height: 8.h),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.videoControlIcon.withValues(alpha: 0.54),
                fontSize: 12.sp,
              ),
            ),
          ],
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: widget.onOpenWithSystem != null
                ? () => widget.onOpenWithSystem!(widget.videoUrl)
                : null,
            child: const Text('Open with System Player'),
          ),
        ],
      ),
    );
  }
}
