import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:just_audio/just_audio.dart';
import '../config/chat_logger.dart';
import '../config/chat_theme_provider.dart';
import '../services/audio_cache_service.dart';
import 'audio_player_controller.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String messageId;
  final String audioUrl;
  final int? durationMilliseconds;
  final bool isSelf;
  final AudioPlayerController? controller;
  final AudioCacheService? cacheService;
  final ChatLogger? logger;

  const AudioPlayerWidget({
    super.key,
    required this.messageId,
    required this.audioUrl,
    this.durationMilliseconds,
    this.isSelf = false,
    this.controller,
    this.cacheService,
    this.logger,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  final GlobalKey _sliderKey = GlobalKey();
  late final AudioPlayerController _controller;
  bool _wasPlayingBeforeDrag = false;
  late final ChatLogger _logger;
  late final AudioCacheService _cacheService;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  Duration? _actualDuration; // Duration obtained from the file itself

  @override
  void initState() {
    super.initState();
    _logger = widget.logger ?? ConsoleLogger();
    _controller = widget.controller ?? AudioPlayerController(logger: _logger);
    _cacheService = widget.cacheService ?? AudioCacheService(logger: _logger);
    _audioPlayer = _controller.player;
    _setupListeners();
  }

  void _setupListeners() {
    _audioPlayer.playerStateStream.listen((state) {
      // Only update if this is the active player
      if (mounted && _controller.currentMessageId == widget.messageId) {
        _logger.i(
          '[AUDIO] ${widget.messageId} - State: ${state.playing}, ProcessingState: ${state.processingState}',
        );
        setState(() {
          _isPlaying = state.playing;
        });
        if (state.processingState == ProcessingState.completed) {
          _logger.i('[AUDIO] ${widget.messageId} - Completed');
          setState(() {
            _isPlaying = false;
          });
        }
      }
    });

    _audioPlayer.positionStream.listen((position) {
      // Only update if this is the active player
      if (mounted && _controller.currentMessageId == widget.messageId) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
  }

  @override
  void didUpdateWidget(AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Audio source updates are handled on user interaction, not on widget update
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        _logger.i('[AUDIO] ${widget.messageId} - Currently playing, pausing');
        await _controller.pause();
      } else {
        // Check if this is a different audio than what's currently playing
        if (_controller.currentMessageId != widget.messageId) {
          _logger.i(
            '[AUDIO] ${widget.messageId} - Different audio, checking cache',
          );

          // Check if already cached
          final isCached = await _cacheService.isCached(widget.audioUrl);

          if (isCached) {
            _logger.i(
              '[AUDIO] ${widget.messageId} - Audio already cached, loading directly',
            );
            try {
              final audioFile = await _cacheService.getAudioFile(
                widget.audioUrl,
                onProgress: (progress) {
                  // Cache hit - progress will be 0->100 instantly
                  _logger.d(
                    '[AUDIO] ${widget.messageId} - Cache hit progress: ${progress.toStringAsFixed(1)}%',
                  );
                },
              );

              await _controller.setAudioSourceFromFile(
                widget.messageId,
                audioFile.path,
              );

              if (mounted) {
                setState(() {
                  _actualDuration = _audioPlayer.duration;
                  _currentPosition = Duration.zero;
                });
              }

              _logger.i(
                '[AUDIO] ${widget.messageId} - Audio loaded from cache, duration: ${_actualDuration?.inMilliseconds}ms',
              );
              await _controller.play();
            } catch (e) {
              _logger.e(
                '[AUDIO] ${widget.messageId} - Error loading cached audio: $e',
                error: e,
              );
            }
          } else {
            _logger.i(
              '[AUDIO] ${widget.messageId} - Audio not cached, starting download',
            );

            // Download audio to cache if needed
            if (!_isDownloading) {
              if (mounted) {
                setState(() {
                  _isDownloading = true;
                  _downloadProgress = 0.0;
                });
              }

              // Download in background without blocking
              _cacheService
                  .getAudioFile(
                    widget.audioUrl,
                    onProgress: (progress) {
                      if (mounted) {
                        setState(() {
                          _downloadProgress = progress;
                        });
                        _logger.d(
                          '[AUDIO] ${widget.messageId} - Download progress: ${progress.toStringAsFixed(1)}%',
                        );
                      }
                    },
                  )
                  .then((audioFile) {
                    // When download completes, load the audio
                    _logger.i(
                      '[AUDIO] ${widget.messageId} - Download complete, loading audio',
                    );
                    return _controller.setAudioSourceFromFile(
                      widget.messageId,
                      audioFile.path,
                    );
                  })
                  .then((_) {
                    // Update duration and start playing
                    if (mounted) {
                      setState(() {
                        _actualDuration = _audioPlayer.duration;
                        _currentPosition = Duration.zero;
                        _isDownloading = false;
                      });
                    }
                    _logger.i(
                      '[AUDIO] ${widget.messageId} - Audio loaded, duration: ${_actualDuration?.inMilliseconds}ms, starting playback',
                    );
                    _controller.play();
                  })
                  .catchError((e) {
                    _logger.e(
                      '[AUDIO] ${widget.messageId} - Error loading audio: $e',
                      error: e,
                    );
                    if (mounted) {
                      setState(() {
                        _isDownloading = false;
                      });
                    }
                  });
            }
          }
        } else {
          _logger.i(
            '[AUDIO] ${widget.messageId} - Same audio, checking if at end',
          );
          // Same audio - check if we need to reset to beginning
          final duration = _actualDuration ?? _audioPlayer.duration;
          bool shouldReset = false;

          if (duration != null && duration.inMilliseconds > 0) {
            final currentPos = _audioPlayer.position;
            // Check if we're past the end (with 100ms tolerance)
            shouldReset =
                currentPos >= (duration - const Duration(milliseconds: 100));
            _logger.i(
              '[AUDIO] ${widget.messageId} - Checking if at end: duration=${duration.inMilliseconds}ms, pos=${currentPos.inMilliseconds}ms, shouldReset=$shouldReset',
            );
          } else {
            _logger.i('[AUDIO] ${widget.messageId} - No duration available');
          }

          if (shouldReset) {
            _logger.i('[AUDIO] ${widget.messageId} - Seeking to beginning');
            await _controller.seek(Duration.zero);
          }
          _logger.i('[AUDIO] ${widget.messageId} - Playing');
          await _controller.play();
        }
      }
    } catch (e) {
      _logger.e('[AUDIO] ${widget.messageId} - Error: $e', error: e);
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Cancel any in-flight downloads when widget is disposed
    _cacheService.cancelDownload(widget.audioUrl).catchError((e) {
      _logger.d(
        '[AUDIO] ${widget.messageId} - Error cancelling download on dispose: $e',
      );
    });
    // Don't dispose the shared audio player here - the controller manages it
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    final isActive = _controller.currentMessageId == widget.messageId;
    final hasDuration =
        widget.durationMilliseconds != null && widget.durationMilliseconds! > 0;
    final totalDuration = hasDuration
        ? Duration(milliseconds: widget.durationMilliseconds!)
        : null;

    // Only show actual progress if this player is active
    final displayPosition = isActive ? _currentPosition : Duration.zero;
    final progress = totalDuration != null && totalDuration.inMilliseconds > 0
        ? (displayPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : null;

    return Container(
      width: 300.w,
      height: 70.h,
      decoration: BoxDecoration(
        color: widget.isSelf
            ? theme.audioPlayerSentBackground
            : theme.audioPlayerReceivedBackground,
        borderRadius: BorderRadius.circular(12.r),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      child: Row(
        children: [
          // Play/Pause button or Loading indicator
          GestureDetector(
            onTap: _isDownloading ? null : _togglePlayPause,
            child: Container(
              width: 40.w,
              height: 40.h,
              decoration: BoxDecoration(
                color: widget.isSelf
                    ? Colors.white
                    : theme.audioPlayerIconColor,
                shape: BoxShape.circle,
                border: Border.all(color: theme.borderColor, width: 1.w),
              ),
              child: _isDownloading
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 30.w,
                          height: 30.h,
                          child: CircularProgressIndicator(
                            value: _downloadProgress / 100.0,
                            strokeWidth: 2.w,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.isSelf
                                  ? theme.audioPlayerIconColor
                                  : Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          '${_downloadProgress.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 8.sp,
                            color: widget.isSelf
                                ? theme.audioPlayerIconColor
                                : Colors.white,
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: widget.isSelf
                          ? theme.audioPlayerIconColor
                          : Colors.white,
                      size: 20.sp,
                    ),
            ),
          ),
          SizedBox(width: 8.w),
          // Progress slider (seekable)
          Expanded(
            key: _sliderKey,
            child: GestureDetector(
              onHorizontalDragStart: (details) async {
                _wasPlayingBeforeDrag = _isPlaying;
                // Ensure this audio is loaded when dragging
                if (_controller.currentMessageId != widget.messageId) {
                  await _controller.setAudioSource(
                    widget.messageId,
                    widget.audioUrl,
                  );
                }
                if (_isPlaying) {
                  _controller.pause();
                }
              },
              onHorizontalDragUpdate: (details) {
                // Get the slider's render box from the GlobalKey
                final sliderBox =
                    _sliderKey.currentContext?.findRenderObject() as RenderBox?;
                if (sliderBox != null && totalDuration != null) {
                  final localPosition = sliderBox.globalToLocal(
                    details.globalPosition,
                  );
                  final percentage = (localPosition.dx / sliderBox.size.width)
                      .clamp(0.0, 1.0);
                  final newPosition = Duration(
                    milliseconds: (percentage * totalDuration.inMilliseconds)
                        .toInt(),
                  );
                  _controller.seek(newPosition);
                } else {}
              },
              onHorizontalDragEnd: (details) {
                if (_wasPlayingBeforeDrag) {
                  _controller.play();
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.r),
                child: hasDuration
                    ? LinearProgressIndicator(
                        value: progress,
                        minHeight: 8.h,
                        backgroundColor: theme.audioPlayerProgressTrack,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isSelf
                              ? theme.audioPlayerSentProgressBar
                              : theme.audioPlayerReceivedProgressBar,
                        ),
                      )
                    : LinearProgressIndicator(
                        value: null,
                        minHeight: 8.h,
                        backgroundColor: theme.audioPlayerProgressTrack,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isSelf
                              ? theme.audioPlayerSentProgressBar
                              : theme.audioPlayerReceivedProgressBar,
                        ),
                      ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          // Duration display
          SizedBox(
            width: 40.w,
            child: hasDuration
                ? Text(
                    _formatDuration(totalDuration!),
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      color: widget.isSelf
                          ? theme.audioPlayerSentTextColor
                          : theme.audioPlayerReceivedTextColor,
                      fontFamily: 'Courier',
                    ),
                    textAlign: TextAlign.right,
                  )
                : Text(
                    _formatDuration(displayPosition),
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      color: widget.isSelf
                          ? theme.audioPlayerSentTextColor
                          : theme.audioPlayerReceivedTextColor,
                      fontFamily: 'Courier',
                    ),
                    textAlign: TextAlign.right,
                  ),
          ),
        ],
      ),
    );
  }
}
