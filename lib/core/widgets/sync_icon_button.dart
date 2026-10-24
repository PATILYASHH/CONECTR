import 'package:flutter/material.dart';

/// The top-left sync icon. Spins while anything is syncing — including the
/// automatic check when the app opens — so there's always a visible sign
/// that work is happening.
class SyncIconButton extends StatefulWidget {
  const SyncIconButton({
    super.key,
    required this.spinning,
    required this.onPressed,
  });

  final bool spinning;
  final VoidCallback onPressed;

  @override
  State<SyncIconButton> createState() => _SyncIconButtonState();
}

class _SyncIconButtonState extends State<SyncIconButton>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(SyncIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      // Finish the turn instead of freezing mid-rotation.
      _controller.forward(from: _controller.value).then((_) {
        if (mounted) _controller.reset();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Sync now',
      // Not disabled while spinning — a greyed-out spinner reads as broken.
      onPressed: widget.spinning ? () {} : widget.onPressed,
      icon: RotationTransition(
        turns: _controller,
        child: const Icon(Icons.sync),
      ),
    );
  }
}
