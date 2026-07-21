import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/nurse_controller.dart';
import '../theme/nurse_theme.dart';

class NurseAvatar extends StatefulWidget {
  const NurseAvatar({
    super.key,
    required this.state,
    required this.emotion,
    required this.imagePath,
    required this.departmentName,
    this.motionEnabled = true,
  });

  final NurseUiState state;
  final String emotion;
  final String imagePath;
  final String departmentName;
  final bool motionEnabled;

  @override
  State<NurseAvatar> createState() => _NurseAvatarState();
}

class _NurseAvatarState extends State<NurseAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    if (widget.motionEnabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant NurseAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motionEnabled == widget.motionEnabled) return;
    if (widget.motionEnabled) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette =
        Theme.of(context).extension<NursePalette>() ??
        NursePalette.forStyle(NurseVisualStyle.clinicalLight);
    return Semantics(
      label: '${widget.departmentName}数字护士，${_semanticState(widget.state)}',
      image: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final wave = math.sin(_controller.value * math.pi * 2);
          final active =
              widget.state == NurseUiState.listening ||
              widget.state == NurseUiState.thinking ||
              widget.state == NurseUiState.speaking;
          final color = _stateColor(widget.state);
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.1),
                      radius: 0.74 + (active ? wave.abs() * 0.05 : 0),
                      colors: [
                        color.withValues(alpha: 0.22),
                        const Color(0xFFF5FBFB).withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, wave * 2.1),
                child: Transform.scale(
                  scale: 1 + wave * 0.0025,
                  child: FractionallySizedBox(
                    widthFactor: 0.94,
                    heightFactor: 0.96,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: color.withValues(
                            alpha: active ? 0.62 + wave.abs() * 0.22 : 0.22,
                          ),
                          width: active ? 3 : 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(
                              alpha: active ? 0.20 + wave.abs() * 0.08 : 0.09,
                            ),
                            blurRadius: active ? 24 : 14,
                            spreadRadius: active ? 3 : 0,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform.scale(
                            scale: 1.075,
                            alignment: const Alignment(0, -0.12),
                            child: _avatarImage(),
                          ),
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(0, -0.15),
                                  radius: 0.92,
                                  colors: [
                                    Colors.transparent,
                                    palette.primary.withValues(
                                      alpha: palette.isDark ? 0.12 : 0.065,
                                    ),
                                  ],
                                  stops: const [0.54, 1],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.state == NurseUiState.speaking)
                Positioned(
                  bottom: 34,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: const [
                        BoxShadow(color: Color(0x2200656B), blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      children: List.generate(7, (index) {
                        final height =
                            8 +
                            14 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                          _controller.value * math.pi * 10 +
                                              index * 0.8,
                                        ));
                        return Container(
                          width: 4,
                          height: height,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color _stateColor(NurseUiState state) => switch (state) {
    NurseUiState.listening => const Color(0xFF2AAEA6),
    NurseUiState.thinking => const Color(0xFF6475D8),
    NurseUiState.speaking => const Color(0xFF087F8C),
    NurseUiState.warning => const Color(0xFFE27A26),
    NurseUiState.error || NurseUiState.offline => const Color(0xFF8C9A9C),
    _ => const Color(0xFF55BDB8),
  };

  Widget _avatarImage() {
    final fallback = Image.asset(
      'assets/images/digital_nurse_v2.png',
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
    );
    final path = widget.imagePath.trim();
    if (path.isEmpty) return fallback;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  String _semanticState(NurseUiState state) => switch (state) {
    NurseUiState.listening => '正在聆听',
    NurseUiState.thinking => '正在查询',
    NurseUiState.speaking => '正在回答',
    NurseUiState.warning => '正在进行安全提醒',
    NurseUiState.activationRequired => '正在等待激活',
    _ => '正在待机',
  };
}
