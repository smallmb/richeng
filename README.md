# 日程 0.3.0

沿用原 HTML 的暖灰背景、白色描边卡片、分阶段清单和难度标签，提供 Flutter 桌面与手机布局。

## 0.1.1 动效优化

- 参考 [MotionView](https://feralui.dev/motionview) 的缓动节奏，以 Flutter 原生组件实现，无新增依赖。
- 勾选完成时提供轻微缩放、文字淡化和删除线；筛选列表先保留完成反馈，再平滑收起，支持立即撤回。
- 阶段展开统一高度、透明度和箭头旋转，支持动画中途反向操作；进度条平滑更新。
- 任务详情在桌面使用右侧抽屉，在手机使用底部面板；标题与操作栏固定，内容可滚动并适应键盘。
- 遵循系统“减少动画”设置，改善状态文字对比度，修复桌面侧栏 Material 背景问题。
- 验证：8 项 Flutter 测试通过，静态分析无问题，Windows、Android ARM64 和网页构建成功。移动端布局另经 390px 浏览器预览检查；尚未进行 Android 真机动效验证。

## 0.2.0 日程与账号完善

- 任务可设置开始时间、预计耗时与提前提醒；Android 使用系统本地通知，提醒设置、变更、完成和归档后会重新安排。
- “今天”和日历继续按日期查看，任务行会展示时间、预计耗时与提醒状态；项目可填写开始日和目标截止日。
- 快速添加直接进入“独立任务”箱，不必先建立项目；阶段和任务均可上下排序。
- AI/清单追加导入会跳过同项目内同标题的重复任务；撤销新项目导入会完整移除该项目。
- 同步服务记录登录设备，可查看并移除其他设备的会话；原有数据库启动时自动迁移设备字段。
- 验证：10 项 Flutter 测试、4 项 Python 服务测试通过；网页、Windows 和 Android ARM64 构建通过。

## 0.2.1 多日执行

- 同一任务可增加多个执行日期，日历会在每个日期显示该任务；完成状态、备注和任务数量仍只计算一次。
- Android 会为每个未来执行日期创建对应提醒；旧版本只有一个安排日期的任务会自动迁移为单日执行。

## 0.3.0 公网服务准备

- 服务端新增 SMTP 邮箱验证码：验证码仅以摘要保存，10 分钟过期、错误最多 5 次、发送间隔 60 秒；生产配置可强制注册必须验证。
- 新增 Docker Compose 与 Caddy 部署文件，可使用域名自动申请 HTTPS；AI 密钥和 SMTP 凭据只通过服务器环境变量读取。
- 已在 USB 连接的 OPD2601 平板安装并启动调试版，使用 ADB 反向端口映射验证平板到本机服务的 TCP 连通性。

## 直接体验

- 双击根目录的「打开日程.cmd」，或运行 `build/windows/x64/runner/Release/richeng.exe`。
- Windows 发布时必须保留 Release 目录内的 DLL 和 data 文件夹，不能只复制 exe。
- Android 安装包位于 `build/app/outputs/flutter-apk/`；当前是体验签名，不能直接作为商店正式发布包。
- 首次打开载入原 HTML 的 9 个阶段、104 项任务。原浏览器已勾选状态不在 HTML 文件中，因此不会自动迁移。

## 已实现

- 多项目、归档与恢复，项目开始日和目标截止日；阶段新增、编辑、上下排序；空阶段可删除。
- 独立任务箱、任务新增、编辑、移动阶段、上下排序、删除及即时撤销；未开始、进行中、已完成状态。
- 难度、进度备注、安排日期与开始时间、预计耗时、截止日期；完成数量与阶段进度自动汇总。
- Android 本地提醒，支持开始时、提前 5/15/30/60 分钟提醒；权限只在用户开启提醒时请求。
- 今日安排、逾期待办、未安排任务、月历日期查看。
- 搜索以及全部、未完成、已完成、逾期筛选。
- 本地保存与重启恢复，完整 JSON 备份与追加恢复。
- 文本/Markdown 清单整理、标题编辑、选择性导入、新建项目或追加阶段。
- OpenAI 兼容模型服务：分析 → 校验 → 预览 → 用户确认导入。
- 邮箱验证码注册（生产配置启用）、邮箱和密码登录、登录设备查看与移除、WebSocket 实时同步、断线后的 8 秒 HTTP 轮询兜底、版本冲突阻止覆盖。

## 本地服务

Python 3.10 及以上，无额外 Python 包依赖。

```powershell
# 在项目目录启动服务，默认仅监听本机。
python server/server.py
```

客户端「设置 → 账号与云同步」中填写 `http://127.0.0.1:5318`，注册一个至少 10 位密码的账号。

首次登录选择同步方向：

1. 第一台设备选择「使用当前设备版本」。
2. 第二台设备连接同一服务和账号，选择「使用云端版本」。
3. 后续自动同步。并发修改时暂停同步，选择保留版本；被替换版本可在设置中复制备份恢复。

同步采用整个工作空间的版本检查，不是字段级自动合并。首次方向选择以及冲突解决会有确认提示。登录令牌仅保存在内存，本次关闭程序后需要重新登录；密码不会保存在客户端。

账号数据存放在 `server/data.sqlite3`。本地开发默认不强制邮箱验证码；公开部署应设置 `EMAIL_VERIFICATION_REQUIRED=1` 并配置 SMTP。找回密码、配额与运维监控待后续补齐。

手机连接时，`127.0.0.1` 指手机自身；应使用部署后的 HTTPS 地址，或在可信局域网使用电脑地址。调试 APK 允许 HTTP；正式版本保持 HTTPS。服务监听地址可通过 `RICHENG_HOST` 配置，默认不向局域网开放。

## 接入 AI

复制 `server/config.example.json` 为 `server/config.local.json`，填写：

- `AI_BASE_URL`：OpenAI 兼容接口根地址，通常以 `/v1` 结尾。服务会追加 `/chat/completions`，不要重复填写这个后缀。
- `AI_MODEL`：供应商支持的模型名称。
- `AI_API_KEY`：模型密钥，只填写到本机文件。该文件已被 Git 忽略。

重启 Python 服务。客户端登录后，AI 导入默认使用当前账号服务的 `/api/plan`，无需另外填写 AI 地址。仅发送本次粘贴的材料，未输入具体日期时要求模型保留空日期。

尚未提供真实密钥，因此当前未完成真实模型调用验证。AI 未配置时会返回明确错误，本地清单整理不受影响。自定义 AI 服务地址须实现相同协议；只有同源请求才携带账号令牌。

## 邮箱验证码与 HTTPS 部署

生产部署模板位于 [`deploy/`](deploy/README.md)。复制 `deploy/.env.example` 为私有的 `deploy/.env`，填写公网 API 域名、OpenAI 兼容模型密钥和 SMTP 凭据，再在该目录执行 `docker compose up -d --build`。域名 DNS 指向服务器且开放 80/443 后，Caddy 会自动申请 HTTPS 证书。

客户端注册账号时先点击“发送验证码”，再填写六位验证码。开发环境可保持 `EMAIL_VERIFICATION_REQUIRED=0`；生产环境应使用 `EMAIL_MODE=smtp` 与 `EMAIL_VERIFICATION_REQUIRED=1`。

## 构建与测试

```powershell
# Windows：脚本自动准备插件目录联接。
.\tool\build-windows.ps1

# Android 体验包。
& 'D:\Apps\flutter\bin\flutter.bat' build apk --debug

# 浏览器预览，渲染资源随包提供。
& 'D:\Apps\flutter\bin\flutter.bat' build web --no-web-resources-cdn
python -m http.server 5317 --bind 127.0.0.1 --directory build/web

# 静态分析与自动测试；同步测试会启动临时 Python 服务和临时数据库。
& 'D:\Apps\flutter\bin\flutter.bat' analyze
& 'D:\Apps\flutter\bin\flutter.bat' test
python -m unittest discover -s server -p test_server.py -v
```

Android Kotlin 增量缓存遇到 C、D 盘相对路径冲突，因此在本项目内关闭了 Kotlin 增量编译。没有修改 Flutter SDK 或系统安全设置。

已生成 Android、Windows、iOS、macOS 工程。iOS/macOS 需要在 Mac 上使用 Xcode 构建、签名和实机验证，当前 Windows 环境没有产出这两个平台的安装包。

## 初版边界

- 一个任务支持多个执行日期，但各日期暂共用一个开始时间、预计耗时和提醒规则；暂不含多时段、循环任务和系统日历同步。
- 导入支持粘贴文本；PDF、Word、图片和直接文件选择尚未实现。
- 项目进度按已完成任务数量计算，不代表工时完成比例。
- 尚无团队协作、找回密码、后台推送与实际云服务器账号。Windows 未打包为 MSIX，因此系统级定时提醒暂只在 Android 启用。
- JSON 备份恢复会追加新 ID 的项目，不覆盖已有项目。
- 本地数据使用 SharedPreferences；大规模数据、加密本地存储与增量同步待后续版本。

## 工程结构

- `lib/app.dart`：主题、页面、任务编辑及导入预览。
- `lib/motion.dart`：动效曲线、勾选反馈、阶段展开、任务退场与响应式详情面板。
- `lib/models.dart`：稳定标识、数据模型、输入校验、Markdown 清单解析。
- `lib/store.dart`：本地持久化与串行写入。
- `lib/cloud.dart`：账号界面、同步状态、版本冲突与恢复备份。
- `server/server.py`：账号、SQLite、同步 API、模型代理。
- `assets/seed.json`：从原 HTML 提取的完整初始清单。
- `test/`、`server/test_server.py`：组件、持久化、解析、账号隔离及真实双端同步测试。
