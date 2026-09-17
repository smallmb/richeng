import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:richeng/app.dart';
import 'package:richeng/models.dart';
import 'package:richeng/reminders.dart';
import 'package:richeng/store.dart';

// 验证清单解析保留勾选状态，任务排序后仍以固定标识持久化。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('解析多阶段清单与完成标记', () {
    final phases = parseOutline('# 准备\n- [x] 确定目标\n- [ ] 阅读材料\n# 执行\n1. 写初稿');
    expect(phases.length, 2);
    expect(phases.first.tasks.first.done, true);
    expect(phases.first.tasks.last.title, '阅读材料');
    expect(phases.last.tasks.single.title, '写初稿');
    expect(phases.first.tasks.first.importSource, '- [x] 确定目标');
    expect(
      parseOutline('# 阶段\n- 第 3 周完成测试')
          .single
          .tasks
          .single
          .needsDateConfirmation,
      true,
    );
    expect(parseOutline('   '), isEmpty);
  });
  test('自动外观在夜间切换为深色', () {
    expect(isAutomaticDark(DateTime(2026, 9, 17, 18, 59)), false);
    expect(isAutomaticDark(DateTime(2026, 9, 17, 19)), true);
    expect(isAutomaticDark(DateTime(2026, 9, 17, 6, 59)), true);
    expect(isAutomaticDark(DateTime(2026, 9, 17, 7)), false);
  });
  testWidgets('保存的深色模式使用深色主题和月亮图标', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'appearance.mode': 'dark'});
    final store = PlanStore(await SharedPreferences.getInstance(), [
      Project(
        title: '测试项目',
        phases: [Phase(title: '阶段')],
      ),
    ]);
    await tester.pumpWidget(RichengApp(store: store));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    expect(find.byIcon(Icons.dark_mode), findsWidgets);
  });
  test('保存、移动和重载不丢失进度', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final task = PlanTask(title: '设计', status: 'done', scheduled: '2026-09-15');
    final project = Project(
      title: '测试',
      phases: [
        Phase(
          title: '阶段',
          tasks: [
            task,
            PlanTask(title: '实现'),
          ],
        ),
      ],
    );
    final store = PlanStore(prefs, [project]);
    project.phases.first.tasks = project.phases.first.tasks.reversed.toList();
    await store.save();
    final reloaded = await PlanStore.load();
    expect(reloaded.projects.single.completed, 1);
    expect(reloaded.projects.single.tasks.last.id, task.id);
    expect(reloaded.projects.single.tasks.last.scheduled, '2026-09-15');
  });
  test('任务时间、预计耗时和提醒设置可随旧数据兼容保存', () {
    final old = PlanTask.fromJson({
      'id': 'legacy-task',
      'title': '旧任务',
      'status': 'todo',
      'difficulty': 1,
      'scheduled': '2026-09-15',
      'deadline': null,
    });
    expect(old.scheduledTime, isNull);
    old.scheduledTime = '09:30';
    old.scheduleDates = ['2026-09-15', '2026-09-17'];
    old.scheduleTimes = {'2026-09-15': '09:30', '2026-09-17': '19:00'};
    old.updates = [
      ProgressEntry(
        id: 'update-1',
        text: '接口已完成，等待测试',
        createdAt: DateTime(2026, 9, 15, 10),
      ),
    ];
    old.estimatedMinutes = 60;
    old.reminderMinutes = 15;
    final restored = PlanTask.fromJson(old.toJson());
    expect(restored.scheduledTime, '09:30');
    expect(restored.scheduleDates, ['2026-09-15', '2026-09-17']);
    expect(restored.timeForDate('2026-09-17'), '19:00');
    expect(restored.scheduledOn('2026-09-17'), true);
    expect(restored.estimatedMinutes, 60);
    expect(restored.reminderMinutes, 15);
    expect(restored.updates.single.text, '接口已完成，等待测试');
  });
  test('重新安排到今天不改变任务截止日期', () {
    final task = PlanTask(
      title: '补交材料',
      scheduled: '2026-09-01',
      deadline: '2026-09-03',
    );
    rescheduleTask(task, DateTime(2026, 9, 16));
    expect(task.scheduleDates, ['2026-09-16']);
    expect(task.scheduled, '2026-09-16');
    expect(task.deadline, '2026-09-03');
  });
  test('批量重排保留任务时间并按时间轴排序', () {
    final morning = PlanTask(
      title: '晨间复习',
      scheduled: '2026-09-10',
      scheduledTime: '09:00',
      deadline: '2026-09-12',
    );
    final evening = PlanTask(
      title: '晚上整理',
      scheduled: '2026-09-11',
      scheduledTime: '19:30',
    );
    final anytime = PlanTask(title: '全天阅读', scheduled: '2026-09-11');
    expect(rescheduleTasks([morning, evening], DateTime(2026, 9, 17)), 2);
    expect(morning.scheduleDates, ['2026-09-17']);
    expect(morning.timeForDate('2026-09-17'), '09:00');
    expect(morning.deadline, '2026-09-12');
    final rows = [anytime, evening, morning]
      ..sort((left, right) => compareTimelineTasks(left, right, '2026-09-17'));
    expect(rows.map((task) => task.title), ['晨间复习', '晚上整理', '全天阅读']);
    expect(timelineTimeFor(anytime, '2026-09-17'), '全天');
  });
  test('多日任务按当天独立时间计算提醒', () {
    final task = PlanTask(
      title: '复习',
      scheduleDates: ['2026-09-16', '2026-09-17'],
      scheduleTimes: {'2026-09-16': '09:00', '2026-09-17': '19:30'},
      reminderMinutes: 15,
    );
    expect(reminderTimeFor(task, '2026-09-16'), DateTime(2026, 9, 16, 8, 45));
    expect(reminderTimeFor(task, '2026-09-17'), DateTime(2026, 9, 17, 19, 15));
  });
  test('独立任务箱与项目日期可序列化', () {
    final inbox = Project(
      title: '独立任务',
      inbox: true,
      startDate: '2026-09-15',
      targetDeadline: '2026-10-01',
      phases: [
        Phase(
          title: '待办',
          tasks: [PlanTask(title: '缴费')],
        ),
      ],
    );
    final restored = Project.fromJson(inbox.toJson());
    expect(restored.inbox, true);
    expect(restored.startDate, '2026-09-15');
    expect(restored.targetDeadline, '2026-10-01');
  });
  testWidgets('手机页面可勾选并编辑任务', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final task = PlanTask(title: '完成初稿');
    final store = PlanStore(prefs, [
      Project(
        title: '毕业设计',
        phases: [
          Phase(title: '准备', tasks: [task]),
        ],
      ),
    ]);
    await tester.pumpWidget(RichengApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('毕业设计'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(task.done, true);
    await tester.tap(find.text('完成初稿'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日历').last);
    await tester.pumpAndSettle();
    expect(find.text('给计划留出时间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
