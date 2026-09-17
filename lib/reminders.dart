import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

// 计算任务某一天的提醒时间，供调度和测试共用。
DateTime? reminderTimeFor(PlanTask task, String date) {
  if (task.done || task.reminderMinutes == null) return null;
  final time = task.timeForDate(date);
  final start = time == null ? null : DateTime.tryParse('${date}T$time');
  return start?.subtract(Duration(minutes: task.reminderMinutes!));
}

// Android 本地提醒：只为设置了日期、时间和提醒提前量的未完成任务创建通知。
class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (_ready || !_android) return;
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // 设备返回的时区异常时使用 UTC，仍可安全取消和重新创建提醒。
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (!_android) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> notificationsAllowed() async {
    await initialize();
    if (!_android) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<void> showTest() async {
    await initialize();
    if (!_ready) return;
    await _plugin.show(
      id: 947231,
      title: '日程提醒测试',
      body: '通知已开启，任务开始前会在这里提醒你。',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'schedule_reminders',
          '日程提醒',
          channelDescription: '按任务安排时间提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  int _id(String taskId) {
    // 使用稳定、非负的 31 位散列，编辑任务后能正确覆盖旧提醒。
    var value = 0;
    for (final code in taskId.codeUnits) {
      value = (value * 31 + code) & 0x7fffffff;
    }
    return value;
  }

  Future<void> sync(List<Project> projects) async {
    await initialize();
    if (!_ready) return;
    await _plugin.cancelAll();
    for (final project in projects.where((p) => !p.archived)) {
      for (final task in project.tasks) {
        await _schedule(project, task);
      }
    }
  }

  Future<void> _schedule(Project project, PlanTask task) async {
    if (task.done ||
        task.scheduleDates.isEmpty ||
        task.reminderMinutes == null) {
      return;
    }
    for (final date in task.scheduleDates) {
      final reminderAt = reminderTimeFor(task, date);
      if (reminderAt == null) continue;
      if (!reminderAt.isAfter(DateTime.now())) continue;
      final local = tz.TZDateTime.from(reminderAt, tz.local);
      await _plugin.zonedSchedule(
        id: _id('${task.id}-$date'),
        title: task.title,
        body:
            '${project.title} · ${task.reminderMinutes == 0 ? '现在开始' : '${task.reminderMinutes} 分钟后开始'}',
        scheduledDate: local,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'schedule_reminders',
            '日程提醒',
            channelDescription: '按任务安排时间提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: task.id,
      );
    }
  }
}
