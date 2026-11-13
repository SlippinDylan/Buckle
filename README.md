# Buckle

一个常驻菜单栏的 macOS 小工具：打开系统内存窗口、按语言启动浏览器、重启鼠标相关服务，并在 Finder 中调用隔空投送。

最低支持 macOS 15，使用 Swift 6、SwiftUI 和 AppKit。一个主应用、一个内嵌 Finder 扩展、一个应用图标；后台运行，不显示 Dock 图标。

## 当前功能

- 左键点击菜单栏图标，直接打开已在本机确认的系统原生 LowMemoryPanel，由系统展示应用内存及强制退出操作。右键打开工具面板；鼠标重置进行中或结果未确认时，点击图标回到进度页。
- 每 30 秒采样；估算用量达到物理内存的 90% 并持续至少 30 秒，或系统发出内存压力事件时，自动打开同一个系统窗口。手动刷新不会缩短持续时间，成功打开后的提醒间隔至少 15 分钟，可在工具菜单关闭。缺少权限时只在工具面板显示引导，不在后台弹出授权或错误对话框。
- 「右键菜单栏图标 → 工具 → 按语言启动浏览器 → 浏览器 → 语言」选择启动。支持检测 Chrome（含 Beta、Canary）、Chromium、Edge、Brave、Vivaldi、Opera、Safari 和 Safari Technology Preview。
- 「右键菜单栏图标 → 工具 → 重置鼠标」进入二级进度页，由项目代码刷新偏好与权限服务，重启已安装的 Moom、MonitorControl、BetterMouse、iShot Pro。完成后显示成功，菜单栏图标切换，点击「确定」返回；失败时显示错误，只尝试恢复本次请求关闭的工具，不启动原本未运行的工具。进度和结果同时提供 VoiceOver 描述，完成或失败时播报结果。
- 支持开机自启，必要时引导至系统设置批准。
- Finder 文件或文件夹的一级右键菜单提供「隔空投送」，标题和图标直接读取系统 AirDrop；主面板开关控制入口，下次右键生效。
- Finder 扩展缺失、未注册或未启用时，主面板最底部显示说明和对应按钮；启用后自动隐藏，无需进入二级设置页。配置文件损坏时可确认恢复默认设置，恢复前保留原文件备份。已经运行时重新打开 Buckle 会显示工具主面板。
- 「工具 → 检查更新」使用 Sparkle 原生界面检查和安装新版本，可设置自动检查。Debug 与 CI 测试包关闭更新；首次公开发布安装包和更新清单后，Release 才有可下载的更新。

界面支持英语、简体中文、繁体中文、日语、韩语、德语、法语、西班牙语，与 glilo 一致。默认跟随系统的首选语言；浏览器语言单独选择。

正常退出及 Sparkle 安装更新共用同一退出流程：等待正在进行的操作结束，再分别恢复内存设置和鼠标工具；其中一项失败也会尝试另一项。恢复未完成时默认取消退出，可重试恢复或明确选择「仍然退出」。重试只做恢复，不重新重置服务或请求管理员授权。内存恢复失败时还可查看记录，不会删除记录或猜测原设置。选择仍然退出会丢失保存在内存中的鼠标待恢复信息，部分工具可能保持关闭或稍后退出，需要手动重新打开。

鼠标工具接受退出请求后，Buckle 会等待对应进程真正退出，再恢复应用；其他工具拒绝退出也不会跳过这个等待。退出超时会报告恢复失败，并在下次重试前先处理尚未完成的恢复。刷新 `tccd` 仍需要管理员授权，通过 macOS 系统弹窗完成；不会在 App 内收集或保存密码。

无需付费证书的 ad-hoc 签名不能保证更新后保留系统授权。应用启动及回到前台时会静默检查内存窗口所需权限；缺少权限时，工具面板提供设置入口、当前应用定位和重新检查按钮，并说明如何移除旧辅助功能条目、添加当前应用及允许控制 System Events。

后台权限检查期间点击内存入口，会等待检查结束后继续打开，不需要再点一次；等待期间的重复点击合并处理。如果此时请求退出，则结束检查后直接退出，不再打开新窗口。

## 开发

用 Xcode 26 或更新版本打开 `Buckle.xcodeproj`，选择 Buckle / Debug 运行。开发签名使用 ad-hoc，`DEVELOPMENT_TEAM` 为空，无需登录 Apple 开发者账号。Release 保留 Hardened Runtime，仅主应用关闭同团队库验证以加载 Sparkle；无需付费证书，仍不具备 Developer ID 身份或公证。

```bash
bash Scripts/check.sh          # 测试、Swift 6 类型检查、格式和配置检查
bash Scripts/build.sh          # 明确需要构建时，生成 Debug 应用
```

