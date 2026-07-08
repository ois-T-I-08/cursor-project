import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 初回フレーム描画後に子ウィジェットを構築し、起動時のメインスレッド負荷を分散する。
class DeferredLoader extends StatefulWidget {
  const DeferredLoader({
    super.key,
    required this.builder,
    this.placeholder,
  });

  final WidgetBuilder builder;
  final Widget? placeholder;

  @override
  State<DeferredLoader> createState() => _DeferredLoaderState();
}

class _DeferredLoaderState extends State<DeferredLoader> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    return widget.builder(context);
  }
}
