import 'dart:math';

// 每条记录使用稳定标识，排序和移动不会改变完成状态。
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

// 重新安排只调整执行日期；截止日期仍用于提示是否逾期。
void rescheduleTask(PlanTask task, DateTime day) {
  final date = dateKey(day);
  final previousDate = task.scheduled;
  final time = previousDate == null
      ? task.scheduledTime
      : task.timeForDate(previousDate);
  task.scheduleDates = [date];
  task.scheduled = date;
  // 保留原定开始时间，并丢弃已失效日期的独立时间设置。
  task.scheduleTimes = time == null ? {} : {date: time};
  task.scheduledTime = time;
}

// 批量重排只移动执行日期，不改变截止日期、完成状态或预计工时。
int rescheduleTasks(Iterable<PlanTask> tasks, DateTime day) {
  var count = 0;
  for (final task in tasks) {
    rescheduleTask(task, day);
    count++;
  }
  return count;
}

// 未设置时间的任务排在当天所有定时任务之后，作为“全天”任务展示。
String timelineTimeFor(PlanTask task, String date) =>
    task.timeForDate(date) ?? '全天';

int compareTimelineTasks(PlanTask left, PlanTask right, String date) {
  final leftTime = left.timeForDate(date) ?? '99:99';
  final rightTime = right.timeForDate(date) ?? '99:99';
  final timeOrder = leftTime.compareTo(rightTime);
  return timeOrder != 0 ? timeOrder : left.title.compareTo(right.title);
}

// 外部导入日期必须能被日期选择器展示，拒绝自动溢出到下月的日期。
String? checkedDate(dynamic value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('日期格式不正确');
  final date = DateTime.tryParse(value);
  if (date == null ||
      date.year < 2000 ||
      date.year > 2100 ||
      dateKey(date) != value) {
    throw const FormatException('日期须为 2000—2100 年的有效日期');
  }
  return value;
}

String checkedTitle(dynamic value) {
  if (value is! String || value.trim().isEmpty || value.length > 2000) {
    throw const FormatException('任务或阶段名称不正确');
  }
  return value.trim();
}

String? checkedOptionalText(dynamic value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty || value.length > 2000) {
    throw const FormatException('说明内容不正确');
  }
  return value.trim();
}

// 任务日程采用日期和本地时间分开保存，避免跨端同步时被时区自动偏移。
String? checkedTime(dynamic value) {
  if (value == null) return null;
  if (value is! String ||
      !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
    throw const FormatException('时间须为 HH:mm');
  }
  return value;
}

int? checkedMinutes(dynamic value, {String name = '分钟'}) {
  if (value == null) return null;
  if (value is! int || value < 0 || value > 1440) {
    throw FormatException('$name必须在 0—1440 之间');
  }
  return value;
}

List<String> checkedDates(dynamic value, String? legacyDate) {
  if (value == null) return legacyDate == null ? [] : [legacyDate];
  if (value is! List) throw const FormatException('执行日期格式不正确');
  final dates = value.map(checkedDate).cast<String>().toSet().toList()..sort();
  if (dates.length > 90) throw const FormatException('单个任务最多安排 90 个执行日期');
  return dates;
}