`Scripts/build.sh` 仅构建，不会自动启动应用。需要 Xcode、Node.js 和 Python 3。主应用通过 SPM 使用锁定的 Sparkle 2.10.0，Finder 扩展不依赖 Sparkle；检查脚本会解析依赖，不需要 Apple 开发者账号。

## 版本与打包

只编辑 [Config/Release/manifest.json](Config/Release/manifest.json)：

```json
{
  "version": "0.1.0",
  "build": 1,
  "packagingEnabled": false
}
```

`version` 是应用版本，`build` 是构建号。`Scripts/build.sh` 会自动同步工程版本；直接用 Xcode 前，在修改 manifest 后执行一次 `node .github/scripts/sync-version.mjs`。生成的 xcconfig 纳入 Git，不能手改；CI 会拒绝不同步的配置。

CI 执行检查并编译 Universal 2（Apple Silicon / Intel）应用。手动触发 GitHub Actions 的 Package 工作流时，只有 main 分支且 `packagingEnabled: true` 才会生成带版本号的 DMG 和 SHA256 校验文件。开关默认关闭，不影响日常 CI；目前只提供 ad-hoc 签名测试包，尚未配置 Developer ID 签名、公证或公开发布。

Discord 通知使用 GitHub Actions Secret `DISCORD_WEBHOOK_URL`，覆盖推送、PR、Issue、评论、CI/打包状态、GitHub Release 发布及更新源同步结果。Release 已发布与用户可获取更新是两个独立状态，清单同步失败会单独通知。Webhook 不保存在仓库中。

Sparkle 已接入，使用 Buckle 独立密钥，备份在 1Password「开发」保险库的「Sparkle · Buckle」条目中。公钥位于 `App/Info.plist`，私钥只保存在安全存储和 GitHub Secret。安装包放在 GitHub Releases，签名更新清单由 `Publish Update Feed` 工作流同步到 `homebrew-tap/docs/buckle/appcast.xml`，通过 GitHub Pages 提供更新；安装包不进入 Git 源码仓库。首次公开发布及真实升级尚未执行，发版步骤见[开发与仓库约定](docs/development.md)。

## 使用限制

- 将唯一一份 Buckle.app 放入 `/Applications` 后运行。开发产物与安装副本同时保留时，Spotlight 仍可能索引到多个副本；应用不能控制系统索引。
- Finder 入口由内嵌 Finder Sync 扩展提供。右键点击 Buckle 菜单栏图标打开工具主面板，按底部提示注册或启用扩展，也可点击按钮打开系统扩展管理界面。系统版本不同，设置位置可能不同；Buckle 不要求购买 Apple 开发者证书。
- AirDrop 是一级菜单项，排列位置由 Finder 决定。关闭主面板的隔空投送开关后，下次右键不再显示；这只控制 Buckle 添加的入口。
- Chromium 浏览器按浏览器和语言建立独立配置目录，不会复用日常浏览器的登录态。语言选择不改变系统语言、IP 或时区，也不保证网站采用指定语言。
- Safari 必须先退出才能换语言；Buckle 不会自动关闭浏览器或修改其全局设置。其他浏览器暂未接入。
- 系统窗口通过 loginwindow 的私有调试设置与系统快捷键调用，已在本机 macOS 27.0.1 打开并由用户确认，其他系统版本尚未验证。需要辅助功能和控制 System Events 的自动化授权。修改前先保存原设置到本地恢复记录；调用完成或失败时恢复，正常退出等待恢复完成。如果进程崩溃或被强制退出，下次启动优先恢复。恢复失败会保留记录并报错；再次启动前，系统设置仍可能保持临时值。手动打开时，窗口中的“内存不足”提示并不表示当下内存真的不足。
- 后台提醒仅估算活跃页、驻留内核页与压缩页之和，并监听系统内存压力，不再自行采集或终止应用进程。
- 鼠标重置不依赖个人脚本或终端。刷新系统权限守护进程时通过系统管理员授权执行固定命令，不存储密码；应用拒绝退出、授权取消、重启失败和恢复失败都会明确显示。未安装的工具不参与重启，也不声明它们已成功重启。

内存入口和自动提醒已接入系统窗口，App 内不再绘制应用内存列表。Finder 扩展已在本机通过无账号 ad-hoc Universal 2 构建、签名检查、注册、启用与 Finder 后台加载检查；相同沙盒权限的检查程序已验证配置目录可读、不可写。完整界面、实际右键菜单与 AirDrop 传输仍需实机验收。

初始化的系统行为仍需要实机验收，详细规则见 [开发与仓库约定](docs/development.md)。
