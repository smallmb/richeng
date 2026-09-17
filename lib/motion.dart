import 'package:flutter/material.dart';

// 采用参考站公开的缓动参数；回弹仅用于图标缩放，不用于透明度和布局。
const motionGlide = Cubic(.16, 1, .3, 1);
const motionSheet = Cubic(.32, .72, 0, 1);
const motionSettle = Cubic(.3, 1.25, .45, 1);
Duration motionOf(BuildContext context, [int milliseconds = 240]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class MotionCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  const MotionCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  State<MotionCheckbox> createState() => _MotionCheckboxState();
}

class _MotionCheckboxState extends State<MotionCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    value: 1,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.duration = motionOf(context, 210);
    if (MediaQuery.disableAnimationsOf(context)) controller.value = 1;
  }

  @override
  void didUpdateWidget(MotionCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) => Transform.scale(
      scale: .94 + .06 * motionSettle.transform(controller.value),
      child: child,
    ),
    child: Checkbox(value: widget.value, onChanged: widget.onChanged),
  );
}

// 首次显示直接呈现真实进度，只有值变化时才从上次位置过渡。
class MotionProgress extends StatelessWidget {
  final double value, minHeight;
  final Color? color, backgroundColor;
  const MotionProgress({
    super.key,
    required this.value,
    this.minHeight = 4,
    this.color,
    this.backgroundColor,
  });
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    duration: motionOf(context, 280),
    curve: motionGlide,
    tween: Tween(begin: value, end: value),
    builder: (context, progress, _) => LinearProgressIndicator(
      value: progress,
      minHeight: minHeight,
      color: color,
      backgroundColor: backgroundColor,
    ),
  );
}

// 一个控制器同时驱动高度、箭头和淡入，快速点击可从当前位置反向。
class PhaseDisclosure extends StatefulWidget {
  final Widget leading, title, subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;
  const PhaseDisclosure({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.children,
    this.initiallyExpanded = false,
  });
  @override
  State<PhaseDisclosure> createState() => _PhaseDisclosureState();
}

class _PhaseDisclosureState extends State<PhaseDisclosure>
    with SingleTickerProviderStateMixin {
  late bool expanded = widget.initiallyExpanded;
  late final AnimationController controller = AnimationController(
    vsync: this,
    value: expanded ? 1 : 0,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.duration = motionOf(context, 260);
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = expanded ? 1 : 0;
    }
  }

  void toggle() {
    setState(() => expanded = !expanded);
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = expanded ? 1 : 0;
    } else if (expanded) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        expanded: expanded,
        child: InkWell(
          splashFactory: MediaQuery.disableAnimationsOf(context)
              ? NoSplash.splashFactory
              : null,
          highlightColor: MediaQuery.disableAnimationsOf(context)
              ? Colors.transparent
              : null,
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                widget.leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      widget.title,
                      const SizedBox(height: 3),
                      widget.subtitle,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                RotationTransition(
                  turns: controller
                      .drive(CurveTween(curve: motionGlide))
                      .drive(Tween(begin: 0.0, end: .5)),
                  child: const Icon(Icons.keyboard_arrow_down, size: 21),
                ),
              ],
            ),
          ),
        ),
      ),
      AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Offstage(
          offstage: controller.isDismissed,
          child: IgnorePointer(
            ignoring: !expanded,
            child: ExcludeSemantics(
              excluding: !expanded,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  key: const ValueKey('phase-body-extent'),
                  heightFactor: motionGlide.transform(controller.value),
                  child: Opacity(
                    opacity: const Interval(
                      .08,
                      .85,
                      curve: Curves.easeOut,
                    ).transform(controller.value),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
        child: ExcludeFocus(
          excluding: !expanded,
          child: Column(children: widget.children),
        ),
      ),
    ],
  );
}

// 先保留完成反馈，再收起行；调用方在过渡结束后移除对应记录视图。
class MotionTaskVisibility extends StatelessWidget {
  final bool visible;
  final Widget child;
  const MotionTaskVisibility({
    super.key,
    required this.visible,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 1, end: visible ? 1 : 0),
    duration: motionOf(context, 200),
    curve: motionGlide,
    builder: (context, value, child) => ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: value,
        child: IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: Opacity(opacity: value, child: child),
          ),
        ),
      ),
    ),
    child: child,
  );
}

Future<void> showTaskEditor({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final desktop = MediaQuery.sizeOf(context).width >= 900;
  final route = RawDialogRoute<void>(
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: .18),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: motionOf(context, desktop ? 280 : 300),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final value = motionSheet.transform(animation.value);
            return Transform.translate(
              offset: Offset(
                desktop ? 32 * (1 - value) : 0,
                desktop ? 0 : 44 * (1 - value),
              ),
              child: Opacity(opacity: animation.value, child: child),
            );
          },
        ),
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  // 等到退出动画结束，编辑器控制器才可以被释放。
  await route.completed;
}

class TaskEditorSurface extends StatelessWidget {
  final Widget title, content;
  final List<Widget> actions;
  const TaskEditorSurface({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return SafeArea(
      child: AnimatedPadding(
        duration: motionOf(context, 180),
        curve: motionGlide,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          alignment: desktop ? Alignment.centerRight : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: desktop ? 520 : double.infinity,
              maxHeight:
                  MediaQuery.sizeOf(context).height * (desktop ? 1 : .94),
            ),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: Radius.circular(desktop ? 0 : 18),
                ),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (!desktop)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        width: 32,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: DefaultTextStyle(
                            style: Theme.of(context).textTheme.titleLarge!,
                            child: title,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭详情',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: SizedBox(width: double.infinity, child: content),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: actions,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
