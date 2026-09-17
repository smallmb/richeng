import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:richeng/cloud.dart';
import 'package:richeng/models.dart';
import 'package:richeng/store.dart';

// 两个独立客户端连接真实 Python 服务，验证同步与冲突保留。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 本用例连接临时本地服务，取消组件测试框架的模拟网络返回。
  HttpOverrides.global = null;
  test('账号登录、双端同步、并发修改保留本地版本', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'richeng-sync-test-',
    );
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final process = await Process.start(
      'python',
      ['server/server.py'],
      environment: {
        'RICHENG_DB': '${temporary.path}/test.sqlite3',
        'RICHENG_PORT': '$port',
        'PYTHONIOENCODING': 'utf-8',
      },
    );
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    final endpoint = 'http://127.0.0.1:$port';
    try {
      var ready = false;
      for (var i = 0; i < 40; i++) {
        try {
          ready =
              (await http.get(Uri.parse('$endpoint/health'))).statusCode == 200;
        } catch (_) {
          /* 等待测试服务绑定临时端口。 */
        }
        if (ready) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(ready, true);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = PlanStore(prefs, [
        Project(
          title: '测试项目',
          phases: [
            Phase(
              title: '准备',
              tasks: [PlanTask(title: '写初稿')],
            ),
          ],
        ),
      ]);
      final second = PlanStore(prefs, []);
      final a = CloudSession(first), b = CloudSession(second);
      try {
        await a.login(
          endpoint,
          'sync@example.test',
          'test-only-password',
          true,
        );
        expect(a.connected, true, reason: a.message);
        // 登录成功即保存会话；尚未选择同步方向时重启也不会要求重新输入账号密码。
        final awaitingChoice = CloudSession(first);
        await awaitingChoice.restore();
        expect(awaitingChoice.connected, true);
        expect(awaitingChoice.enabled, false);
        awaitingChoice.dispose();
        await a.choose(true);
        await b.login(
          endpoint,
          'sync@example.test',
          'test-only-password',
          false,
        );
        await b.choose(false);
        expect(second.projects.single.title, '测试项目');
        first.projects.single.tasks.single.status = 'done';
        await first.save();
        // 本地编辑经短暂合并后应主动上传，无需等待 8 秒轮询。
        await a.queueSync();
        await b.sync();
        expect(second.projects.single.tasks.single.done, true);
        // 模拟应用重启：应恢复会话和同步基线，而不是要求重新选择上传方式。
        final resumed = CloudSession(first);
        await resumed.restore();
        expect(resumed.enabled, true);
        expect(resumed.connected, true);
        resumed.dispose();
        // 两端编辑同一任务的不同字段时自动合并，而不是把整份清单判为冲突。
        first.projects.single.tasks.single.title = '设备一标题';
        second.projects.single.tasks.single.note = '设备二备注';
        await a.sync();
        await b.sync();
        expect(b.conflict, false, reason: b.message);
        expect(second.projects.single.tasks.single.title, '设备一标题');
        await a.sync();
        expect(first.projects.single.tasks.single.note, '设备二备注');
        // 相同字段的不同修改仍必须停下，让用户选择版本。
        first.projects.single.tasks.single.title = '设备一修改';
        second.projects.single.tasks.single.title = '设备二修改';
        await a.sync();
        await b.sync();
        expect(b.conflict, true);
        expect(second.projects.single.tasks.single.title, '设备二修改');
        final snapshot = jsonDecode(second.export()) as List;
        expect(snapshot.length, 1);
      } finally {
        a.dispose();
        b.dispose();
      }
    } finally {
      process.kill();
      await process.exitCode;
      // 仅清理本测试创建且处于临时目录内的目录。
      final root = Directory.systemTemp.absolute.path;
      if (temporary.absolute.path.startsWith(root) &&
          temporary.path.contains('richeng-sync-test-')) {
        await temporary.delete(recursive: true);
      }
    }
  });
}
