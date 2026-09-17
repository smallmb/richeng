import 'package:flutter_test/flutter_test.dart';
import 'package:richeng/models.dart';
import 'package:richeng/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 回收站写入本地后，重启应用仍能恢复到原阶段和原排序位置。
void main() {
  test('删除任务可在重启后从回收站恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = PlanTask(title: '第一项');
    final deleted = PlanTask(title: '要恢复的任务');
    final phase = Phase(title: '阶段', tasks: [first, deleted]);
    final project = Project(title: '项目', phases: [phase]);
    final store = PlanStore(preferences, [project]);

    store.trashTask(project, phase, deleted);
    await store.save();
    expect(phase.tasks, [first]);

    final afterRestart = await PlanStore.load();
    expect(afterRestart.trash, hasLength(1));
    expect(afterRestart.trash.single.task.title, '要恢复的任务');
    expect(afterRestart.restoreTrashTask(deleted.id), true);
    await afterRestart.save();

    expect(
      afterRestart.projects.single.phases.single.tasks.map((t) => t.title),
      ['第一项', '要恢复的任务'],
    );
    expect(afterRestart.trash, isEmpty);
  });

  test('导入批次重启后可识别修改并撤销', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final existing = Phase(title: '原有阶段');
    final imported = Phase(
      title: 'AI 导入',
      tasks: [PlanTask(title: '整理资料')],
    );
    final project = Project(title: '项目', phases: [existing, imported]);
    final store = PlanStore(preferences, [project]);
    final batch = store.recordImport(
      project,
      [imported],
      createdProject: false,
      sourceLabel: 'AI 材料分析',
    );
    await store.save();
    expect(imported.tasks.single.importBatchId, batch.id);

    final afterRestart = await PlanStore.load();
    final restoredBatch = afterRestart.imports.single;
    expect(restoredBatch.sourceLabel, 'AI 材料分析');
    expect(afterRestart.importBatchChanged(restoredBatch), false);
    afterRestart.projects.single.phases.last.tasks.single.note = '已人工修改';
    expect(afterRestart.importBatchChanged(restoredBatch), true);
    expect(afterRestart.undoImportBatch(restoredBatch), true);
    await afterRestart.save();
    expect(afterRestart.projects.single.phases, [
      isA<Phase>().having((phase) => phase.title, 'title', '原有阶段'),
    ]);
    expect(afterRestart.imports, isEmpty);
    expect(batch.id, isNotEmpty);
  });

  test('撤销新建导入项目会保留内容并移入归档', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final imported = Phase(
      title: 'AI 导入',
      tasks: [PlanTask(title: '整理资料')],
    );
    final project = Project(title: '导入计划', phases: [imported]);
    final store = PlanStore(preferences, [project]);
    final batch = store.recordImport(
      project,
      [imported],
      createdProject: true,
      sourceLabel: 'AI 材料分析',
    );

    expect(store.undoImportBatch(batch), isTrue);
    expect(store.projects.single.archived, isTrue);
    expect(store.projects.single.tasks, hasLength(1));
    expect(store.lastUndoArchivedProjectTitle, '导入计划');
    expect(store.imports, isEmpty);
  });
}
