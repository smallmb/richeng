import 'package:flutter/material.dart';

import 'app.dart';
import 'store.dart';

// 先载入本地项目，再展示工作空间。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RichengApp(store: await PlanStore.load()));
}
