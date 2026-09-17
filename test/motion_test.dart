import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:richeng/app.dart';
import 'package:richeng/models.dart';
import 'package:richeng/store.dart';
import 'package:richeng/motion.dart';

// 覆盖动效中断与布局边界，确保动画不会妨碍实际操作。
void main() {
  testWidgets('阶段可在展开途中反向收起并再次展开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Material(
            child: PhaseDisclosure(
              leading: const Text('P0'),
              title: const Text('准备阶段'),
              subtitle: const Text('0/1'),
              children: [
                TextButton(onPressed: () {}, child: const Text('阶段任务')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('阶段任务'), findsNothing);
    await tester.tap(find.text('准备阶段'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('准备阶段'));
    await tester.pumpAndSettle();
    expect(find.text('阶段任务'), findsNothing);
    await tester.tap(find.text('准备阶段'));
    await tester.pumpAndSettle();
    expect(find.text('阶段任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时阶段直接展开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Material(
              child: PhaseDisclosure(
                leading: const Text('P0'),
                title: const Text('阶段'),
                subtitle: const Text('0/1'),
                children: const [Text('内容')],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('阶段'));
    await tester.pump();
    expect(find.text('内容'), findsOneWidget);
    // 系统原生水波纹有独立时钟；这里验证自定义折叠已立即到达终点。
    expect(
      tester
          .widget<RotationTransition>(
            find.byWidgetPredicate(
              (w) =>
                  w is RotationTransition &&
                  w.child is Icon &&
                  (w.child as Icon).icon == Icons.keyboard_arrow_down,
            ),
          )
          .turns
          .value,
      .5,
    );
    final body = tester.widget<Align>(
      find.byKey(const ValueKey('phase-body-extent')),
    );
    expect(body.heightFactor, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未完成筛选先反馈再收起，撤回勾选不会丢失任务', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final task = PlanTask(title: '验证动画任务');
    final store = PlanStore(await SharedPreferences.getInstance(), [
      Project(
        title: '测试项目',
        phases: [
          Phase(title: '准备', tasks: [task]),
        ],
      ),
    ]);
    await tester.pumpWidget(RichengApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未完成'));
    await tester.pumpAndSettle();
    final checkbox = find.byType(Checkbox).first;
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump(const Duration(milliseconds: 100));
    expect(task.done, true);
    expect(find.text('验证动画任务'), findsOneWidget);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(task.done, false);
    expect(find.text('验证动画任务'), findsOneWidget);
    await tester.tap(checkbox);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(task.done, true);
    expect(find.text('验证动画任务'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机键盘弹出时详情动作仍可达，关闭保留原任务', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues({});
    final task = PlanTask(title: '编辑任务');
    final store = PlanStore(await SharedPreferences.getInstance(), [
      Project(
        title: '项目',
        phases: [
          Phase(title: '准备', tasks: [task]),
        ],
      ),
    ]);
    await tester.pumpWidget(RichengApp(store: store));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('编辑任务'));
    await tester.tap(find.text('编辑任务'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditorSurface), findsOneWidget);
    expect(tester.getBottomRight(find.text('保存任务')).dy, lessThan(544));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditorSurface), findsNothing);
    expect(task.title, '编辑任务');
    expect(tester.takeException(), isNull);
  });
}
