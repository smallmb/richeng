import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'store.dart';
import 'cloud.dart';
import 'ai.dart';
import 'motion.dart';
import 'reminders.dart';

// 视觉令牌沿用原清单，跨端共享颜色和卡片结构。
const background = Color(0xfff6f6f4);
const border = Color(0xffe5e5e1);
const ink = Color(0xff18180f);
const secondary = Color(0xff6b6b62);
// 墨蓝作为主要强调色，沿用当前纸感界面。
const accent = Color(0xff3e5c76);
// 语义色区分完成、异常与进行中，小字采用更深的色值。
const toneDone = Color(0xff8a8a82);
const toneLate = Color(0xffa84432);
const toneDoing = Color(0xff8a5b0c);
const toneReady = Color(0xff7b9b78);

// AI 服务统一使用本项目的 /api/plan 接口，输入根地址时自动补全路径。
String? normalizeAiEndpoint(String raw) {
  final value = raw.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final path = uri.path.endsWith('/api/plan')
      ? uri.path
      : '${uri.path.isEmpty ? '' : uri.path}/api/plan';
  return uri.replace(path: path).toString();
}

// 健康检查位于 API 同级根路径，便于在保存前确认服务与模型配置。
Uri aiHealthUri(String endpoint) {
  final uri = Uri.parse(endpoint);
  const suffix = '/api/plan';
  final root = uri.path.endsWith(suffix)
      ? uri.path.substring(0, uri.path.length - suffix.length)
      : uri.path;
  return uri.replace(path: '${root.isEmpty ? '' : root}/health');
}

// 窄屏上不超出可用宽度，避免 390px 手机上弹窗溢出。
double dialogWidth(BuildContext context, [double desktop = 460]) =>
    MediaQuery.sizeOf(context).width.clamp(320, desktop).toDouble();

enum AppearanceMode { light, dark, automatic }

// 自动模式使用设备当地时间：19:00 至次日 06:59 显示深色外观。
bool isAutomaticDark(DateTime now) => now.hour >= 19 || now.hour < 7;

class RichengApp extends StatefulWidget {
  final PlanStore store;
  const RichengApp({super.key, required this.store});

  @override
  State<RichengApp> createState() => _RichengAppState();
}

class _RichengAppState extends State<RichengApp> {
  late AppearanceMode appearance;
  Timer? _appearanceTimer;

  @override
  void initState() {
    super.initState();
    appearance = AppearanceMode.values.firstWhere(
      (mode) =>
          mode.name == widget.store.preferences.getString('appearance.mode'),
      orElse: () => AppearanceMode.light,
    );
    // 每分钟检查一次，自动模式跨越 19:00 或 07:00 后无需重启即可切换。
    _appearanceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (appearance == AppearanceMode.automatic && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _appearanceTimer?.cancel();
    super.dispose();
  }

  bool get dark =>
      appearance == AppearanceMode.dark ||
      (appearance == AppearanceMode.automatic &&
          isAutomaticDark(DateTime.now()));

  Future<void> setAppearance(AppearanceMode mode) async {
    await widget.store.preferences.setString('appearance.mode', mode.name);
    if (mounted) setState(() => appearance = mode);
  }

  ThemeData theme(bool dark) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      primary: accent,
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: dark ? const Color(0xff1b1d20) : Colors.white,
      onSurface: dark ? const Color(0xffe8e8e4) : ink,
    );
    final pageBackground = dark ? const Color(0xff121416) : background;
    final line = dark ? const Color(0xff363a3f) : border;
    final muted = dark ? const Color(0xffb2b5b8) : secondary;
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: pageBackground,
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const [
        'PingFang SC',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
      colorScheme: scheme,
      dividerColor: line,
      textTheme: TextTheme(
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(fontSize: 12, color: muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff24272b) : background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: line),
        ),
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '日程 · 一步一步，完成计划',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: theme(dark),
    home: Workspace(
      store: widget.store,
      appearance: appearance,
      dark: dark,
      onAppearanceChanged: setAppearance,
    ),
  );
}

class Workspace extends StatefulWidget {
  final PlanStore store;
  final AppearanceMode appearance;
  final bool dark;
  final Future<void> Function(AppearanceMode mode) onAppearanceChanged;
  const Workspace({
    super.key,
    required this.store,
    required this.appearance,
    required this.dark,
    required this.onAppearanceChanged,
  });
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  late final CloudSession cloud;
  late final ReminderService reminders;
  final Set<String> finishing = {}, collapsing = {};
  final Map<String, Timer> finishTimers = {};

  // 仅在筛选会移除任务时延迟收起，勾选状态立即保存。
  void toggleTask(PlanTask task, bool value) {
    finishTimers.remove(task.id)?.cancel();
    finishing.remove(task.id);
    collapsing.remove(task.id);
    task.status = value ? 'done' : 'todo';
    if (value &&
        (filter == '未完成' || filter == '逾期') &&
        !MediaQuery.disableAnimationsOf(context)) {
      finishing.add(task.id);
      finishTimers[task.id] = Timer(const Duration(milliseconds: 240), () {
        if (!mounted) return;
        setState(() => collapsing.add(task.id));
        finishTimers[task.id] = Timer(const Duration(milliseconds: 210), () {
          if (!mounted) return;
          setState(() {
            finishing.remove(task.id);
            collapsing.remove(task.id);
            finishTimers.remove(task.id);
          });
        });
      });
    }
    save();
  }

  int page = 1;
  String? selected;
  String filter = '全部', search = '';
  DateTime calendarDay = DateTime.now();
  bool showArchived = false;
  PlanStore get store => widget.store;
  bool get dark => Theme.of(context).brightness == Brightness.dark;
  Color get surface => Theme.of(context).colorScheme.surface;
  Color get line => Theme.of(context).dividerColor;
  Color get onSurface => Theme.of(context).colorScheme.onSurface;
  Color get muted => dark ? const Color(0xffb2b5b8) : secondary;
  Project? get project =>
      store.projects.where((p) => p.id == selected).firstOrNull;
  List<Project> get active => store.projects.where((p) => !p.archived).toList();
  Project? get inbox =>
      store.projects.where((p) => p.inbox && !p.archived).firstOrNull;
  @override
  void initState() {
    super.initState();
    cloud = CloudSession(store);
    reminders = ReminderService();
    // 初始化不主动请求系统权限；已授权设备会恢复之前保存的提醒。
    unawaited(_restoreReminders());
    selected = active.firstOrNull?.id;
    store.addListener(refresh);
    // 中文说明：恢复后会自动续传离线期间已保存的本地编辑。
    unawaited(cloud.restore());
  }

  Future<void> _restoreReminders() async {
    await reminders.initialize();
    if (store.preferences.getBool('reminders.enabled') ?? false) {
      await reminders.sync(store.projects);
    }
  }

