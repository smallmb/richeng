import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'device_label.dart';
import 'models.dart';
import 'store.dart';

class _CloudConflict implements Exception {
  final Map<String, dynamic> response;
  const _CloudConflict(this.response);
}

class _MergeOutcome {
  final List<dynamic>? projects;
  final List<String> conflicts;
  const _MergeOutcome(this.projects, this.conflicts);
}

// 三方合并使用“上次同步版本、本机版本、云端版本”。固定 ID 让移动排序不会误判为新任务。
_MergeOutcome _mergeProjects(
  List<dynamic> base,
  List<dynamic> local,
  List<dynamic> remote,
) {
  final conflicts = <String>[];
  final result = _mergeList(base, local, remote, '项目', 'phases', conflicts);
  return _MergeOutcome(result, conflicts);
}

List<dynamic> _mergeList(
  List<dynamic> base,
  List<dynamic> local,
  List<dynamic> remote,
  String label,
  String? childKey,
  List<String> conflicts,
) {
  Map<String, Map<String, dynamic>> index(List<dynamic> source) => {
    for (final raw in source)
      if (raw is Map && raw['id'] is String)
        raw['id'] as String: Map<String, dynamic>.from(raw),
  };

  final baseById = index(base);
  final localById = index(local);
  final remoteById = index(remote);
  final ids = <String>[...remoteById.keys];
  for (final id in localById.keys) {
    if (!ids.contains(id)) ids.add(id);
  }
  for (final id in baseById.keys) {
    if (!ids.contains(id)) ids.add(id);
  }
  final result = <dynamic>[];
  for (final id in ids) {
    final merged = _mergeEntity(
      baseById[id],
      localById[id],
      remoteById[id],
      label,
      childKey,
      conflicts,
    );
    if (merged != null) result.add(merged);
  }
  return result;
}

Map<String, dynamic>? _mergeEntity(
  Map<String, dynamic>? base,
  Map<String, dynamic>? local,
  Map<String, dynamic>? remote,
  String label,
  String? childKey,
  List<String> conflicts,
) {
  final id = local?['id'] ?? remote?['id'] ?? base?['id'] ?? '未知';
  if (base == null) {
    if (local == null) return remote;
    if (remote == null) return local;
    if (!_same(local, remote)) conflicts.add('$label $id 被两端以不同内容新建');
    return local;
  }
  if (local == null || remote == null) {
    final survivor = local ?? remote;
    if (survivor != null && !_same(survivor, base)) {
      conflicts.add('$label $id 一端删除、另一端编辑');
      return survivor;
    }
    return null;
  }

  final merged = Map<String, dynamic>.from(remote);
  final keys = {...base.keys, ...local.keys, ...remote.keys};
  keys.remove(childKey);
  for (final key in keys) {
    final localChanged = !_same(local[key], base[key]);
    final remoteChanged = !_same(remote[key], base[key]);
    if (localChanged && remoteChanged && !_same(local[key], remote[key])) {
      conflicts.add('$label $id 的“$key”被两端同时修改');
    } else if (localChanged) {
      merged[key] = local[key];
    }
  }
  if (childKey != null) {
    final nextLabel = childKey == 'phases' ? '阶段' : '任务';
    merged[childKey] = _mergeList(
      List<dynamic>.from(base[childKey] as List? ?? const []),
      List<dynamic>.from(local[childKey] as List? ?? const []),
      List<dynamic>.from(remote[childKey] as List? ?? const []),
      nextLabel,
      childKey == 'phases' ? 'tasks' : null,
      conflicts,
    );
  }
  return merged;
}

bool _same(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);

