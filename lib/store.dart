import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

// 回收站只保存被删除任务及其原位置，避免误删后同步到其他设备就无法恢复。
class TrashedTask {
  final PlanTask task;
  final String projectId, phaseId, projectTitle, phaseTitle;
  final int index;
  final DateTime deletedAt;
  TrashedTask({
    required this.task,
    required this.projectId,
    required this.phaseId,
    required this.projectTitle,
    required this.phaseTitle,
    required this.index,
    DateTime? deletedAt,
  }) : deletedAt = deletedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'task': task.toJson(),
    'projectId': projectId,
    'phaseId': phaseId,
    'projectTitle': projectTitle,
    'phaseTitle': phaseTitle,
    'index': index,
    'deletedAt': deletedAt.toIso8601String(),
  };

  factory TrashedTask.fromJson(Map<String, dynamic> json) => TrashedTask(
    task: PlanTask.fromJson(Map<String, dynamic>.from(json['task'] as Map)),
    projectId: checkedTitle(json['projectId']),
    phaseId: checkedTitle(json['phaseId']),
    projectTitle: checkedTitle(json['projectTitle']),
    phaseTitle: checkedTitle(json['phaseTitle']),
    index: json['index'] is int && json['index'] >= 0 ? json['index'] : 0,
    deletedAt:
        DateTime.tryParse(json['deletedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

// 每批导入保存当时的快照，关闭应用后仍能判断是否可安全撤销。
class ImportBatch {
  final String id, projectId, sourceLabel;
  final bool createdProject;
  final DateTime createdAt;
  final List<Map<String, dynamic>> phaseSnapshots;
  final Map<String, dynamic>? projectSnapshot;
  ImportBatch({
    required this.id,
    required this.projectId,
    required this.sourceLabel,
    required this.createdProject,
    required this.phaseSnapshots,
    this.projectSnapshot,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'sourceLabel': sourceLabel,
    'createdProject': createdProject,
    'createdAt': createdAt.toIso8601String(),
    'phaseSnapshots': phaseSnapshots,
    'projectSnapshot': projectSnapshot,
  };

  factory ImportBatch.fromJson(Map<String, dynamic> json) => ImportBatch(
    id: checkedTitle(json['id']),
    projectId: checkedTitle(json['projectId']),
    sourceLabel: checkedTitle(json['sourceLabel']),
    createdProject: json['createdProject'] == true,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    phaseSnapshots: (json['phaseSnapshots'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(),
    projectSnapshot: json['projectSnapshot'] is Map
        ? Map<String, dynamic>.from(json['projectSnapshot'] as Map)
        : null,
  );
}

// 本地仓库串行写入，避免快速勾选时旧快照覆盖新快照。
class PlanStore extends ChangeNotifier {
  final SharedPreferences preferences;
  List<Project> projects;
  List<TrashedTask> trash;
  List<ImportBatch> imports;
  // 仅供界面在撤销后提示；归档状态本身会随项目数据持久保存。
  String? lastUndoArchivedProjectTitle;
  String? error;
  Future<void> _pending = Future.value();
  PlanStore(
    this.preferences,
    this.projects, {
    List<TrashedTask>? trash,
    List<ImportBatch>? imports,
  }) : trash = trash ?? [],
       imports = imports ?? [];
  static Future<PlanStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('richeng.data.v1');
    if (raw != null) {
      try {
        final trashRaw = prefs.getString('richeng.trash.v1');
        final importsRaw = prefs.getString('richeng.imports.v1');
        return PlanStore(
          prefs,
          (jsonDecode(raw) as List)
              .map((j) => Project.fromJson(Map<String, dynamic>.from(j)))
              .toList(),
          trash: trashRaw == null
              ? []
              : (jsonDecode(trashRaw) as List)
                    .map(
                      (j) => TrashedTask.fromJson(Map<String, dynamic>.from(j)),
                    )
                    .toList(),
          imports: importsRaw == null
              ? []
              : (jsonDecode(importsRaw) as List)
                    .map(
                      (j) => ImportBatch.fromJson(Map<String, dynamic>.from(j)),
                    )
                    .toList(),
        );
      } catch (_) {
        // 先保留异常原文，后续新任务保存也不会丢失恢复依据。
        await prefs.setString('richeng.recovery', raw);
        return PlanStore(prefs, [])..error = '本地数据无法读取，请先在设置中复制原始备份。';
      }
    }
    final seed =
        jsonDecode(await rootBundle.loadString('assets/seed.json')) as List;
    final store = PlanStore(prefs, [
      Project(
        title: '毕业设计项目进度清单',
        description: 'P0 → P8 · 每阶段任务从简到难',
        phases: seed
            .map(
              (p) => Phase(
                title: p['name'],
                period: p['weeks'],
                color: int.parse(
                  'ff${(p['bar'] as String).substring(1)}',
                  radix: 16,
                ),
                tasks: (p['tasks'] as List)
                    .map(
                      (t) => PlanTask(
                        title: t['n'],
                        note: t['hint'] ?? '',
                        difficulty: t['d'],
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    ]);
    await store.save();
    return store;
  }

  Future<void> save() {
    final snapshot = jsonEncode(projects.map((p) => p.toJson()).toList());
    final trashSnapshot = jsonEncode(
      trash.map((item) => item.toJson()).toList(),
    );
    final importsSnapshot = jsonEncode(
      imports.map((item) => item.toJson()).toList(),
    );
    notifyListeners();
    _pending = _pending.then((_) async {
      String? next;
      try {
        final saved = await Future.wait([
          preferences.setString('richeng.data.v1', snapshot),
          preferences.setString('richeng.trash.v1', trashSnapshot),
          preferences.setString('richeng.imports.v1', importsSnapshot),
        ]);
        if (saved.any((value) => !value)) {
          throw Exception();
        }
      } catch (_) {
        next = '保存失败，请复制备份后重试。';
      }
      // 只在错误状态真的变化时再通知一次，避免每次保存把界面刷新两遍。
      if (next != error) {
        error = next;
        notifyListeners();
      }
    });
    return _pending;
  }

  String export() =>
      const JsonEncoder.withIndent('  ')
          .convert(projects.map((p) => p.toJson()).toList());

  // 放入回收站时不改变任务标识，恢复后提醒和跨端定位仍可沿用原记录。
  void trashTask(Project project, Phase phase, PlanTask task) {
    final index = phase.tasks.indexOf(task);
    if (index < 0) return;
    phase.tasks.removeAt(index);
    trash.insert(
      0,
      TrashedTask(
        task: task,
        projectId: project.id,
        phaseId: phase.id,
        projectTitle: project.title,
        phaseTitle: phase.title,
        index: index,
      ),
    );
  }

  bool restoreTrashTask(String taskId) {
    final entry = trash.where((item) => item.task.id == taskId).firstOrNull;
    if (entry == null) return false;
    final project = projects
        .where((item) => item.id == entry.projectId)
        .firstOrNull;
    if (project == null) return false;
    var phase = project.phases
        .where((item) => item.id == entry.phaseId)
        .firstOrNull;
    // 阶段被删除或移动后，为恢复任务创建一个明确的容器。
    phase ??= Phase(title: '${entry.phaseTitle}（已恢复）');
    if (!project.phases.contains(phase)) project.phases.add(phase);
    phase.tasks.insert(entry.index.clamp(0, phase.tasks.length), entry.task);
    trash.remove(entry);
    return true;
  }

  ImportBatch recordImport(
    Project project,
    List<Phase> phases, {
    required bool createdProject,
    required String sourceLabel,
    String? id,
  }) {
    // 同一批次共享一个标识，避免按标题误判不同阶段的正常重复任务。
    final batchId = id ?? newId();
    for (final phase in phases) {
      for (final task in phase.tasks) {
        task.importBatchId = batchId;
      }
    }
    final batch = ImportBatch(
      id: batchId,
      projectId: project.id,
      sourceLabel: sourceLabel,
      createdProject: createdProject,
      phaseSnapshots: phases
          .map((phase) => Map<String, dynamic>.from(phase.toJson()))
          .toList(),
      projectSnapshot: createdProject
          ? Map<String, dynamic>.from(project.toJson())
          : null,
    );
    imports.insert(0, batch);
    return batch;
  }

  // 只阻止同一批次被重复写入，不按任务标题做删除或去重。
  bool hasImportBatch(String batchId) =>
      imports.any((batch) => batch.id == batchId);

  bool importBatchChanged(ImportBatch batch) {
    final project = projects
        .where((item) => item.id == batch.projectId)
        .firstOrNull;
    if (project == null) return true;
    if (batch.createdProject) {
      return jsonEncode(project.toJson()) != jsonEncode(batch.projectSnapshot);
    }
    for (final snapshot in batch.phaseSnapshots) {
      final current = project.phases
          .where((phase) => phase.id == snapshot['id'])
          .firstOrNull;
      if (current == null ||
          jsonEncode(current.toJson()) != jsonEncode(snapshot)) {
        return true;
      }
    }
    return false;
  }

  bool undoImportBatch(ImportBatch batch) {
    lastUndoArchivedProjectTitle = null;
    final project = projects
        .where((item) => item.id == batch.projectId)
        .firstOrNull;
    if (project == null) return false;
    if (batch.createdProject) {
      // 新建导入项目保留完整内容并移入归档，用户仍可查看或手动恢复。
      project.archived = true;
      lastUndoArchivedProjectTitle = project.title;
    } else {
      final phaseIds = batch.phaseSnapshots.map((item) => item['id']).toSet();
      project.phases.removeWhere((phase) => phaseIds.contains(phase.id));
    }
    imports.remove(batch);
    return true;
  }
}
