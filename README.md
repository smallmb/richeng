# 日程 Richeng

一款面向阶段型目标的个人项目与日程管理工具。它把“目标、截止日期、每周可用时间”整理为可审核的阶段计划，并支持 Android、Windows 和网页端同步执行。

当前版本：**0.5.8**

## 核心能力

- **项目与任务**：多项目、阶段、独立任务箱、归档、搜索、难度、任务状态、进度记录、回收站与恢复。
- **日程执行**：任务可设置多个执行日期、每个日期独立开始时间、预计时长、截止日期和提醒提前量。
- **今日页**：按开始时间展示时间轴；无时间任务显示为“全天”；逾期任务可勾选多项并批量重新安排，同时保留开始时间和截止日期。
- **提醒**：Android 本地通知会按每个执行日期及对应时间登记；可在设置中发送测试通知。
- **AI / 清单导入**：支持 Markdown 或纯文本清单整理，也支持“目标 + 截止日期 + 每周可用时间”生成计划。可使用服务端 AI，或在当前设备配置 OpenAI 兼容 API、模型和 API Key。预览会标注原文提取、AI 建议和待确认日期。
- **AI 处理反馈**：个人接口使用流式响应时，会显示服务商明确返回的处理过程；没有该字段的模型则展示阶段状态和最终处理摘要。分析期间使用六点环形动效反馈请求仍在进行。
- **导入历史**：每批导入持久保存，可撤销；批次内容已被人工修改时会先提示。同名任务不会被删除，只会提示并保留。
- **账号与同步**：邮箱注册登录、验证码注册、设备列表与移除、WebSocket 实时同步、HTTP 轮询兜底、三方字段合并和冲突提示。
- **本地可靠性**：自动保存、完整 JSON 备份、同步前备份、导入撤销和回收站都可在重启后继续使用。
- **外观**：浅色、深色、按当地时间自动切换；深色模式下“今天”显示黄色月亮图标。

## 体验与运行

### Flutter 客户端

```powershell
# 获取依赖并运行网页调试版
flutter pub get
flutter run -d chrome

# Android ARM64 发布包
flutter build apk --release --target-platform android-arm64

# 网页发布包
flutter build web --release
```

Windows 本地构建可使用：

```powershell
.\tool\build-windows.ps1
```

Windows 打包依赖 Visual Studio 的 C++ 桌面开发组件；若缺少 ATL 等组件，请先按 Flutter Windows 构建要求补齐 Visual Studio 工作负载。

### 本地服务

服务端需要 Python 3.9+。首次启动会安装 `websockets` 依赖：

```powershell
python -m pip install -r server\requirements.txt
python server\server.py
```

默认 HTTP API 是 `http://127.0.0.1:5318`，实时同步 WebSocket 是 `ws://127.0.0.1:5319/ws`。客户端在“设置 → 账号与云同步”中填写 HTTP 服务根地址。

首次同步时：

1. 第一台设备登录后选择“使用当前设备版本”。
2. 其他设备使用同一邮箱登录，选择“使用云端版本”。
3. 后续编辑会先本地保存，再通过 WebSocket 通知和 HTTP 同步。

登录令牌与同步基线会保存在当前设备；登录成功后即使尚未选择首次同步方向，关闭应用后也可恢复该账号。服务端会话有效期为 30 天。主动退出账号会清除本机令牌，但保留上次邮箱与服务地址供下次填写。

## AI 服务配置

复制配置模板：

```powershell
Copy-Item server\config.example.json server\config.local.json
```

在 `server/config.local.json` 填写以下字段：

- `AI_BASE_URL`：OpenAI 兼容接口根地址，通常以 `/v1` 结尾。
- `AI_MODEL`：模型名称。
- `AI_API_KEY`：模型密钥。

`config.local.json` 已被 Git 忽略，禁止提交。客户端“设置 → AI 规划服务”可直接使用同步服务器并测试 `/health` 连通性和服务端模型配置；保存根地址时会自动补全 `/api/plan`。

