import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/theme.dart';

class InAppNotificationManager {
  static OverlayEntry? _currentOverlay;
  static Timer? _dismissTimer;
  static GlobalKey<_NotificationBannerState> _bannerKey = GlobalKey<_NotificationBannerState>();

  static void show({
    required BuildContext context,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    _dismissTimer?.cancel();
    final overlayState = Overlay.of(context);
    
    // If an overlay is already present, animate it out first, then show the new one
    if (_currentOverlay != null) {
      final state = _bannerKey.currentState;
      if (state != null) {
        state.dismiss().then((_) {
          _createAndInsert(overlayState, title, body, onTap);
        });
        return;
      } else {
        _currentOverlay?.remove();
        _currentOverlay = null;
      }
    }

    _createAndInsert(overlayState, title, body, onTap);
  }

  static void _createAndInsert(
    OverlayState overlayState,
    String title,
    String body,
    VoidCallback onTap,
  ) {
    _bannerKey = GlobalKey<_NotificationBannerState>();
    
    _currentOverlay = OverlayEntry(
      builder: (context) {
        return _NotificationBanner(
          key: _bannerKey,
          title: title,
          body: body,
          onTap: () {
            final state = _bannerKey.currentState;
            if (state != null) {
              state.dismiss().then((_) {
                _currentOverlay?.remove();
                _currentOverlay = null;
                onTap();
              });
            } else {
              _currentOverlay?.remove();
              _currentOverlay = null;
              onTap();
            }
          },
          onDismiss: () {
            _currentOverlay?.remove();
            _currentOverlay = null;
          },
        );
      },
    );

    overlayState.insert(_currentOverlay!);

    _dismissTimer = Timer(const Duration(seconds: 4), () {
      final state = _bannerKey.currentState;
      if (state != null) {
        state.dismiss().then((_) {
          _currentOverlay?.remove();
          _currentOverlay = null;
        });
      } else {
        _currentOverlay?.remove();
        _currentOverlay = null;
      }
    });
  }
}

class _NotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationBanner({
    super.key,
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  Future<void> dismiss() async {
    if (_isDismissing) return;
    if (mounted) {
      setState(() {
        _isDismissing = true;
      });
      await _controller.reverse();
    }
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: _offsetAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: widget.onTap,
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta! < -4) {
                    dismiss();
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.85), // slate 800 glass
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.25),
                            child: const Icon(Icons.chat_bubble_outline, color: AppTheme.secondaryTeal, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.body,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white60, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: dismiss,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