  @override
  void dispose() {
    for (final timer in finishTimers.values) {
      timer.cancel();
    }
    cloud.dispose();
    store.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void save() {
    store.save();
    unawaited(cloud.queueSync());
    if (store.preferences.getBool('reminders.enabled') ?? false) {
      unawaited(reminders.sync(store.projects));
    }
  }

  void toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // 云同步每 8 秒轮询一次，这里只让状态那一小块刷新。
  Widget syncStatus(BuildContext context, Widget? child) {
    final failure = store.error != null || cloud.conflict;
    final online = cloud.enabled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 16,
          child: Center(
            child: AnimatedSwitcher(
              duration: motionOf(context),
              child: Icon(
                failure
                    ? Icons.cloud_off
                    : online
                    ? Icons.cloud_done
                    : Icons.circle,
                key: ValueKey(
                  failure
                      ? '故障'
                      : online
                      ? '云端'
                      : '本地',
                ),
                size: failure || online ? 15 : 7,
                color: failure
                    ? toneLate
                    : online
                    ? toneReady
                    : secondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          store.error != null
              ? '保存异常'
              : cloud.conflict
              ? '同步冲突'
              : online
              ? '云端已连接'
              : '本地工作空间',
          style: const TextStyle(fontSize: 12, color: secondary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) sidebar(),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: line)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          wide
                              ? [
                                  '我的工作台 / 今天',
                                  '我的工作台 / 项目',
                                  '我的工作台 / 日历',
                                  '我的工作台 / 设置',
                                ][page]
                              : '日程',
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                        const Spacer(),
                        ListenableBuilder(
                          listenable: Listenable.merge([cloud, store]),
                          builder: syncStatus,
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          tooltip: '设置与备份',
                          onPressed: () => setState(() => page = 3),
                          icon: const Icon(
                            Icons.account_circle_outlined,
                            size: 23,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (store.error != null)
                    MaterialBanner(
                      content: Text(store.error!),
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => page = 3),
                          child: const Text('查看备份'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: motionOf(context),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, ?current],
                      ),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, .04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: SingleChildScrollView(
                        key: ValueKey(page),
                        padding: EdgeInsets.all(wide ? 32 : 18),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1000),
                            child: switch (page) {
                              0 => today(),
                              1 => projectsPage(),
                              2 => calendar(),
                              _ => settings(),
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              backgroundColor: surface,
              onDestinationSelected: (i) => setState(() => page = i),
              destinations: [
                NavigationDestination(
                  icon: Icon(
                    dark ? Icons.dark_mode : Icons.wb_sunny_outlined,
                    color: dark ? Colors.amber.shade500 : null,
                  ),
                  label: '今天',
                ),
                NavigationDestination(
                  icon: Icon(Icons.layers_outlined),
                  label: '项目',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: '日历',
                ),
                NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
              ],
            ),
    );
  }

  Widget sidebar() => Container(
    width: 220,
    decoration: BoxDecoration(
      color: dark ? const Color(0xff1a1c1f) : const Color(0xfff0f0ed),
      border: Border(right: BorderSide(color: line)),
    ),
    child: Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(26, 32, 20, 5),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: accent, size: 29),
                SizedBox(width: 9),
                Text(
                  '日程',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(27, 0, 20, 32),
            child: Text(
              '一步一步，完成计划',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Material(
                color: page == i ? surface : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  leading: Icon(
                    [
                      dark ? Icons.dark_mode : Icons.wb_sunny_outlined,
                      Icons.layers_outlined,
                      Icons.calendar_month_outlined,
                      Icons.tune,
                    ][i],
                    size: 20,
                    color: i == 0 && dark
                        ? Colors.amber.shade500
                        : page == i
                        ? accent
                        : muted,
                  ),
                  title: Text(
                    ['今天', '项目', '日历', '设置'][i],
                    style: TextStyle(
                      color: page == i ? accent : onSurface,
                      fontWeight: page == i
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => setState(() => page = i),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(26, 30, 20, 10),
            child: Text('进行中的项目', style: TextStyle(fontSize: 11, color: muted)),
          ),
          Expanded(
            child: ListView(
              children: active
                  .map(
                    (p) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 26,
                      ),
                      dense: true,
                      leading: const Icon(Icons.circle, size: 8, color: accent),
                      title: Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => setState(() {
                        selected = p.id;
                        showArchived = false;
                        page = 1;
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: panel(
              Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '给计划一个开始',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '粘贴已有清单，整理成阶段任务。',
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: importPlan,
                      child: const Text('导入计划 ↗'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget panel(Widget child) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: surface,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Material(color: Colors.transparent, child: child),
  );
  Widget heading(
    String title,
    String subtitle, {
    List<Widget> actions = const [],
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w600,
                letterSpacing: -.5,
              ),
            ),
            ...actions,
          ],
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(fontSize: 13, color: muted)),
      ],
    ),
  );
  Widget label(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
  Widget empty(
    String title,
    String detail,
    VoidCallback action,
    String button,
  ) => panel(
    Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.task_alt, size: 32, color: muted),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: action, child: Text(button)),
          ],
        ),
      ),
    ),
  );

  Widget projectsPage() {
    final p = project;
    if (p == null || p.archived != showArchived) {
      final list = store.projects
          .where((p) => p.archived == showArchived)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(
            '我的项目',
            '把长远目标，拆成眼前的一小步。',
            actions: [
              FilledButton.icon(
                onPressed: () => editProject(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建项目'),
              ),
            ],
          ),
          Row(
            children: [
              FilterChip(
                label: const Text('进行中'),
                selected: !showArchived,
                onSelected: (_) => setState(() => showArchived = false),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('已归档'),
                selected: showArchived,
                onSelected: (_) => setState(() => showArchived = true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            empty('这里还没有项目', '从一个目标开始，也可以导入已有清单。', () => editProject(), '新建项目'),
          ...list.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: panel(
                ListTile(
                  contentPadding: const EdgeInsets.all(20),
                  title: Text(
                    p.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p.inbox ? '独立任务' : '${p.phases.length} 个阶段'} · ${p.completed}/${p.tasks.length} 项已完成${p.targetDeadline == null ? '' : ' · 目标 ${p.targetDeadline}'}',
                        ),
                        const SizedBox(height: 12),
                        MotionProgress(
                          value: p.progress,
                          minHeight: 4,
                          backgroundColor: dark
                              ? const Color(0xff30343a)
                              : background,
                        ),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () => setState(() => selected = p.id),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final completePhases = p.phases
        .where((s) => s.tasks.isNotEmpty && s.completed == s.tasks.length)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => selected = null),
          icon: const Icon(Icons.arrow_back, size: 15),
          label: const Text('所有项目'),
        ),
        const SizedBox(height: 12),
        heading(
          p.title,
          p.description.isEmpty ? '每一个完成，都让目标更近一点。' : p.description,
          actions: [
            PopupMenuButton<String>(
              tooltip: '项目操作',
              onSelected: (v) {
                if (v == 'edit') {
                  editProject(p);
                } else {
                  p.archived = !p.archived;
                  selected = null;
                  save();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑项目')),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(p.archived ? '恢复项目' : '归档项目'),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            stat('${p.completed}', '已完成任务', blue: true),
            const SizedBox(width: 10),
            stat('${p.tasks.length}', '总任务数'),
            const SizedBox(width: 10),
            stat('$completePhases/${p.phases.length}', '阶段完成数'),
          ],
        ),
        const SizedBox(height: 12),
        panel(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Text('任务完成率', style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(width: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MotionProgress(
                      value: p.progress,
                      minHeight: 7,
                      backgroundColor: dark
                          ? const Color(0xff30343a)
                          : background,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${(p.progress * 100).round()}%',
                  style: const TextStyle(fontSize: 13, color: accent),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in ['全部', '未完成', '已完成', '逾期'])
              ChoiceChip(
                label: Text(f),
                selected: filter == f,
                onSelected: (_) => setState(() => filter = f),
                showCheckmark: false,
                side: BorderSide(color: line),
              ),
            OutlinedButton.icon(
              onPressed: importPlan,
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('AI / 清单导入'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => search = v),
          decoration: const InputDecoration(
            hintText: '搜索项目中的任务',
            prefixIcon: Icon(Icons.search, size: 19),
            isDense: true,
          ),
        ),
        const SizedBox(height: 18),
        if (p.phases.isEmpty)
          empty('先添加一个阶段', '例如：准备、执行、收尾。', () => editPhase(p), '添加阶段'),
        ...p.phases.asMap().entries.map((e) => phaseCard(p, e.value, e.key)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => editPhase(p),
          icon: const Icon(Icons.add, size: 17),
          label: const Text('添加阶段'),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            '不用一次完成全部，先完成下一步。',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ],
    );
  }

  Widget stat(String value, String title, {bool blue = false}) => Expanded(
    child: panel(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w500,
                color: blue ? accent : onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ),
    ),
  );
  bool matches(PlanTask task) =>
      task.title.toLowerCase().contains(search.toLowerCase()) &&
      switch (filter) {
        '未完成' => !task.done,
        '已完成' => task.done,
        '逾期' => overdue(task),
        _ => true,
      };
  bool overdue(PlanTask task) =>
      !task.done &&
      task.deadline != null &&
      task.deadline!.compareTo(dateKey(DateTime.now())) < 0;
  Widget phaseCard(Project p, Phase phase, int index) {
    final tasks = phase.tasks
        .where((task) => matches(task) || finishing.contains(task.id))
        .toList();
    final color = Color(phase.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panel(
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: PhaseDisclosure(
            key: ValueKey('${phase.id}-$filter-${search.isNotEmpty}'),
            initiallyExpanded:
                index == 0 || search.isNotEmpty || filter != '全部',
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'P$index',
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Text(
              phase.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${phase.completed}/${phase.tasks.length} 已完成${phase.period.isEmpty ? '' : ' · ${phase.period}'}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            children: [
              MotionProgress(
                value: phase.tasks.isEmpty
                    ? 0
                    : phase.completed / phase.tasks.length,
                minHeight: 3,
                color: color,
                backgroundColor: dark ? const Color(0xff30343a) : background,
              ),
              ...tasks.map(
                (t) => MotionTaskVisibility(
                  key: ValueKey(t.id),
                  visible: !collapsing.contains(t.id),
                  child: taskRow(p, phase, t),
                ),
              ),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('暂无符合条件的任务', style: TextStyle(color: muted)),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => editTask(p, phase),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加任务'),
                    ),
                    TextButton(
                      onPressed: () => editPhase(p, phase),
                      child: const Text('编辑阶段'),
                    ),
                    if (index > 0)
                      TextButton(
                        onPressed: () {
                          p.phases.removeAt(index);
                          p.phases.insert(index - 1, phase);
                          save();
                        },
                        child: const Text('上移'),
                      ),
                    if (index < p.phases.length - 1)
                      TextButton(
                        onPressed: () {
                          p.phases.removeAt(index);
                          p.phases.insert(index + 1, phase);
                          save();
                        },
                        child: const Text('下移'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget taskRow(
    Project p,
    Phase phase,
    PlanTask task, {
    bool showProject = false,
    bool offerToday = false,
  }) {
    final difficulty = task.difficulty.clamp(1, 3);
    final colors = [
      const Color(0xff2a7a36),
      const Color(0xff8a5108),
      const Color(0xff9b2222),
    ];
    return Container(
      key: ValueKey(task.id),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 7),
            child: MotionCheckbox(
              value: task.done,
              onChanged: (v) => toggleTask(task, v!),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => editTask(p, phase, task),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 15, 14, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: motionOf(context, 180),
                            curve: motionGlide,
                            style: TextStyle(
                              fontFamily: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontFamily,
                              fontFamilyFallback: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontFamilyFallback,
                              fontSize: 14,
                              height: 1.5,
                              color: task.done ? muted : onSurface,
                              decoration: task.done
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              decorationColor: toneDone,
                            ),
                            child: Text(task.title),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors[difficulty - 1].withValues(
                              alpha: .09,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            ['简单', '中等', '较难'][difficulty - 1],
                            style: TextStyle(
                              fontSize: 10,
                              color: colors[difficulty - 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (task.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          task.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    if (task.updates.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '最近进展：${task.updates.first.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    if (offerToday && overdue(task))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton.icon(
                          onPressed: () {
                            rescheduleTask(task, DateTime.now());
                            save();
                            toast('已安排到今天，截止日期保持不变');
                          },
                          icon: const Icon(Icons.today_outlined, size: 16),
                          label: const Text('安排到今天'),
                        ),
                      ),
                    if (showProject ||
                        task.scheduled != null ||
                        task.deadline != null ||
                        task.status == 'doing')
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            if (showProject)
                              Text(
                                p.title,
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            if (task.status == 'doing')
                              const Text(
                                '进行中',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: toneDoing,
                                ),
                              ),
                            if (task.scheduled != null)
                              Text(
                                '安排 ${task.scheduled}${task.scheduleDates.length > 1 ? ' 等 ${task.scheduleDates.length} 天' : ''}${task.timeForDate(task.scheduled!) == null ? '' : ' ${task.timeForDate(task.scheduled!)}'}',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            if (task.estimatedMinutes != null)
                              Text(
                                '预计 ${task.estimatedMinutes! >= 60 && task.estimatedMinutes! % 60 == 0 ? '${task.estimatedMinutes! ~/ 60} 小时' : '${task.estimatedMinutes} 分钟'}',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            if (task.reminderMinutes != null)
                              const Text(
                                '已提醒',
                                style: TextStyle(fontSize: 11, color: accent),
                              ),
                            if (task.deadline != null)
                              Text(
                                '${overdue(task) ? '已逾期' : '截止'} ${task.deadline}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: overdue(task) ? toneLate : muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<(Project, Phase, PlanTask)> get entries => [
    for (final p in active)
      for (final s in p.phases)
        for (final t in s.tasks) (p, s, t),
  ];
  Widget taskGroup(
    List<(Project, Phase, PlanTask)> rows, {
    bool offerToday = false,
  }) => panel(
    Column(
      children: rows
          .map(
            (e) => taskRow(
              e.$1,
              e.$2,
              e.$3,
              showProject: true,
              offerToday: offerToday,
            ),
          )
          .toList(),
    ),
  );

  // 今天页按开始时间显示，未设置时间的任务统一放在时间轴底部。
  Widget todayTimeline(List<(Project, Phase, PlanTask)> rows, String date) {
    final sorted = [...rows]
      ..sort((left, right) => compareTimelineTasks(left.$3, right.$3, date));
    return panel(
      Column(
        children: [
          for (final entry in sorted)
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 58,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 17, left: 12),
                    child: Text(
                      timelineTimeFor(entry.$3, date),
                      style: TextStyle(
                        fontSize: 12,
                        color: entry.$3.timeForDate(date) == null
                            ? muted
                            : accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Container(width: 1, color: line),
                Expanded(
                  child: taskRow(
                    entry.$1,
                    entry.$2,
                    entry.$3,
                    showProject: true,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> rescheduleOverdue(List<(Project, Phase, PlanTask)> late) async {
    final selectedIds = late.map((entry) => entry.$3.id).toSet();
    var targetDay = DateTime.now();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('批量重新安排'),
          content: SizedBox(
            width: dialogWidth(ctx, 460),
            height: MediaQuery.sizeOf(ctx).height.clamp(360, 560).toDouble(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择要移动的逾期任务。任务的截止日期保持不变，原有开始时间会保留。',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text('重新安排到：${dateKey(targetDay)}'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: targetDay,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) update(() => targetDay = picked);
                  },
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in late)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selectedIds.contains(entry.$3.id),
                          onChanged: (selected) => update(() {
                            if (selected == true) {
                              selectedIds.add(entry.$3.id);
                            } else {
                              selectedIds.remove(entry.$3.id);
                            }
                          }),
                          title: Text(entry.$3.title),
                          subtitle: Text(
                            '${entry.$1.title} · 原安排 ${entry.$3.scheduled ?? '未设置'} · 截止 ${entry.$3.deadline}',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selectedIds.isEmpty
                  ? null
                  : () {
                      final selected = late
                          .where((entry) => selectedIds.contains(entry.$3.id))
                          .map((entry) => entry.$3);
                      final count = rescheduleTasks(selected, targetDay);
                      save();
                      Navigator.pop(ctx);
                      toast('已将 $count 项逾期任务安排到 ${dateKey(targetDay)}');
                    },
              child: const Text('确认重排'),
            ),
          ],
        ),
      ),
    );
  }

  Widget today() {
    final key = dateKey(DateTime.now());
    final planned = entries
        .where((e) => e.$3.scheduledOn(key) || e.$3.deadline == key)
        .toList();
    final late = entries.where((e) => overdue(e.$3)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          '今天，向前一步',
          '$key · ${['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][DateTime.now().weekday - 1]}',
          actions: [
            FilledButton.icon(
              onPressed: quickTask,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加任务'),
            ),
          ],
        ),
        Row(
          children: [
            stat(
              '${planned.where((e) => e.$3.done).length}/${planned.length}',
              '今日已完成',
              blue: true,
            ),
            const SizedBox(width: 10),
            stat('${active.length}', '进行中项目'),
            const SizedBox(width: 10),
            stat('${late.length}', '逾期待办'),
          ],
        ),
        if (late.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: label('需要重新安排 · ${late.length}')),
              TextButton.icon(
                onPressed: () => rescheduleOverdue(late),
                icon: const Icon(Icons.event_repeat_outlined, size: 16),
                label: const Text('批量重排'),
              ),
            ],
          ),
          taskGroup(late, offerToday: true),
        ],
        label('今日安排'),
        if (planned.isEmpty)
          empty('今天还没有安排', '为已有任务设置安排日期，或添加一个小任务。', quickTask, '安排第一件事')
        else
          todayTimeline(planned, key),
        label('尚未安排'),
        taskGroup(
          entries
              .where((e) => e.$3.scheduleDates.isEmpty && !e.$3.done)
              .take(5)
              .toList(),
        ),
      ],
    );
  }

  Widget calendar() {
    final rows = entries
        .where(
          (e) =>
              e.$3.scheduledOn(dateKey(calendarDay)) ||
              e.$3.deadline == dateKey(calendarDay),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading('给计划留出时间', '选择日期，查看当天安排与截止任务。'),
        panel(
          CalendarDatePicker(
            initialDate: calendarDay,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            onDateChanged: (d) => setState(() => calendarDay = d),
          ),
        ),
        label('${dateKey(calendarDay)} · ${rows.length} 项任务'),
        if (rows.isEmpty)
          empty(
            '这一天还没有安排',
            '添加任务后，可以在任务详情中调整日期。',
            () => quickTask(day: calendarDay),
            '添加当天任务',
          )
        else
          taskGroup(rows),
      ],
    );
  }

  Future<void> quickTask({DateTime? day}) async {
    // 快速添加默认进入独立任务箱，用户无需先创建项目。
    var p = inbox;
    p ??= Project(title: '独立任务', description: '不属于项目的日常待办。', inbox: true);
    if (!store.projects.contains(p)) {
      store.projects.add(p);
    }
    if (p.phases.isEmpty) {
      p.phases.add(Phase(title: '待办'));
      save();
    }
    await editTask(p, p.phases.first, null, day ?? DateTime.now());
  }

  Future<void> editProject([Project? current]) async {
    final title = TextEditingController(text: current?.title);
    final description = TextEditingController(text: current?.description);
    String? startDate = current?.startDate;
    String? targetDeadline = current?.targetDeadline;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current == null ? '新建项目' : '编辑项目'),
        content: SizedBox(
          width: dialogWidth(ctx, 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '项目名称'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '目标说明'),
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, update) => Column(
                  children: [
                    for (final type in ['开始', '目标截止'])
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                              ),
                              label: Text(
                                '$type：${(type == '开始' ? startDate : targetDeadline) ?? '未设置'}',
                              ),
                              onPressed: () async {
                                final old = type == '开始'
                                    ? startDate
                                    : targetDeadline;
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: old == null
                                      ? DateTime.now()
                                      : DateTime.parse(old),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null) {
                                  update(() {
                                    if (type == '开始') {
                                      startDate = dateKey(date);
                                    } else {
                                      targetDeadline = dateKey(date);
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: '清除$type日期',
                            onPressed: () => update(() {
                              if (type == '开始') {
                                startDate = null;
                              } else {
                                targetDeadline = null;
                              }
                            }),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) {
                toast('请填写名称后再保存');
                return;
              }
              if (current == null) {
                final p = Project(
                  title: title.text.trim(),
                  description: description.text.trim(),
                  startDate: startDate,
                  targetDeadline: targetDeadline,
                );
                store.projects.add(p);
                selected = p.id;
                showArchived = false;
                page = 1;
              } else {
                current.title = title.text.trim();
                current.description = description.text.trim();
                current.startDate = startDate;
                current.targetDeadline = targetDeadline;
              }
              save();
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> editPhase(Project p, [Phase? current]) async {
    final title = TextEditingController(text: current?.title);
    final period = TextEditingController(text: current?.period);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current == null ? '添加阶段' : '编辑阶段'),
        content: SizedBox(
          width: dialogWidth(ctx, 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '阶段名称'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: period,
                decoration: const InputDecoration(labelText: '时间说明（如第 1—2 周）'),
              ),
            ],
          ),
        ),
        actions: [
          if (current != null && current.tasks.isEmpty)
            TextButton(
              onPressed: () {
                p.phases.remove(current);
                save();
                Navigator.pop(ctx);
              },
              child: const Text('删除空阶段'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) {
                toast('请填写名称后再保存');
                return;
              }
              if (current == null) {
                p.phases.add(
                  Phase(
                    title: title.text.trim(),
                    period: period.text.trim(),
                    color: [
                      0xff378add,
                      0xff1d9e75,
                      0xffba7517,
                      0xffd4537e,
                      0xff7b6ef6,
                    ][p.phases.length % 5],
                  ),
                );
              } else {
                current.title = title.text.trim();
                current.period = period.text.trim();
              }
              save();
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 编辑使用草稿，取消弹窗不会修改已保存任务。
  Future<void> editTask(
    Project p,
    Phase phase, [
    PlanTask? current,
    DateTime? initialDay,
  ]) async {
    final title = TextEditingController(text: current?.title);
    final note = TextEditingController(text: current?.note);
    final progressText = TextEditingController();
    var progressEntries = List<ProgressEntry>.of(current?.updates ?? []);
    var difficulty = current?.difficulty ?? 1;
    var status = current?.status ?? 'todo';
    String? scheduled =
        current?.scheduled ?? (initialDay == null ? null : dateKey(initialDay));
    var scheduleDates = List<String>.of(
      current?.scheduleDates ?? (scheduled == null ? [] : [scheduled]),
    );
    String? scheduledTime = current?.scheduledTime;
    var scheduleTimes = Map<String, String>.of(current?.scheduleTimes ?? {});
    if (scheduleTimes.isEmpty && scheduledTime != null) {
      scheduleTimes = {for (final date in scheduleDates) date: scheduledTime};
    }
    String? deadline = current?.deadline;
    int? estimatedMinutes = current?.estimatedMinutes;
    int? reminderMinutes = current?.reminderMinutes;
    var target = phase;
    await showTaskEditor(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => TaskEditorSurface(
          title: Text(current == null ? '添加任务' : '任务详情'),
          content: SizedBox(
            width: dialogWidth(ctx, 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title, style: TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: title,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '任务名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: '说明与进度备注'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '进度记录',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: progressText,
                          maxLength: 300,
                          decoration: const InputDecoration(
                            labelText: '记录本次进展',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '添加进度记录',
                        onPressed: () {
                          final text = progressText.text.trim();
                          if (text.isEmpty) return;
                          update(() {
                            progressEntries.insert(
                              0,
                              ProgressEntry(text: text),
                            );
                            progressText.clear();
                          });
                        },
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  if (progressEntries.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        children: [
                          for (final entry in progressEntries)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(entry.text),
                              subtitle: Text(
                                '${dateKey(entry.createdAt)} ${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}',
                              ),
                              trailing: IconButton(
                                tooltip: '删除这条记录',
                                onPressed: () =>
                                    update(() => progressEntries.remove(entry)),
                                icon: const Icon(Icons.close, size: 17),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Phase>(
                    initialValue: target,
                    decoration: const InputDecoration(labelText: '所属阶段'),
                    isExpanded: true,
                    items: p.phases
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => target = v!,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in [
                        ('todo', '未开始'),
                        ('doing', '进行中'),
                        ('done', '已完成'),
                      ])
                        ChoiceChip(
                          label: Text(s.$2),
                          selected: status == s.$1,
                          onSelected: (_) => update(() => status = s.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 1; i <= 3; i++)
                        ChoiceChip(
                          label: Text(['简单', '中等', '较难'][i - 1]),
                          selected: difficulty == i,
                          onSelected: (_) => update(() => difficulty = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final type in ['安排', '截止'])
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                            ),
                            label: Text(
                              '$type：${(type == '安排' ? scheduled : deadline) ?? '未设置'}',
                            ),
                            onPressed: () async {
                              final old = type == '安排' ? scheduled : deadline;
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate: old == null
                                    ? DateTime.now()
                                    : DateTime.parse(old),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (date != null) {
                                update(() {
                                  if (type == '安排') {
                                    scheduled = dateKey(date);
                                    scheduleDates = [scheduled!];
                                    scheduleTimes = {
                                      if (scheduledTime != null)
                                        scheduled!: scheduledTime!,
                                    };
                                  } else {
                                    deadline = dateKey(date);
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: '清除$type日期',
                          onPressed: () => update(() {
                            if (type == '安排') {
                              scheduled = null;
                              scheduleDates = [];
                              scheduleTimes = {};
                              scheduledTime = null;
                              reminderMinutes = null;
                            } else {
                              deadline = null;
                            }
                          }),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  if (scheduleDates.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final day in scheduleDates)
                          InputChip(
                            label: Text('$day ${scheduleTimes[day] ?? '未设时间'}'),
                            onPressed: () async {
                              final previous = scheduleTimes[day];
                              final initial = previous == null
                                  ? TimeOfDay.now()
                                  : TimeOfDay(
                                      hour: int.parse(previous.split(':')[0]),
                                      minute: int.parse(previous.split(':')[1]),
                                    );
                              final time = await showTimePicker(
                                context: ctx,
                                initialTime: initial,
                              );
                              if (time != null) {
                                update(() {
                                  scheduleTimes[day] =
                                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                  scheduledTime =
                                      scheduleTimes[scheduleDates.first];
                                });
                              }
                            },
                            onDeleted: () => update(() {
                              scheduleTimes.remove(day);
                              scheduleDates.remove(day);
                              scheduled = scheduleDates.firstOrNull;
                              if (scheduleDates.isEmpty) {
                                scheduledTime = null;
                                reminderMinutes = null;
                              }
                            }),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 15),
                          label: const Text('增加一天'),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime.parse(scheduleDates.last),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (date != null) {
                              update(() {
                                scheduleDates.add(dateKey(date));
                                scheduleDates = scheduleDates.toSet().toList()
                                  ..sort();
                                if (scheduledTime != null) {
                                  scheduleTimes[dateKey(date)] = scheduledTime!;
                                }
                                scheduled = scheduleDates.first;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_outlined, size: 16),
                    label: Text('统一设置开始时间：${scheduledTime ?? '未设置'}'),
                    onPressed: scheduled == null
                        ? null
                        : () async {
                            final initial = scheduledTime == null
                                ? TimeOfDay.now()
                                : TimeOfDay(
                                    hour: int.parse(
                                      scheduledTime!.split(':')[0],
                                    ),
                                    minute: int.parse(
                                      scheduledTime!.split(':')[1],
                                    ),
                                  );
                            final time = await showTimePicker(
                              context: ctx,
                              initialTime: initial,
                            );
                            if (time != null) {
                              update(() {
                                scheduledTime =
                                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                scheduleTimes = {
                                  for (final date in scheduleDates)
                                    date: scheduledTime!,
                                };
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: estimatedMinutes,
                    decoration: const InputDecoration(labelText: '预计耗时'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('未设置')),
                      DropdownMenuItem(value: 15, child: Text('15 分钟')),
                      DropdownMenuItem(value: 30, child: Text('30 分钟')),
                      DropdownMenuItem(value: 60, child: Text('1 小时')),
                      DropdownMenuItem(value: 90, child: Text('1.5 小时')),
                      DropdownMenuItem(value: 120, child: Text('2 小时')),
                      DropdownMenuItem(value: 180, child: Text('3 小时')),
                    ],
                    onChanged: (value) =>
                        update(() => estimatedMinutes = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: reminderMinutes,
                    decoration: const InputDecoration(labelText: '提醒'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('不提醒')),
                      DropdownMenuItem(value: 0, child: Text('开始时提醒')),
                      DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
                      DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
                      DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
                      DropdownMenuItem(value: 60, child: Text('提前 1 小时')),
                    ],
                    onChanged: scheduleTimes.isEmpty
                        ? null
                        : (value) => update(() => reminderMinutes = value),
                  ),
                  if (scheduleTimes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '点击日期可单独设置开始时间；设置后可开启提醒。',
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (current != null && phase.tasks.indexOf(current) > 0)
              TextButton(
                onPressed: () {
                  final index = phase.tasks.indexOf(current);
                  phase.tasks.removeAt(index);
                  phase.tasks.insert(index - 1, current);
                  save();
                  Navigator.pop(ctx);
                },
                child: const Text('上移'),
              ),
            if (current != null &&
                phase.tasks.indexOf(current) < phase.tasks.length - 1)
              TextButton(
                onPressed: () {
                  final index = phase.tasks.indexOf(current);
                  phase.tasks.removeAt(index);
                  phase.tasks.insert(index + 1, current);
                  save();
                  Navigator.pop(ctx);
                },
                child: const Text('下移'),
              ),
            if (current != null)
              TextButton(
                onPressed: () {
                  store.trashTask(p, phase, current);
                  save();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('任务已移入回收站'),
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () {
                          if (store.restoreTrashTask(current.id)) save();
                        },
                      ),
                    ),
                  );
                },
                child: const Text('删除', style: TextStyle(color: toneLate)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) {
                  toast('请填写名称后再保存');
                  return;
                }
                final task = current ?? PlanTask(title: title.text.trim());
                task.title = title.text.trim();
                task.note = note.text.trim();
                task.updates = progressEntries;
                task.difficulty = difficulty;
                task.status = status;
                task.scheduleDates = scheduleDates;
                task.scheduled = scheduleDates.firstOrNull;
                task.scheduleTimes = scheduleTimes;
                task.scheduledTime =
                    scheduleTimes[task.scheduled] ?? scheduledTime;
                task.deadline = deadline;
                task.estimatedMinutes = estimatedMinutes;
                task.reminderMinutes = reminderMinutes;
                if (reminderMinutes != null) {
                  final permitted = await reminders.requestPermission();
                  await store.preferences.setBool(
                    'reminders.enabled',
                    permitted,
                  );
                  if (!ctx.mounted) return;
                  if (!permitted) {
                    toast('系统未授予提醒权限，任务已保存；可在系统设置中开启通知。');
                  }
                }
                if (current == null) {
                  target.tasks.add(task);
                } else if (target != phase) {
                  phase.tasks.remove(task);
                  target.tasks.add(task);
                }
                save();
                Navigator.pop(ctx);
              },
              child: const Text('保存任务'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    note.dispose();
    progressText.dispose();
  }

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('设置', '管理本地数据与服务连接。'),
      panel(
        Column(
          children: [
            ListTile(
              leading: Icon(
                widget.dark ? Icons.dark_mode : Icons.light_mode_outlined,
                color: widget.dark ? Colors.amber.shade500 : null,
              ),
              title: const Text('外观模式'),
              subtitle: Text(switch (widget.appearance) {
                AppearanceMode.light => '浅色模式',
                AppearanceMode.dark => '深色模式',
                AppearanceMode.automatic =>
                  '跟随当地时间 · 当前${widget.dark ? '深色' : '浅色'}',
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: appearanceDialog,
            ),
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text(cloud.connected ? cloud.email : '本地工作空间'),
              subtitle: Text(cloud.message),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('账号与云同步'),
              subtitle: Text(cloud.connected ? cloud.message : '登录同一账号，在设备间同步'),
              trailing: const Icon(Icons.chevron_right),
              onTap: cloudDialog,
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI 规划服务'),
              subtitle: Text(_aiConfigurationSummary()),
              trailing: const Icon(Icons.chevron_right),
              onTap: configureAi,
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('本机任务提醒'),
              subtitle: Text(
                store.preferences.getBool('reminders.enabled') ?? false
                    ? '已开启 · 打开后会重新登记未来提醒'
                    : '未开启 · 仅在当前设备发送通知',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: configureReminders,
            ),
          ],
        ),
      ),
      label('数据与备份'),
      if (store.imports.isNotEmpty)
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('导入历史'),
          subtitle: Text('已保留 ${store.imports.length} 批，可撤销最近导入'),
          trailing: const Icon(Icons.chevron_right),
          onTap: importHistoryDialog,
        ),
      if (store.trash.isNotEmpty)
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('回收站'),
          subtitle: Text('已保留 ${store.trash.length} 项可恢复任务'),
          trailing: const Icon(Icons.chevron_right),
          onTap: trashDialog,
        ),
      for (final item in [
        ('cloud.backup', '复制同步前的本地备份'),
        ('cloud.remote.backup', '复制被替换的云端备份'),
        ('richeng.recovery', '复制异常数据备份'),
      ])
        if (store.preferences.containsKey(item.$1))
          ListTile(
            title: Text(item.$2),
            leading: const Icon(Icons.history),
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: store.preferences.getString(item.$1)!),
              );
              if (mounted) toast('已复制，可通过恢复备份追加导入');
            },
          ),
      panel(
        Column(
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制完整备份'),
              subtitle: const Text('包含全部项目、任务、日期和完成状态'),
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: store.error == null
                        ? store.export()
                        : store.preferences.getString('richeng.data.v1') ??
                              '[]',
                  ),
                );
                if (mounted) toast('备份已复制，请保存到安全位置');
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('从备份恢复'),
              subtitle: const Text('校验内容后追加为新项目，保留当前数据'),
              onTap: restoreBackup,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        '日程 0.4.1 · 本地优先同步\n提醒通知、系统日历同步尚未启用。',
        style: TextStyle(fontSize: 12, color: secondary),
      ),
    ],
  );

  String _aiConfigurationSummary() {
    if (store.preferences.getString('ai.mode') == AiMode.personal.name) {
      final model = store.preferences.getString('ai.personal.model');
      return model == null || model.isEmpty ? '个人接口 · 未选择模型' : '个人接口 · $model';
    }
    return store.preferences.getString('ai.endpoint') ?? '未配置 · 可使用本地清单整理';
  }

  Future<void> importHistoryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('导入历史'),
          content: SizedBox(
            width: dialogWidth(ctx, 500),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: store.imports.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final batch = store.imports[index];
                final changed = store.importBatchChanged(batch);
                final taskCount = batch.phaseSnapshots
                    .map(
                      (phase) => (phase['tasks'] as List? ?? const []).length,
                    )
                    .fold<int>(0, (total, count) => total + count);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(batch.sourceLabel),
                  subtitle: Text(
                    '${dateKey(batch.createdAt)} · $taskCount 项任务${changed ? ' · 导入内容已修改' : ''}',
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      var confirmed = true;
                      if (changed) {
                        confirmed =
                            await showDialog<bool>(
                              context: context,
                              builder: (confirmCtx) => AlertDialog(
                                title: const Text('导入内容已修改'),
                                content: const Text(
                                  '撤销会删除这一批导入的阶段和任务，其中部分内容已被编辑。仍要撤销吗？',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmCtx, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(confirmCtx, true),
                                    child: const Text('仍然撤销'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                      }
                      if (confirmed && store.undoImportBatch(batch)) {
                        save();
                        update(() {});
                      }
                    },
                    child: const Text('撤销导入'),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> trashDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('回收站'),
          content: SizedBox(
            width: dialogWidth(ctx, 480),
            child: store.trash.isEmpty
                ? const Text('回收站为空。')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: store.trash.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final entry = store.trash[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.task.title),
                        subtitle: Text(
                          '${entry.projectTitle} · ${entry.phaseTitle}',
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            if (store.restoreTrashTask(entry.task.id)) {
                              save();
                              update(() {});
                            }
                          },
                          child: const Text('恢复'),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> appearanceDialog() async {
    var selectedMode = widget.appearance;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('外观模式'),
          content: SizedBox(
            width: dialogWidth(ctx, 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择适合当前环境的显示方式。自动模式使用设备当地时间，在晚上 19:00 至早上 07:00 显示深色模式。',
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in AppearanceMode.values)
                      ChoiceChip(
                        label: Text(switch (mode) {
                          AppearanceMode.light => '浅色模式',
                          AppearanceMode.dark => '深色模式',
                          AppearanceMode.automatic => '按当地时间自动切换',
                        }),
                        selected: selectedMode == mode,
                        onSelected: (_) => update(() => selectedMode = mode),
                      ),
                  ],
                ),
                if (selectedMode == AppearanceMode.automatic)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '当前将使用 ${isAutomaticDark(DateTime.now()) ? '深色' : '浅色'} 模式',
                      style: const TextStyle(fontSize: 12, color: secondary),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await widget.onAppearanceChanged(selectedMode);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> configureReminders() async {
    final permitted = await reminders.requestPermission();
    await store.preferences.setBool('reminders.enabled', permitted);
    if (permitted) await reminders.sync(store.projects);
    if (!mounted) return;
    if (!permitted) {
      toast('通知权限未开启，请在 Android 系统设置中允许“日程”发送通知。');
      refresh();
      return;
    }
    final test = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('本机提醒已开启'),
        content: const Text('未来任务提醒已重新登记。现在发送一条测试通知吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后测试'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('发送测试'),
          ),
        ],
      ),
    );
    if (test == true) {
      await reminders.showTest();
      if (mounted) toast('测试通知已发送，请查看系统通知栏。');
    }
    refresh();
  }

  Future<void> configureAi() async {
    final configuration = await AiConfiguration.load(store.preferences);
    if (!mounted) return;
    final server = TextEditingController(text: configuration.serverEndpoint);
    final baseUrl = TextEditingController(text: configuration.apiBaseUrl);
    final model = TextEditingController(text: configuration.model);
    final apiKey = TextEditingController();
    var selectedMode = configuration.mode;
    var checking = false;
    var fetchingModels = false;
    var apiKeyVisible = false;
    AiProviderPreset? selectedPreset;
    var detectedModels = <String>[];
    String? status;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('AI 规划服务'),
          content: SizedBox(
            width: dialogWidth(ctx, 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<AiMode>(
                  segments: const [
                    ButtonSegment(
                      value: AiMode.server,
                      icon: Icon(Icons.cloud_outlined),
                      label: Text('服务端 AI'),
                    ),
                    ButtonSegment(
                      value: AiMode.personal,
                      icon: Icon(Icons.key_outlined),
                      label: Text('个人接口'),
                    ),
                  ],
                  selected: {selectedMode},
                  onSelectionChanged: checking
                      ? null
                      : (value) => update(() {
                          selectedMode = value.first;
                          status = null;
                        }),
                ),
                const SizedBox(height: 16),
                if (selectedMode == AiMode.server) ...[
                  const Text(
                    '填写日程服务根地址，软件会自动补全 /api/plan。模型密钥仅保存在服务端。',
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'AI 服务根地址',
                      hintText: 'https://你的服务',
                    ),
                  ),
                  if (cloud.endpoint.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          update(() => server.text = cloud.endpoint),
                      icon: const Icon(Icons.cloud_outlined, size: 16),
                      label: const Text('使用当前同步服务器'),
                    ),
                  ],
                ] else ...[
                  const Text(
                    '填写兼容 OpenAI Chat Completions 的接口、模型和 API Key。Key 只安全保存在当前设备，不会备份或同步。',
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '服务商预设',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in aiProviderPresets)
                        ChoiceChip(
                          label: Text(preset.name),
                          selected: selectedPreset == preset,
                          onSelected: checking || fetchingModels
                              ? null
                              : (_) => update(() {
                                  selectedPreset = preset;
                                  baseUrl.text = preset.endpoint;
                                  if (model.text.trim().isEmpty) {
                                    model.text = preset.models.first;
                                  }
                                  detectedModels = preset.models;
                                  status = null;
                                }),
                        ),
                      ChoiceChip(
                        label: const Text('自定义'),
                        selected: selectedPreset == null,
                        onSelected: checking || fetchingModels
                            ? null
                            : (_) => update(() {
                                selectedPreset = null;
                                detectedModels = [];
                              }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: baseUrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onChanged: (_) => selectedPreset = null,
                    decoration: const InputDecoration(
                      labelText: 'API 地址',
                      hintText: 'https://api.openai.com/v1',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: apiKey,
                    obscureText: !apiKeyVisible,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: configuration.hasApiKey
                          ? '已安全保存；留空则继续使用'
                          : '请输入 API Key',
                      suffixIcon: IconButton(
                        tooltip: apiKeyVisible ? '隐藏 API Key' : '显示 API Key',
                        onPressed: () =>
                            update(() => apiKeyVisible = !apiKeyVisible),
                        icon: Icon(
                          apiKeyVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: checking || fetchingModels
                            ? null
                            : () async {
                                final endpoint = normalizeOpenAiEndpoint(
                                  baseUrl.text,
                                );
                                final key = apiKey.text.trim().isNotEmpty
                                    ? apiKey.text.trim()
                                    : await AiConfiguration.readApiKey(
                                        store.preferences,
                                      );
                                if (endpoint == null ||
                                    key == null ||
                                    key.isEmpty) {
                                  update(
                                    () => status = '请先填写 API 地址和 API Key。',
                                  );
                                  return;
                                }
                                update(() {
                                  fetchingModels = true;
                                  status = null;
                                });
                                try {
                                  final models = await fetchPersonalModels(
                                    endpoint: endpoint,
                                    apiKey: key,
                                  );
                                  if (!ctx.mounted) return;
                                  update(() {
                                    detectedModels = models;
                                    if (!models.contains(model.text.trim())) {
                                      model.text = models.first;
                                    }
                                    status =
                                        '已识别 ${models.length} 个模型，请选择或手动填写。';
                                  });
                                } catch (exception) {
                                  if (ctx.mounted) {
                                    update(
                                      () => status =
                                          '获取模型失败：${exception.toString().replaceFirst('Exception: ', '')}',
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    update(() => fetchingModels = false);
                                  }
                                }
                              },
                        icon: const Icon(
                          Icons.cloud_download_outlined,
                          size: 16,
                        ),
                        label: Text(fetchingModels ? '获取中…' : '获取模型'),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '地址与 Key 可用后读取 /models。',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: model,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      hintText: '例如 gpt-4o-mini',
                    ),
                  ),
                  if (detectedModels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '可用模型',
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 74,
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final availableModel in detectedModels)
                              ChoiceChip(
                                label: Text(availableModel),
                                selected: model.text.trim() == availableModel,
                                onSelected: checking || fetchingModels
                                    ? null
                                    : (_) => update(
                                        () => model.text = availableModel,
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    '网页端要求接口允许跨域访问。HTTP 网页无法使用安全存储时，Key 仅保存在此浏览器本机；建议使用 HTTPS。',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ],
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      status!,
                      style: TextStyle(
                        fontSize: 12,
                        color: status!.startsWith('服务可用')
                            ? toneReady
                            : toneLate,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: checking
                  ? null
                  : () async {
                      await AiConfiguration.clear(store.preferences);
                      if (ctx.mounted) Navigator.pop(ctx);
                      refresh();
                    },
              child: const Text('清空'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: checking
                  ? null
                  : () async {
                      final endpoint = selectedMode == AiMode.server
                          ? normalizeAiEndpoint(server.text)
                          : normalizeOpenAiEndpoint(baseUrl.text);
                      final key = apiKey.text.trim().isNotEmpty
                          ? apiKey.text.trim()
                          : await AiConfiguration.readApiKey(store.preferences);
                      if (endpoint == null ||
                          (selectedMode == AiMode.personal &&
                              (model.text.trim().isEmpty ||
                                  key == null ||
                                  key.isEmpty))) {
                        update(
                          () => status = selectedMode == AiMode.server
                              ? '请输入完整的 HTTP 或 HTTPS 服务地址。'
                              : '请填写 API 地址、模型名称和 API Key。',
                        );
                        return;
                      }
                      update(() {
                        checking = true;
                        status = null;
                      });
                      try {
                        final response = await http
                            .get(
                              selectedMode == AiMode.server
                                  ? aiHealthUri(endpoint)
                                  : modelsEndpoint(endpoint),
                              headers: selectedMode == AiMode.personal
                                  ? {'Authorization': 'Bearer $key'}
                                  : null,
                            )
                            .timeout(const Duration(seconds: 10));
                        if (response.statusCode < 200 ||
                            response.statusCode >= 300) {
                          throw Exception();
                        }
                        if (selectedMode == AiMode.personal) {
                          update(() => status = '接口可用，认证已通过。请保存后在 AI 分析中验证模型。');
                        } else {
                          final data = jsonDecode(
                            utf8.decode(response.bodyBytes),
                          );
                          update(
                            () => status = data is Map && data['ai'] == true
                                ? '服务可用，AI 模型已配置。'
                                : '服务可达，但服务端尚未配置 AI 模型。',
                          );
                        }
                      } catch (_) {
                        update(() => status = '无法连接服务，请检查地址、网络和服务器状态。');
                      } finally {
                        if (ctx.mounted) update(() => checking = false);
                      }
                    },
              child: Text(checking ? '测试中…' : '测试连接'),
            ),
            FilledButton(
              onPressed: checking
                  ? null
                  : () async {
                      final serverEndpoint = server.text.trim().isEmpty
                          ? ''
                          : normalizeAiEndpoint(server.text);
                      final personalEndpoint = baseUrl.text.trim().isEmpty
                          ? ''
                          : normalizeOpenAiEndpoint(baseUrl.text);
                      final isValid = selectedMode == AiMode.server
                          ? serverEndpoint != null
                          : personalEndpoint != null &&
                                model.text.trim().isNotEmpty &&
                                (apiKey.text.trim().isNotEmpty ||
                                    configuration.hasApiKey);
                      if (!isValid) {
                        toast(
                          selectedMode == AiMode.server
                              ? '请输入完整的 HTTP 或 HTTPS 地址'
                              : '请填写 API 地址、模型名称和 API Key',
                        );
                        return;
                      }
                      await AiConfiguration.save(
                        store.preferences,
                        mode: selectedMode,
                        serverEndpoint: serverEndpoint ?? '',
                        apiBaseUrl: personalEndpoint ?? '',
                        model: model.text.trim(),
                        apiKey: apiKey.text.trim().isEmpty
                            ? null
                            : apiKey.text.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      refresh();
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    server.dispose();
    baseUrl.dispose();
    model.dispose();
    apiKey.dispose();
  }

  Future<void> restoreBackup() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份'),
        content: SizedBox(
          width: dialogWidth(ctx, 500),
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(hintText: '粘贴完整 JSON 备份'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final restored = (jsonDecode(controller.text) as List)
                    .map((j) => Project.fromJson(Map<String, dynamic>.from(j)))
                    .toList();
                for (final p in restored) {
                  p.id = newId();
                  for (final s in p.phases) {
                    s.id = newId();
                    for (final t in s.tasks) {
                      t.id = newId();
                    }
                  }
                }
                store.projects.addAll(restored);
                save();
                Navigator.pop(ctx);
                toast('已恢复 ${restored.length} 个项目');
              } catch (_) {
                toast('备份格式不正确，请使用完整的日程备份');
              }
            },
            child: const Text('追加恢复'),
          ),
        ],
      ),
    );
  }

  Future<void> cloudDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => CloudDialog(cloud: cloud),
    );
  }

  Future<void> importPlan() async {
    final source = TextEditingController();
    final name = TextEditingController(text: '导入的计划');
    final excluded = <String>{};
    List<Phase>? preview;
    String? error;
    bool busy = false, append = project != null;
    bool goalMode = false;
    String? goalDeadline;
    var weeklyHours = 6;
    String sourceLabel = '本地清单整理';
    // 一个弹窗生命周期只对应一个导入批次，双击确认也不会生成重复导入。
    final importBatchId = newId();
    final destination = project;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(preview == null ? '把材料变成计划' : '确认导入内容'),
          content: SizedBox(
            width: dialogWidth(ctx, 650),
            height: MediaQuery.sizeOf(ctx).height.clamp(360, 460).toDouble(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview == null
                      ? '可从已有材料提取，也可按目标、截止日期和每周可用时间生成计划。'
                      : '检查阶段和任务。点击标题可修改，取消勾选可排除任务。',
                  style: const TextStyle(fontSize: 12, color: secondary),
                ),
                const SizedBox(height: 16),
                if (preview == null)
                  Expanded(
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('从材料提取'),
                              selected: !goalMode,
                              onSelected: (_) => update(() => goalMode = false),
                            ),
                            ChoiceChip(
                              label: const Text('按目标规划'),
                              selected: goalMode,
                              onSelected: (_) => update(() => goalMode = true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (goalMode) ...[
                          TextField(
                            controller: source,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: '目标',
                              hintText: '例如：在截止日前完成毕业设计并通过答辩',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.event_outlined,
                                    size: 16,
                                  ),
                                  label: Text('截止日期：${goalDeadline ?? '请选择'}'),
                                  onPressed: () async {
                                    final date = await showDatePicker(
                                      context: ctx,
                                      initialDate: goalDeadline == null
                                          ? DateTime.now().add(
                                              const Duration(days: 30),
                                            )
                                          : DateTime.parse(goalDeadline!),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date != null) {
                                      update(
                                        () => goalDeadline = dateKey(date),
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: weeklyHours,
                                  decoration: const InputDecoration(
                                    labelText: '每周可用时间',
                                  ),
                                  items: [2, 4, 6, 8, 10, 15, 20, 30]
                                      .map(
                                        (hours) => DropdownMenuItem(
                                          value: hours,
                                          child: Text('$hours 小时'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (hours) => update(
                                    () => weeklyHours = hours ?? weeklyHours,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              'AI 生成的日期均为建议；无法确定的日期会标记为待确认。',
                              style: TextStyle(fontSize: 12, color: secondary),
                            ),
                          ),
                        ] else
                          Expanded(
                            child: TextField(
                              controller: source,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: const InputDecoration(
                                hintText: '# 准备阶段\n- 整理研究资料\n- [x] 确定选题\n\n# 开始执行\n- 完成第一版方案',
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else ...[
                  if (destination != null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '追加到「${destination.title}」',
                        style: const TextStyle(fontSize: 13),
                      ),
                      value: append,
                      onChanged: (v) => update(() => append = v!),
                    ),
                  if (!append)
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '新项目名称'),
                    ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final phase in preview!) ...[
                          TextFormField(
                            initialValue: phase.title,
                            decoration: const InputDecoration(
                              labelText: '阶段名称',
                              isDense: true,
                            ),
                            onChanged: (v) => phase.title = v,
                          ),
                          for (final task in phase.tasks)
                            Row(
                              children: [
                                Checkbox(
                                  value: !excluded.contains(task.id),
                                  onChanged: (v) => update(
                                    () => v!
                                        ? excluded.remove(task.id)
                                        : excluded.add(task.id),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TextFormField(
                                        initialValue: task.title,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          filled: false,
                                          isDense: true,
                                        ),
                                        onChanged: (v) => task.title = v,
                                      ),
                                      if (task.note.isNotEmpty)
                                        Text(
                                          task.note,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: secondary,
                                          ),
                                        ),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Chip(
                                            label: Text(
                                              task.aiSuggested
                                                  ? 'AI 建议'
                                                  : '原文提取',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          if (task.needsDateConfirmation)
                                            const Chip(
                                              label: Text('日期待确认'),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                        ],
                                      ),
                                      if (task.importSource != null)
                                        Text(
                                          '依据：${task.importSource}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: secondary,
                                          ),
                                        ),
                                      Text(
                                        '${task.done ? '已完成 · ' : ''}安排：${task.scheduled ?? '待安排'} · 截止：${task.deadline ?? '未设置'}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                ],
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: toneLate, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            if (preview != null)
              TextButton(
                onPressed: () => update(() => preview = null),
                child: const Text('返回编辑'),
              ),
            if (preview == null)
              OutlinedButton(
                onPressed: busy || goalMode
                    ? null
                    : () {
                        final parsed = parseOutline(source.text);
                        update(() {
                          if (parsed.isEmpty) {
                            error = '请先输入需要整理的清单。';
                          } else {
                            preview = parsed;
                            sourceLabel = '本地清单整理';
                            error = null;
                          }
                        });
                      },
                child: const Text('本地整理'),
              ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (preview != null) {
                        final phases = preview!
                            .map((s) {
                              s.tasks.removeWhere(
                                (t) =>
                                    excluded.contains(t.id) ||
                                    t.title.trim().isEmpty,
                              );
                              return s;
                            })
                            .where(
                              (s) =>
                                  s.tasks.isNotEmpty &&
                                  s.title.trim().isNotEmpty,
                            )
                            .toList();
                        if (phases.isEmpty ||
                            (!append && name.text.trim().isEmpty)) {
                          update(() => error = '请保留至少一项任务，并填写项目和阶段名称。');
                          return;
                        }
                        Project target;
                        final createdProject = !append || destination == null;
                        if (store.hasImportBatch(importBatchId)) {
                          update(() => error = '此导入批次已经完成，请勿重复导入。');
                          return;
                        }
                        final sameTitleCount =
                            destination?.tasks
                                .map((task) => task.title.trim())
                                .toSet()
                                .intersection(
                                  phases
                                      .expand((phase) => phase.tasks)
                                      .map((task) => task.title.trim())
                                      .toSet(),
                                )
                                .length ??
                            0;
                        if (append && destination != null) {
                          target = destination;
                          target.phases.addAll(phases);
                        } else {
                          target = Project(
                            title: name.text.trim(),
                            phases: phases,
                          );
                          store.projects.add(target);
                        }
                        final batch = store.recordImport(
                          target,
                          phases,
                          createdProject: createdProject,
                          sourceLabel: sourceLabel,
                          id: importBatchId,
                        );
                        selected = target.id;
                        page = 1;
                        showArchived = target.archived;
                        save();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '已导入 ${phases.expand((s) => s.tasks).length} 项任务${sameTitleCount > 0 ? '；发现 $sameTitleCount 项同名任务，均已保留' : ''}，可在设置的导入历史中撤销。',
                            ),
                            action: SnackBarAction(
                              label: '撤销',
                              onPressed: () {
                                store.undoImportBatch(batch);
                                if (createdProject) selected = null;
                                save();
                              },
                            ),
                          ),
                        );
                        return;
                      }
                      final aiConfiguration = await AiConfiguration.load(
                        store.preferences,
                      );
                      if (aiConfiguration.mode == AiMode.server &&
                          aiConfiguration.serverEndpoint.isEmpty) {
                        update(() => error = '尚未连接 AI 服务。可先使用本地整理，或在设置中配置。');
                        return;
                      }
                      final personalKey =
                          aiConfiguration.mode == AiMode.personal
                          ? await AiConfiguration.readApiKey(store.preferences)
                          : null;
                      final personalEndpoint =
                          aiConfiguration.mode == AiMode.personal
                          ? normalizeOpenAiEndpoint(aiConfiguration.apiBaseUrl)
                          : null;
                      if (aiConfiguration.mode == AiMode.personal &&
                          (personalEndpoint == null ||
                              aiConfiguration.model.isEmpty ||
                              personalKey == null ||
                              personalKey.isEmpty)) {
                        update(
                          () => error = '个人 AI 接口尚未配置完整，请在设置中填写地址、模型和 API Key。',
                        );
                        return;
                      }
                      if (source.text.trim().isEmpty) {
                        update(() => error = goalMode ? '请先填写目标。' : '请先输入材料。');
                        return;
                      }
                      if (goalMode && goalDeadline == null) {
                        update(() => error = '请为目标规划选择截止日期。');
                        return;
                      }
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        late final List<Phase> phases;
                        if (aiConfiguration.mode == AiMode.personal) {
                          phases = await requestPersonalPlan(
                            endpoint: personalEndpoint!,
                            apiKey: personalKey!,
                            model: aiConfiguration.model,
                            mode: goalMode ? 'goal' : 'material',
                            text: source.text,
                            today: dateKey(DateTime.now()),
                            deadline: goalMode ? goalDeadline : null,
                            weeklyHours: goalMode ? weeklyHours : null,
                          );
                        } else {
                          final endpoint = aiConfiguration.serverEndpoint;
                          final response = await http
                              .post(
                                Uri.parse(endpoint),
                                headers: {
                                  'Content-Type': 'application/json',
                                  if (cloud.connected &&
                                      Uri.parse(endpoint).origin ==
                                          Uri.parse(cloud.endpoint).origin)
                                    'Authorization': 'Bearer ${cloud.token}',
                                },
                                body: jsonEncode({
                                  'text': source.text,
                                  'today': dateKey(DateTime.now()),
                                  'mode': goalMode ? 'goal' : 'material',
                                  if (goalMode) 'deadline': goalDeadline,
                                  if (goalMode) 'weeklyHours': weeklyHours,
                                }),
                              )
                              .timeout(const Duration(seconds: 60));
                          if (response.statusCode != 200) {
                            throw Exception('服务返回 ${response.statusCode}');
                          }
                          final payload = jsonDecode(
                            utf8.decode(response.bodyBytes),
                          ) as Map<String, dynamic>;
                          phases = (payload['phases'] as List)
                              .map(
                                (s) => Phase.fromJson(
                                  Map<String, dynamic>.from(s),
                                ),
                              )
                              .toList();
                        }
                        if (phases.isEmpty ||
                            phases.expand((p) => p.tasks).isEmpty) {
                          throw Exception('未识别到任务');
                        }
                        // 模型返回的标识一律替换，避免与已有记录冲突。
                        for (final p in phases) {
                          p.id = newId();
                          for (final t in p.tasks) {
                            t.id = newId();
                          }
                        }
                        if (ctx.mounted) {
                          update(() {
                            preview = phases;
                            sourceLabel = goalMode ? 'AI 目标规划' : 'AI 材料分析';
                          });
                        }
                      } catch (exception) {
                        if (ctx.mounted) {
                          final message = exception.toString().replaceFirst(
                            'Exception: ',
                            '',
                          );
                          update(() => error = '分析失败：$message。原始材料已保留。');
                        }
                      } finally {
                        if (ctx.mounted) update(() => busy = false);
                      }
                    },
              child: Text(preview == null ? 'AI 分析' : '确认导入'),
            ),
          ],
        ),
      ),
    );
  }
}
