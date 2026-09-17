import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

// 登录时仅采集用户可见的设备名称与系统信息，不采集序列号或设备唯一标识。
Future<String> deviceDisplayName() async {
  final plugin = DeviceInfoPlugin();
  try {
    if (kIsWeb) {
      final web = await plugin.webBrowserInfo;
      return '日程网页 · ${_browserName(web.browserName)}';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = await plugin.androidInfo;
        final maker = _usable(android.manufacturer)
            ? android.manufacturer
            : android.brand;
        final model = _usable(android.model) ? android.model : android.device;
        final system = _usable(android.version.release)
            ? 'Android ${android.version.release}'
            : 'Android';
        return '日程 · ${_androidFormFactor()} · $maker $model · $system';
      case TargetPlatform.windows:
        final windows = await plugin.windowsInfo;
        final computer = _usable(windows.computerName)
            ? windows.computerName
            : 'Windows 设备';
        final product = _usable(windows.productName)
            ? windows.productName
            : 'Windows';
        final version = _usable(windows.displayVersion)
            ? ' ${windows.displayVersion}'
            : '';
        return '日程 · $computer · $product$version';
      default:
        return '日程 · ${defaultTargetPlatform.name}';
    }
  } catch (_) {
    // 中文说明：平台插件不可用时仍允许登录，并保留基础平台名称。
    return kIsWeb ? '日程网页' : '日程 · ${defaultTargetPlatform.name}';
  }
}

bool _usable(String value) => value.trim().isNotEmpty && value != 'unknown';

String _androidFormFactor() {
  // 中文说明：Android 官方常用 600dp 短边作为平板布局的分界线。
  final view = ui.PlatformDispatcher.instance.views.firstOrNull;
  if (view == null) return 'Android 设备';
  final size = view.physicalSize / view.devicePixelRatio;
  return size.shortestSide >= 600 ? '平板' : '手机';
}

String _browserName(BrowserName browser) {
  switch (browser) {
    case BrowserName.edge:
      return 'Microsoft Edge';
    case BrowserName.chrome:
      return 'Google Chrome';
    case BrowserName.firefox:
      return 'Firefox';
    case BrowserName.safari:
      return 'Safari';
    case BrowserName.samsungInternet:
      return 'Samsung Internet';
    case BrowserName.opera:
      return 'Opera';
    case BrowserName.msie:
      return 'Internet Explorer';
    case BrowserName.unknown:
      return '浏览器';
  }
}