// 进度记录保留发生时间，便于回看长期项目为什么延期或完成。
class ProgressEntry {
  String id, text;
  DateTime createdAt;
  ProgressEntry({String? id, required this.text, DateTime? createdAt})
    : id = id ?? newId(),
      createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ProgressEntry.fromJson(Map<String, dynamic> json) => ProgressEntry(
    id: json['id'] as String?,
    text: checkedTitle(json['text']),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class PlanTask {
  String id, title, note, status;
  int difficulty;
  String? scheduled, scheduledTime, deadline;
  List<String> scheduleDates;
  Map<String, String> scheduleTimes;
  List<ProgressEntry> updates;
  int? estimatedMinutes, reminderMinutes;
  String? importSource, importBatchId;
  bool aiSuggested, needsDateConfirmation;
  PlanTask({
    String? id,
    required this.title,
    this.note = '',
    this.status = 'todo',
    this.difficulty = 1,
    this.scheduled,
    List<String>? scheduleDates,
    Map<String, String>? scheduleTimes,
    List<ProgressEntry>? updates,
    this.importSource,
    this.importBatchId,
    this.aiSuggested = false,
    this.needsDateConfirmation = false,
    this.scheduledTime,
    this.deadline,
    this.estimatedMinutes,
    this.reminderMinutes,
  }) : id = id ?? newId(),
       scheduleDates = scheduleDates ?? (scheduled == null ? [] : [scheduled]),
       scheduleTimes = scheduleTimes ?? {},
       updates = updates ?? [];
  bool get done => status == 'done';
  // 新数据按日期读取时间；旧数据继续使用统一的 scheduledTime。
  String? timeForDate(String date) => scheduleTimes[date] ?? scheduledTime;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'status': status,
    'difficulty': difficulty,
    'scheduled': scheduled,
    'scheduleDates': scheduleDates,
    'scheduleTimes': scheduleTimes,
    'updates': updates.map((entry) => entry.toJson()).toList(),
    'importSource': importSource,
    'importBatchId': importBatchId,
    'aiSuggested': aiSuggested,
    'needsDateConfirmation': needsDateConfirmation,
    'scheduledTime': scheduledTime,
    'deadline': deadline,
    'estimatedMinutes': estimatedMinutes,
    'reminderMinutes': reminderMinutes,
  };
  factory PlanTask.fromJson(Map<String, dynamic> j) {
    final scheduled = checkedDate(j['scheduled']);
    final dates = checkedDates(j['scheduleDates'], scheduled);
    final legacyTime = checkedTime(j['scheduledTime']);
    final rawTimes = j['scheduleTimes'];
    final scheduleTimes = <String, String>{
      if (rawTimes == null && legacyTime != null)
        for (final date in dates) date: legacyTime,
      if (rawTimes is Map)
        for (final entry in rawTimes.entries)
          if (dates.contains(checkedDate(entry.key)))
            checkedDate(entry.key)!: checkedTime(entry.value)!,
    };
    return PlanTask(
      id: j['id'],
      title: checkedTitle(j['title']),
      note: j['note'] ?? '',
      status: ['todo', 'doing', 'done'].contains(j['status'] ?? 'todo')
          ? j['status'] ?? 'todo'
          : throw const FormatException('任务状态不正确'),
      difficulty: [1, 2, 3].contains(j['difficulty'] ?? 1)
          ? j['difficulty'] ?? 1
          : throw const FormatException('难度不正确'),
      scheduled: dates.firstOrNull,
      scheduleDates: dates,
      scheduleTimes: scheduleTimes,
      updates: (j['updates'] as List? ?? const [])
          .map(
            (entry) => ProgressEntry.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(),
      importSource: checkedOptionalText(j['importSource']),
      importBatchId: checkedOptionalText(j['importBatchId']),
      aiSuggested: j['aiSuggested'] is bool ? j['aiSuggested'] as bool : false,
      needsDateConfirmation: j['needsDateConfirmation'] is bool
          ? j['needsDateConfirmation'] as bool
          : false,
      scheduledTime: legacyTime,
      deadline: checkedDate(j['deadline']),
      estimatedMinutes: checkedMinutes(j['estimatedMinutes'], name: '预计时长'),
      reminderMinutes: checkedMinutes(j['reminderMinutes'], name: '提醒提前时间'),
    );
  }
  bool scheduledOn(String date) => scheduleDates.contains(date);
}

class Phase {
  String id, title, period;
  int color;
  List<PlanTask> tasks;
  Phase({
    String? id,
    required this.title,
    this.period = '',
    this.color = 0xff378add,
    List<PlanTask>? tasks,
  }) : id = id ?? newId(),
       tasks = tasks ?? [];
  int get completed => tasks.where((t) => t.done).length;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'period': period,
    'color': color,
    'tasks': tasks.map((t) => t.toJson()).toList(),
  };
  factory Phase.fromJson(Map<String, dynamic> j) => Phase(
    id: j['id'],
    title: checkedTitle(j['title']),
    period: j['period'] ?? '',
    color: j['color'] ?? 0xff378add,
    tasks: (j['tasks'] as List)
        .map((t) => PlanTask.fromJson(Map<String, dynamic>.from(t)))
        .toList(),
  );
}

class Project {
  String id, title, description;
  bool archived, inbox;
  String? startDate, targetDeadline;
  List<Phase> phases;
  Project({
    String? id,
    required this.title,
    this.description = '',
    this.archived = false,
    this.inbox = false,
    this.startDate,
    this.targetDeadline,
    List<Phase>? phases,
  }) : id = id ?? newId(),
       phases = phases ?? [];
  List<PlanTask> get tasks => phases.expand((p) => p.tasks).toList();
  int get completed => tasks.where((t) => t.done).length;
  double get progress => tasks.isEmpty ? 0 : completed / tasks.length;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'archived': archived,
    'inbox': inbox,
    'startDate': startDate,
    'targetDeadline': targetDeadline,
    'phases': phases.map((p) => p.toJson()).toList(),
  };
  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: j['id'],
    title: checkedTitle(j['title']),
    description: j['description'] ?? '',
    archived: j['archived'] ?? false,
    inbox: j['inbox'] ?? false,
    startDate: checkedDate(j['startDate']),
    targetDeadline: checkedDate(j['targetDeadline']),
    phases: (j['phases'] as List)
        .map((p) => Phase.fromJson(Map<String, dynamic>.from(p)))
        .toList(),
  );
}

// 本地导入只整理明确的清单，不假装进行模型推理或补全日期。
List<Phase> parseOutline(String source) {
  final result = <Phase>[];
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      final title = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      if (title.isNotEmpty) result.add(Phase(title: title));
    } else {
      if (result.isEmpty) result.add(Phase(title: '导入任务'));
      final done = RegExp(r'^[-*]\s*\[[xX]\]').hasMatch(line);
      final title = line
          .replaceFirst(RegExp(r'^([-*]\s*(\[[ xX]\]\s*)?|\d+[.、]\s*)'), '')
          .trim();
      if (title.isNotEmpty) {
        result.last.tasks.add(
          PlanTask(
            title: title,
            status: done ? 'done' : 'todo',
            // 保留原始行，供审核导入来源时核对。
            importSource: line,
            // “第 3 周”没有计划起点时无法换算为实际日期。
            needsDateConfirmation: RegExp(r'第\s*\d+\s*周').hasMatch(line),
          ),
        );
      }
    }
  }
  return result.where((p) => p.tasks.isNotEmpty).toList();
}
