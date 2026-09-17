import 'package:flutter_test/flutter_test.dart';
import 'package:richeng/ai.dart';

void main() {
  test('个人接口地址会补全 Chat Completions 路径', () {
    expect(
      normalizeOpenAiEndpoint('https://example.com/v1/'),
      'https://example.com/v1/chat/completions',
    );
    expect(
      normalizeOpenAiEndpoint('https://example.com/v1/chat/completions'),
      'https://example.com/v1/chat/completions',
    );
    expect(normalizeOpenAiEndpoint('ftp://example.com'), isNull);
    expect(
      modelsEndpoint('https://example.com/v1/chat/completions').toString(),
      'https://example.com/v1/models',
    );
  });

  test('模型计划 JSON 会补齐任务字段', () {
    final phases = decodeAiPlan('''
```json
{"phases":[{"title":"准备","tasks":[{"title":"确定选题"}]}]}
```
''');

    expect(phases, hasLength(1));
    expect(phases.single.tasks.single.title, '确定选题');
    expect(phases.single.tasks.single.status, 'todo');
    expect(phases.single.tasks.single.aiSuggested, isTrue);
  });

  test('模型可返回面向用户的处理摘要', () {
    expect(
      planSummary('{"summary":["识别了目标","拆分了任务"],"phases":[]}'),
      '识别了目标\n拆分了任务',
    );
  });
}