// 初版按工作空间做乐观版本检查；发现并发修改时停下，不静默覆盖。
class CloudSession extends ChangeNotifier {
  final PlanStore store;
  String endpoint = '', email = '', token = '', message = '未连接云端';
  String rememberedEmail = '';
  String baseline = '';
  int revision = 0;
  bool busy = false,
      enabled = false,
      conflict = false,
      realtimeConnected = false;
  List<Map<String, dynamic>> devices = [];
  Timer? _timer;
  Timer? _reconnectTimer;
  Timer? _syncDebounce;
  Completer<void>? _queuedSync;
  WebSocketChannel? _socket;
  bool _disposed = false;
  CloudSession(this.store) {
    endpoint =
        store.preferences.getString('cloud.endpoint') ??
        'http://127.0.0.1:5318';
    rememberedEmail = store.preferences.getString('cloud.lastEmail') ?? '';
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (enabled && !conflict) sync();
    });
  }
  bool get connected => token.isNotEmpty;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _reconnectTimer?.cancel();
    _syncDebounce?.cancel();
    _queuedSync?.complete();
    _socket?.sink.close();
    super.dispose();
  }

  void _connectRealtime() {
    _socket?.sink.close();
    _reconnectTimer?.cancel();
    if (!enabled || token.isEmpty || endpoint.isEmpty) return;
    realtimeConnected = false;
    final base = Uri.parse(endpoint);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: {'token': token},
    );
    try {
      final channel = WebSocketChannel.connect(uri);
      _socket = channel;
      unawaited(
        channel.ready.then<void>((_) {
          realtimeConnected = true;
          message = '已同步 · WebSocket 实时连接已建立';
          notifyListeners();
        }, onError: (_) => _scheduleReconnect()),
      );
      channel.stream.listen(
        _onRealtimeMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    realtimeConnected = false;
    if (!enabled || _disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connectRealtime);
  }

  void _onRealtimeMessage(dynamic raw) {
    try {
      final event = jsonDecode(raw as String) as Map<String, dynamic>;
      if (event['type'] == 'sync' &&
          event['revision'] is int &&
          event['revision'] > revision) {
        unawaited(sync());
      }
    } catch (_) {
      // 中文说明：坏消息不影响 HTTP 轮询兜底。
    }
  }

  // 将连续编辑合并为一次上传：界面先本地保存，约半秒后立即同步。
  Future<void> queueSync() {
    if (!enabled || conflict || _disposed) return Future.value();
    _syncDebounce?.cancel();
    final pending = _queuedSync ??= Completer<void>();
    message = '待同步…';
    notifyListeners();
    _syncDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (busy) {
        // 首次同步、登录等操作进行时，保留这次修改，稍后再发出。
        _syncDebounce = Timer(const Duration(milliseconds: 450), () {
          unawaited(queueSync());
        });
        return;
      }
      try {
        // 等待最新本地快照落盘，离线时重启也不会丢失这次编辑。
        await store.save();
        await sync();
      } finally {
        if (!pending.isCompleted) pending.complete();
        if (identical(_queuedSync, pending)) _queuedSync = null;
      }
    });
    return pending.future;
  }

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$endpoint$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final response =
        await (body == null
                ? http.get(uri, headers: headers)
                : http.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 15));
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode == 409) {
      throw _CloudConflict(data);
    }
    if (response.statusCode >= 400) throw Exception(data['error'] ?? '服务请求失败');
    return data;
  }

  Future<void> login(
    String url,
    String account,
    String password,
    bool register, [
    String code = '',
  ]) async {
    if (busy) return;
    busy = true;
    message = '正在连接…';
    notifyListeners();
    try {
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(account.trim())) {
        throw Exception('请输入有效邮箱地址，例如 name@example.com');
      }
      final uri = Uri.parse(url);
      if (!['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw Exception('请输入有效的服务根地址');
      }
      endpoint = url.replaceFirst(RegExp(r'/+$'), '');
      final device = await deviceDisplayName();
      final response = await request(
        register ? '/api/register' : '/api/login',
        body: {
          'email': account,
          'password': password,
          if (register) 'code': code,
          'device': device,
        },
      );
      token = response['token'];
      email = response['email'];
      rememberedEmail = email;
      await store.preferences.setString('cloud.endpoint', endpoint);
      await store.preferences.setString('cloud.lastEmail', rememberedEmail);
      // 登录成功立即写入令牌。用户关闭首次同步选择页后也能继续当前账号。
      await _persistSession();
      message = '已登录，请选择首次同步方式';
      conflict = false;
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> requestEmailCode(String url, String account) async {
    if (busy) return;
    busy = true;
    message = '正在发送验证码…';
    notifyListeners();
    try {
      final uri = Uri.parse(url);
      if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
        throw Exception('请输入有效的服务根地址');
      }
      endpoint = url.replaceFirst(RegExp(r'/+$'), '');
      await request('/api/email/request', body: {'email': account});
      message = '验证码已发送，请在 10 分钟内填写。';
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> backup() async {
    if (!await store.preferences.setString('cloud.backup', store.export())) {
      throw Exception('无法创建同步前备份');
    }
  }

  // 保存可恢复的同步状态；本地任务数据仍由 PlanStore 单独保存。
  Future<void> _persistSession() async {
    await Future.wait([
      store.preferences.setString('cloud.token', token),
      store.preferences.setString('cloud.email', email),
      store.preferences.setString('cloud.baseline', baseline),
      store.preferences.setInt('cloud.revision', revision),
      store.preferences.setBool('cloud.enabled', enabled),
    ]);
  }

  Future<void> _clearSession() async {
    await Future.wait([
      store.preferences.remove('cloud.token'),
      store.preferences.remove('cloud.email'),
      store.preferences.remove('cloud.baseline'),
      store.preferences.remove('cloud.revision'),
      store.preferences.remove('cloud.enabled'),
    ]);
  }

  // 应用重启后恢复登录状态，并用上次的基线判断是否存在离线编辑。
  Future<void> restore() async {
    if (_disposed || busy || enabled) return;
    final savedToken = store.preferences.getString('cloud.token');
    final savedEmail = store.preferences.getString('cloud.email');
    final savedBaseline = store.preferences.getString('cloud.baseline');
    if (savedToken == null || savedEmail == null || savedBaseline == null) {
      return;
    }
    token = savedToken;
    email = savedEmail;
    baseline = savedBaseline;
    revision = store.preferences.getInt('cloud.revision') ?? 0;
    enabled = store.preferences.getBool('cloud.enabled') ?? false;
    message = enabled ? '正在恢复同步…' : '已恢复登录，请选择首次同步方式';
    notifyListeners();
    if (!enabled) return;
    _connectRealtime();
    await sync();
  }

  Future<void> choose(bool upload) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      final local = store.export();
      final remote = await request('/api/sync');
      await backup();
      // 两个方向都保留被替换版本，供设置页复制恢复。
      await store.preferences.setString(
        'cloud.remote.backup',
        jsonEncode(remote['projects']),
      );
      revision = remote['revision'];
      if (upload) {
        final result = await request(
          '/api/sync',
          body: {'revision': revision, 'projects': jsonDecode(local)},
        );
        revision = result['revision'];
        baseline = local;
      } else {
        if (store.export() != local) throw Exception('本地任务刚刚发生变化，请重试');
        store.projects = (remote['projects'] as List)
            .map((p) => Project.fromJson(Map<String, dynamic>.from(p)))
            .toList();
        baseline = store.export();
        await store.save();
      }
      enabled = true;
      conflict = false;
      await _persistSession();
      _connectRealtime();
      message = '已同步 · 正在建立实时连接';
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (busy || !enabled || conflict) return;
    busy = true;
    try {
      final local = store.export();
      if (local != baseline) {
        final result = await request(
          '/api/sync',
          body: {'revision': revision, 'projects': jsonDecode(local)},
        );
        revision = result['revision'];
        baseline = local;
      } else {
        final remote = await request('/api/sync');
        if (remote['revision'] != revision) {
          if (store.export() != local) {
            conflict = true;
            throw Exception('同步期间本地发生修改，请选择保留版本');
          }
          await backup();
          store.projects = (remote['projects'] as List)
              .map((p) => Project.fromJson(Map<String, dynamic>.from(p)))
              .toList();
          revision = remote['revision'];
          baseline = store.export();
          await store.save();
        }
      }
      message = realtimeConnected
          ? '已同步 · WebSocket 实时连接已建立'
          : '已同步 · HTTP 轮询兜底中';
      await _persistSession();
    } on _CloudConflict {
      await _mergeAndRetry();
    } catch (e) {
      message = conflict ? '两端都有修改，请在设置中处理冲突' : '同步失败，联网后自动重试';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _mergeAndRetry() async {
    try {
      final remote = await request('/api/sync');
      final base = jsonDecode(baseline) as List<dynamic>;
      final local = jsonDecode(store.export()) as List<dynamic>;
      final merged = _mergeProjects(
        base,
        local,
        List<dynamic>.from(remote['projects'] as List),
      );
      if (merged.conflicts.isNotEmpty || merged.projects == null) {
        conflict = true;
        message = '同步冲突：${merged.conflicts.firstOrNull ?? '请在设置中选择保留版本'}';
        return;
      }
      // 合并成功后先落盘，再以云端最新版本号提交，避免重试产生重复任务。
      store.projects = merged.projects!
          .map((item) => Project.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      await store.save();
      revision = remote['revision'] as int;
      final result = await request(
        '/api/sync',
        body: {'revision': revision, 'projects': merged.projects},
      );
      revision = result['revision'] as int;
      baseline = store.export();
      conflict = false;
      message = '已自动合并两端不同修改';
      await _persistSession();
    } catch (_) {
      conflict = true;
      message = '同步冲突，请在设置中选择要保留的版本';
    }
  }

  Future<void> logout() async {
    enabled = false;
    realtimeConnected = false;
    _reconnectTimer?.cancel();
    await _socket?.sink.close();
    _socket = null;
    try {
      await request('/api/logout', body: {});
    } catch (_) {
      /* 离线退出仍清除本机会话。 */
    }
    token = '';
    email = '';
    // 退出只移除会话令牌，保留邮箱和服务器地址方便下次安全登录。
    message = '未连接云端';
    conflict = false;
    devices = [];
    await _clearSession();
    notifyListeners();
  }

  Future<void> loadDevices() async {
    if (!connected || busy) return;
    busy = true;
    notifyListeners();
    try {
      final response = await request('/api/devices');
      devices = (response['devices'] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> revokeDevice(int id) async {
    if (!connected || busy) return;
    busy = true;
    notifyListeners();
    try {
      await request('/api/devices/revoke', body: {'id': id});
      final response = await request('/api/devices');
      devices = (response['devices'] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      message = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class CloudDialog extends StatefulWidget {
  final CloudSession cloud;
  const CloudDialog({super.key, required this.cloud});
  @override
  State<CloudDialog> createState() => _CloudDialogState();
}

class _CloudDialogState extends State<CloudDialog> {
  late final url = TextEditingController(text: widget.cloud.endpoint);
  late final email = TextEditingController(text: widget.cloud.rememberedEmail);
  final password = TextEditingController();
  final code = TextEditingController();
  bool register = false;
  @override
  void dispose() {
    url.dispose();
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> select(bool upload) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(upload ? '使用当前设备版本？' : '使用云端版本？'),
        content: Text(
          upload
              ? '当前设备的完整工作空间将替换云端版本。原云端版本会保留到本机的同步备份中。'
              : '云端工作空间将替换当前设备内容。当前内容会保留到同步前备份中。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认同步'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.cloud.choose(upload);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.cloud,
    builder: (context, _) {
      final c = widget.cloud;
      return AlertDialog(
        title: const Text('账号与同步'),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width.clamp(320, 440).toDouble(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!c.connected) ...[
                  const Text(
                    '连接同一服务，即可在不同设备使用同一账号。首次登录后选择要保留的工作空间。',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: url,
                    decoration: const InputDecoration(labelText: '服务根地址'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '邮箱'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码（至少 10 位）'),
                  ),
                  if (register) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: code,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: '邮箱验证码',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : () => c.requestEmailCode(
                                  url.text.trim(),
                                  email.text.trim(),
                                ),
                          child: const Text('发送验证码'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('注册新账号'),
                    value: register,
                    onChanged: c.busy
                        ? null
                        : (v) => setState(() => register = v!),
                  ),
                  const Text(
                    '支持 QQ、163、Gmail、Outlook 和企业邮箱等标准邮箱。会话会保留在当前设备；通过公网连接时，请使用 HTTPS 服务地址。',
                    style: TextStyle(fontSize: 12),
                  ),
                ] else ...[
                  Text(
                    c.email,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(c.endpoint),
                  const SizedBox(height: 16),
                  if (!c.enabled || c.conflict) ...[
                    OutlinedButton(
                      onPressed: c.busy ? null : () => select(true),
                      child: const Text('使用当前设备版本'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: c.busy ? null : () => select(false),
                      child: const Text('使用云端版本'),
                    ),
                  ] else
                    OutlinedButton(
                      onPressed: c.busy ? null : c.sync,
                      child: const Text('立即同步'),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: c.busy ? null : c.loadDevices,
                    icon: const Icon(Icons.devices_outlined, size: 16),
                    label: const Text('查看登录设备'),
                  ),
                  if (c.devices.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '登录设备',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    for (final device in c.devices)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          device['current'] == true
                              ? Icons.phone_android
                              : Icons.devices_other,
                          size: 18,
                        ),
                        title: Text(
                          '${device['name']}${device['current'] == true ? '（当前）' : ''}',
                        ),
                        trailing: device['current'] == true
                            ? null
                            : TextButton(
                                onPressed: c.busy
                                    ? null
                                    : () => c.revokeDevice(device['id'] as int),
                                child: const Text('移除'),
                              ),
                      ),
                  ],
                ],
                const SizedBox(height: 14),
                Text(
                  c.message,
                  style: TextStyle(
                    fontSize: 12,
                    // 与 app.dart 里的 toneLate 保持同一支红色；此文件不能反向 import app.dart。
                    color: c.conflict ? const Color(0xffc0553f) : null,
                  ),
                ),
                if (c.busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (c.connected)
            TextButton(
              onPressed: c.busy ? null : c.logout,
              child: const Text('退出账号'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (!c.connected)
            FilledButton(
              onPressed: c.busy
                  ? null
                  : () => c.login(
                      url.text.trim(),
                      email.text.trim(),
                      password.text,
                      register,
                      code.text.trim(),
                    ),
              child: Text(register ? '注册并登录' : '登录'),
            ),
        ],
      );
    },
  );
}