也可在“设置 → AI 规划服务 → 个人接口”选择 OpenAI、DeepSeek、通义千问、Kimi、智谱、SiliconFlow 等预设，或填写自定义 OpenAI Chat Completions 兼容 API 地址。填入 API Key 后点“获取模型”会读取接口的 `/models` 清单，也可手动填写模型名称，并可用显示按钮检查输入的 Key。API Key 不会进入备份或跨端同步数据；安全存储可用时会使用系统安全存储。HTTP 网页无法使用浏览器安全存储时，Key 仅保存在该浏览器本机，建议部署 HTTPS。网页端还要求该 API 允许浏览器跨域访问；Windows、Android 和服务端 AI 不受此限制。AI 导入仅上传用户当前输入的材料或目标，不会上传完整本地工作空间。

## 邮箱验证码

开发环境默认可不强制验证码。生产环境建议在私有配置中设置：

```text
EMAIL_MODE=smtp
EMAIL_VERIFICATION_REQUIRED=1
SMTP_HOST=...
SMTP_PORT=587
SMTP_USERNAME=...
SMTP_PASSWORD=...
SMTP_FROM=...
```

支持 QQ、163、Gmail、Outlook、企业邮箱等符合标准格式的邮箱地址。发信能力取决于已配置 SMTP 服务是否允许向对应收件人投递。

## Windows Server 部署

Windows 原生部署说明在 [deploy/README.md](deploy/README.md)。常用部署结构：

```text
C:\richeng\server\server.py
C:\richeng\server\requirements.txt
C:\richeng\deploy\windows-start.ps1
C:\richeng\deploy\Caddyfile.windows
C:\richeng\web\                 # Flutter build web 的输出
```

私有配置和数据不得覆盖或上传：

- `server/config.local.json`
- `server/data.sqlite3`
- `deploy/.env`
- `deploy/runtime/`

使用公网 IP 时，可基于 `deploy/Caddyfile.windows.public-ip` 配置网页、`/api/*` 与 `/ws` 转发。更新网页端时仅需覆盖 `C:\richeng\web`；更新服务端代码或 Caddy 配置后再运行：

```powershell
Set-Location C:\richeng\deploy
.\windows-start.ps1
```

该脚本会停止本项目已记录的 API 与 Caddy 进程、安装 WebSocket 依赖、重新启动服务并写入 `deploy/runtime` 日志。公网部署应只开放 80 和 443，不公开 5318、5319。

## 验证

```powershell
flutter analyze
flutter test
python server\test_server.py
```

Flutter 测试涵盖本地持久化、回收站、导入批次、时间轴排序、批量重排、深色模式、提醒规则及双端同步。服务端测试覆盖账号隔离、同步版本冲突、设备移除、邮箱验证码和常见邮箱格式。

## 当前限制

- 暂不支持循环任务、系统日历双向同步、PDF/Word/图片导入、团队协作、找回密码、后台推送。
- 项目进度目前按已完成任务数计算，不按预计工时加权。
- 本地数据使用 SharedPreferences；加密本地数据库和大规模数据迁移尚未实现。
- Android 已支持本地提醒；Windows 原生提醒和正式 MSIX 分发仍待完善。
- iOS/macOS 工程已生成，但需要 macOS 与 Xcode 才能构建、签名和验证。

## 目录说明

- `lib/app.dart`：页面、主题、任务编辑、时间轴、导入预览与设置。
- `lib/ai.dart`：AI 模式配置、个人 OpenAI 兼容接口调用和计划结果校验。
- `lib/models.dart`：项目、任务、日期校验、清单解析和批量重排规则。
- `lib/store.dart`：本地保存、回收站和导入历史。
- `lib/cloud.dart`：账号、设备、会话恢复、实时同步和三方合并。
- `lib/reminders.dart`：Android 本地提醒。
- `server/server.py`：SQLite、账号、同步 API、WebSocket、邮件验证码和 AI 代理。
- `deploy/`：Windows、Docker、Caddy 部署配置。
- `test/`、`server/test_server.py`：客户端与服务端自动测试。
