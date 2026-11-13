# 开发与仓库约定

## 工程

`App/` 是唯一 macOS 主应用的源码，`App/Core/` 同时作为 Swift Package 参与独立测试。`FinderExtension/` 编译为主应用内嵌的 `BuckleFinder.appex`（`studio.slippindylan.Buckle.Finder`），提供一级右键菜单；不生成第二个独立 `.app`、登录辅助应用或开发版主应用身份。`Config/Debug.xcconfig` 与 `Config/Release.xcconfig` 都使用本地 ad-hoc 签名，不继承个人 Team 或证书。

Sparkle 2.10.0 通过 Xcode SPM 依赖仅链接到主应用，锁文件纳入 Git。更新框架及其内部更新组件内嵌在主应用中；内部 Updater 使用 `LSUIElement`，不增加独立安装入口。更新器只在主应用完成单实例检查后创建，扩展进程不启动更新器。

版本、构建号与安装包开关的唯一编辑入口是 `Config/Release/manifest.json`。`node .github/scripts/sync-version.mjs` 更新 `Config/Generated/Version.xcconfig`，两个构建配置共同包含它。不要在 Xcode Build Settings 再设置版本覆盖值。使用 `Scripts/build.sh` 时自动同步；CI 用 `--check` 检测遗漏。

## 检查与构建

`bash Scripts/check.sh` 包含核心单元测试、Finder 配置与 URL 路由测试、真实沙盒配置读写权限检查、Release 签名下实际加载 Sparkle 的检查、更新配置与密钥匹配测试、官方 Sparkle 工具生成签名清单及拒绝篡改的检查、Swift 6 主应用和扩展源码类型检查、实际 Mach 内存采样检查、鼠标重置及部分退出失败回滚检查、系统内存窗口事件构造、权限拒绝和跨实例偏好恢复检查、格式、多语言、版本配置、通知脚本测试及 plist 检查。它通过 `Scripts/resolve-dependencies.sh` 解析锁定的 SPM 依赖，需要网络或已有缓存；不会启动应用界面或完整构建 Buckle。更新工具检查只生成临时测试归档，不使用用户私钥，不启动测试程序。

Swift 改动后执行：

```bash
xcrun swift-format format -i --recursive App FinderExtension Tests Package.swift Scripts/generate-icon.swift
bash Scripts/check.sh
```

需要完整构建时运行 `bash Scripts/build.sh Debug` 或 `bash Scripts/build.sh Release`。输出在 `build/DerivedData/Build/Products/`。构建后自动运行 `Scripts/verify-bundle.sh`，检查主应用及内嵌扩展的签名、ad-hoc Hardened Runtime 下的库验证例外、版本一致性、架构和扩展权限，以及 Sparkle 框架、内部组件、架构覆盖与更新校验配置；CI 与 Package 共用该检查。图标由 `Scripts/generate-icon.swift` 绘制；只有修改图标时才需运行该脚本，再执行 `iconutil -c icns build/Buckle.iconset -o App/Resources/AppIcon.icns`。正式图标文件纳入 Git。

CI 对 main 推送、PR 和手动触发执行检查及 Universal 2 构建。Package 单独手动触发，先验证 manifest，再根据开关决定是否执行 macOS 打包任务；包保留 7 天，不创建 Release、不推送其他仓库。关闭开关时通知报告 skipped，不把工作流的成功状态误报为已产出安装包。

通知工作流读取默认分支上的脚本，不执行 fork PR 的代码或下载其构建产物。权限只读；`DISCORD_WEBHOOK_URL` 只通过 Secret 进入通知步骤，消息禁用提及，错误不打印带凭据的请求地址。通知失败会让相应工作流失败，不伪装为成功。目前没有自动重试，需通过 GitHub 重新运行失败任务。`Publish Update Feed` 的开始及完成结果也发送通知；GitHub Release 发布消息只说明 Release 已发布，不代表更新清单已同步。

## 本机数据与权限

### Sparkle 更新签名密钥

Buckle 使用独立的 Ed25519 密钥，不能复用其他 App 的更新私钥。1Password「开发」保险库的「Sparkle · Buckle」保存公钥、`SPARKLE_ED_PRIVATE_KEY` 和本机钥匙串账户名 `studio.slippindylan.Buckle`。公钥已写入 `App/Info.plist` 的 `SUPublicEDKey`，可以公开；私钥只能保存在钥匙串、1Password 和 GitHub Secret 中，不能进入仓库或日志。

GitHub 仓库 `SlippinDylan/Buckle` 已配置 Secret `SPARKLE_ED_PRIVATE_KEY`、`HOMEBREW_TAP_TOKEN` 与普通 Variable `SPARKLE_PUBLIC_KEY`。更新发布工作流验证私钥推导出的公钥与 Variable、源码及实际发布 App 内的公钥一致，再签署更新包和清单。私钥通过标准输入传递给官方工具的 `--ed-key-file -`，不作为命令行参数；Tap Token 仅用于读取和提交更新宿主仓库。

密钥由校验 SHA256 后的官方 Sparkle 2.10.0 `generate_keys --account studio.slippindylan.Buckle` 生成。已从 1Password 读回核对，用导出的私钥签署测试归档，并验证公钥能验签、篡改后的归档验签失败。以后恢复或导出密钥时使用同一账户名，避免误用默认账户的密钥或替换既有更新身份。

### App 更新与发布

`ApplicationUpdateController` 管理一个 Sparkle 标准更新器。工具菜单提供检查更新与自动检查开关；后者直接读写 Sparkle 自己持久化的偏好，并通过主线程 KVO 更新界面，不在每次启动时覆盖用户选择。检查不可用时禁用入口，配置错误或启动失败在菜单中明确显示。网络错误及下载安装交给 Sparkle 原生界面。八种语言均补齐入口文本。

Debug 的 `BUCKLE_UPDATER_ENABLED=NO`，不要求更新源或私钥；CI 和 Package 构建显式停用更新，测试包不能用于正式更新。Release 使用 `BUCKLE_UPDATER_ENABLED=YES` 及 HTTPS 地址 `https://slippindylan.github.io/homebrew-tap/buckle/appcast.xml`。启动前校验地址、公钥；`SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 始终开启。首次发布前地址尚无 Buckle 清单，不能把接入代码完成当作已有更新可下载。

正式更新沿用现有 `homebrew-tap` 的 GitHub Pages `docs/` 托管，不将安装包提交到 Tap 或源码仓库：

1. 在 manifest 中递增 `version` 和 `build`，并设置 `packagingEnabled: true`。保持版本与构建号同时递增，避免 Sparkle 将新包视为旧构建。
2. 明确需要构建时运行 `bash Scripts/build.sh Release`，再运行 `bash Scripts/create-dmg.sh build/DerivedData/Build/Products/Release/Buckle.app build/Buckle-<version>.dmg`。这个包启用更新器；现有 Package 生成的 `-test.dmg` 不符合更新发布条件。
3. 在公开的 `SlippinDylan/Buckle` 发布稳定 GitHub Release，标签为 `v<version>`，上传唯一同名 `Buckle-<version>.dmg`。保持该下载地址可用，旧清单仍引用的包不要删除。当前仓库尚未公开，不自动修改仓库可见性或创建 Release。
4. `Publish Update Feed` 随 Release 发布触发，也可在 main 手动输入已发布标签重跑。它读取标签中的 manifest，验证开关、稳定版状态与仓库公开性，挂载 DMG 验证签名、版本、构建号、公钥、更新地址和 Sparkle 组件，再调用 `Scripts/prepare-update.sh` 生成并验签清单。历史清单从 Tap 读取，最多保留三个版本；发布说明嵌入签名清单。
5. 工作流只提交 `homebrew-tap/docs/buckle/appcast.xml`，不修改其他 App 的清单，也不自动生成 Homebrew Cask。此处使用 Tap 作为更新源宿主。推送冲突最多重试三次，失败明确报告；已发布包保持不变，可手动重跑清单同步。
6. 首次发布后验收 Pages 地址、正确和错误签名、网络失败、检查偏好保存、从旧版本实际安装更新及重启后 Finder 扩展状态。新增集成已通过类型检查和离线签名工具测试，尚未执行包含 Sparkle 的完整 Buckle 构建、线上工作流或真实升级。

`Scripts/prepare-update.sh <专用归档目录> <HTTPS下载目录>` 也可用于只生成文件而不发布。先解析依赖，以环境变量提供私钥和公钥；目录只存待发布归档及同名发布说明，Sparkle 可能将旧归档移入 `old_updates/`。脚本先验签已有清单，再在临时目录生成和验签候选清单；`Scripts/update_feed.py` 对照原清单验证新版本与构建号都递增，已发布构建的版本、下载地址、归档签名和长度不能改变。同一安装包可重复生成，清单验证失败时保留原清单。修改生成的清单或说明后必须重新签名，不手工修改线上已签名文件。

### 系统功能

- 浏览器隔离数据：`~/Library/Application Support/Buckle/BrowserProfiles/<bundle id>/<language>/`。
- 提醒偏好：Buckle 的 UserDefaults；登录项状态以 `SMAppService.mainApp.status` 为准。
- 鼠标重置：使用已确认的 bundle ID 查找工具，用 NSRunningApplication 请求退出并等待其实际结束，通过 NSWorkspace 后台重启。失败回滚只恢复本次成功发出退出请求的已运行工具；未运行或拒绝退出的工具不会被恢复逻辑额外启动。仅刷新当前用户的 `cfprefsd`；`tccd` 通过系统管理员授权执行固定命令刷新。不调用个人脚本、不打开终端、不获取或保存密码。不强制终止拒绝退出的工具，等待超时后报告失败并恢复可恢复的应用。
- 重置流程：停止窗口工具、刷新偏好服务、刷新权限服务、重启输入工具、重启窗口工具、检查运行状态。进度按实际步骤推进，失败恢复完成后才显示结果；成功或失败状态保留到点击「确定」，菜单栏图标同步切换。图标的无障碍描述包含当前步骤或结果，完成与失败通过 Apple 无障碍通知播报。
- Finder：内嵌 Finder Sync 扩展通过 `menu(for:)` 返回一级菜单项，使用系统 AirDrop 的标题和图标。扩展观察根目录及已挂载卷，并处理卷挂载变化。通过带参数校验的 `buckle://finder/airdrop` URL 将文件选择交给包含它的主应用；主应用再次检查开关并调用公开 NSSharingService，不使用 shell 拼接文件路径。
- Finder 开关：`~/Library/Application Support/Buckle/Finder/menus.json`，目录权限 700、文件权限 600，原子保存；扩展每次右键重新读取。主应用负责写入，沙盒扩展仅有该目录的 home-relative read-only 临时例外，不使用 App Groups、Team 或 provisioning。真实用户目录通过 `getpwuid_r` 读取，避免 Foundation 将路径重定向到扩展容器。文件缺失默认启用，损坏时明确报错。
- 主面板底部显示扩展缺失、未注册、未启用或操作失败的说明和相应按钮；启用时隐藏。配置解码失败有独立状态和确认后恢复默认配置的入口，恢复前在同目录创建 `menus-backup-<UUID>.json`；备份失败则不覆盖原文件。已运行时重新打开 App 显示工具主面板，Finder 的错误说明直接指向菜单栏右键入口。通过系统公开接口打开扩展管理界面，通过 `pluginkit` 注册和请求启用，随后读取实际状态，不把命令执行成功等同于系统已启用。面板打开及应用激活时刷新状态。单独关闭 AirDrop 入口不会禁用整个扩展，便于以后增加其他入口。
- 内存：后台仅串行读取系统虚拟内存计数，列表与强制退出完全交给系统 LowMemoryPanel，不再读取应用进程列表。左键和自动提醒共用 SystemMemoryPanel，右键提供工具面板。修改 loginwindow 的 DebugShowLowMemoryPanel 前，先原子保存原值到 `~/Library/Application Support/Buckle/MemoryPanel/pending.plist`；记录保留值是否原本不存在。发送系统快捷键并等待异步处理后恢复原值，成功恢复才删除记录。启动和正常退出也检查恢复记录，调用中正常退出会等待恢复。进程被强杀或崩溃后，无法保证立即恢复，下次启动才会继续恢复。记录不可读时拒绝覆盖，不猜测原设置。高内存持续时间与 15 分钟冷却均使用 ContinuousClock，普通刷新不会缩短 30 秒持续阈值，仅成功打开窗口后记录冷却起点。
- 调用系统窗口需要辅助功能与控制 System Events 的自动化授权。只有手动触发允许请求辅助功能及自动化授权。先确保 System Events 运行，再在后台线程调用 AEDeterminePermissionToAutomateTarget 检查权限。使用 System Events 字典中的 `prcs/kcod` Apple Event 发送相同的 Command–Option–Escape，并设置 `kAEDoNotPromptForUserConsent` 和 10 秒发送超时；检查传输错误及目标回复中的错误。自动提醒缺少权限或失败只更新工具面板，不抢焦点，不开启冷却。该调试路径属于私有系统行为，不能以源码类型检查或模拟测试代替各支持版本的实测。

### 操作期间退出与更新

`ApplicationLifecycle` 统一登记内存窗口操作（含权限检查）和鼠标重置，退出分为正常运行、等待操作、退出恢复三个阶段。收到正常退出请求后停止接收新操作，等待已有操作结束，再进入退出恢复；进入恢复阶段后，重复退出请求不会再次启动恢复任务。Sparkle 安装更新通过正常退出事件进入同一协调流程，不单独维护更新专用的忙碌状态。

`ApplicationRecovery` 在退出边界分别恢复内存设置和鼠标工具，其中一项失败也必须尝试另一项；错误类型明确区分内存、鼠标及两项都失败，保留完整原因。完成业务流程不等于已经恢复，退出判断以这次实际恢复结果为准。恢复失败时默认取消退出，允许重试恢复或明确选择仍然退出；重试不重新执行停止应用、刷新系统服务或管理员授权。取消后重新开放操作，鼠标待恢复进程和内存恢复文件保持不变，之后再次退出仍执行恢复。明确继续退出才允许丢弃仅在内存中的鼠标待恢复信息，界面说明工具可能需要手动重新打开；内存恢复文件仍保留。

鼠标重置按具体进程记录已接受的退出请求；随后有工具拒绝退出时，也先等待已发出的请求完成，再进入恢复。恢复前再次确认原进程已退出，MonitorControl helper 的恢复归属主工具。退出或恢复超时会明确报告失败，进程记录保留在当前控制器中；下次重试先处理这些记录，不用新操作覆盖。只有确认退出并完成恢复启动后才清除对应记录，不强制结束第三方应用。管理员授权沿用原脚本 `sudo killall tccd` 的权限需求，由系统授权弹窗执行固定的 `/usr/bin/killall tccd`；`cfprefsd` 只针对当前用户，不提升整个 App 的权限。

内存恢复记录损坏或恢复失败时，不覆盖记录、不猜测原设置。退出确认提供查看记录的入口，查看后取消本次退出；内存窗口仍需先成功恢复记录才可修改设置。明确继续退出可能让临时设置继续有效，下次启动仍尝试恢复。

内存压力回调可能合并多个标志，因此将 warning/critical 视为待处理的一次事件；合并的 normal 不会覆盖高压力事件。成功采样后消费该事件，即使提醒关闭或处于冷却期也不保留旧事件以后重放。持续高用量仍由独立的持续时间判定。采样 Timer 注册在主运行循环的 common modes，菜单跟踪期间继续采样。

AirDrop 用户取消属于正常结束，只释放共享服务引用；真正的共享错误仍报告。

### 更新后的权限复查

ad-hoc 签名的指定要求绑定具体构建，不能保证跨版本保留 TCC 授权。启动和应用重新激活时静默复查辅助功能与自动化权限，复查失败单独报告，不覆盖内存设置恢复错误。权限缺失时在工具面板提供设置入口、当前应用定位和重新检查按钮；指引用户移除旧辅助功能条目、添加当前版本，并在自动化中允许控制 System Events。后台检查不弹授权窗口，只有手动打开系统内存窗口才允许请求授权。

后台权限检查与打开窗口是独立的操作，两者都参与退出协调。手动打开先登记请求，等待已有检查任务完成（包括状态写回），再继续授权及打开窗口；重复打开不会并行执行。等待时如果收到退出请求，则放弃打开窗口，在检查结束后完成退出。

新增自动检查覆盖：并行操作的退出等待、拒绝退出后的新操作、鼠标成功及失败恢复后的退出、损坏恢复记录时取消或保留记录退出、权限状态重新检查、合并内存压力信号及一次性消费、真实监测器在模拟菜单跟踪模式下持续采样，以及 AirDrop 取消与其他错误的区别。测试不打开系统窗口、不重置实际服务、不执行更新。

回归检查还覆盖延迟退出与部分拒绝退出同时发生、退出超时后的恢复重试、helper 的恢复归属、权限检查中手动打开及重复点击、等待期间退出，以及官方 Sparkle 工具生成清单时拒绝重复构建号和未递增版本，并确认失败不覆盖原清单。

退出恢复检查使用实际 `ApplicationRecovery`，组合覆盖退出请求在重置期间或之后发生、仅鼠标恢复失败或两项都失败，以及重试/取消/明确退出三种决定。另用实际 `NativeMouseReset` 和模拟系统边界检查退出超时、重新启动失败、取消退出及关闭结果页后再次恢复；单独验证内存记录损坏时仍恢复鼠标、干净退出无需确认、异步恢复期间重复退出只处理一次。测试不实际终止应用、刷新服务或弹出授权窗口。

依据：[Apple 退出协调](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:))、[Sparkle 安装与退出契约](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html)、[Timer 默认运行模式](https://developer.apple.com/documentation/foundation/timer/scheduledtimer(withtimeinterval:repeats:block:))、[AirDrop 取消回调](https://developer.apple.com/documentation/appkit/nssharingservicedelegate/sharingservice(_:didfailtoshareitems:error:))、[Apple 签名要求与 ad-hoc 身份](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

## 纳入与排除

应提交：源码、测试、八种语言资源、正式图标、Xcode 工程与共享 scheme、版本 manifest 及生成的版本配置、自动化脚本、正式文档。未来增加依赖时，锁文件应提交。

由 `.gitignore` 排除：`build/`、`.build/`、DerivedData、app/DMG/归档/dSYM、Xcode 用户状态、编辑器私有设置、日志、`.env`、签名凭据、`Config/Local.xcconfig`、个人草稿及参考项目。不得依赖忽略规则保护已经跟踪的密钥，任何凭据都不能写入源码或日志。

## 实机验收

类型检查不能替代下列系统验收：

1. 运行和 Spotlight 只有一个正式安装副本，Dock 不显示图标，关闭面板后继续后台运行。
2. 八种系统首选语言下的 UI、菜单、Finder 原生 AirDrop 名称，以及浅色/深色和 VoiceOver 操作。
3. 浏览器的首次启动、已经运行时再次按相同/不同语言启动，以及 Safari 未退出时的错误提示。
4. Finder 一级菜单和系统图标、多文件及文件夹 AirDrop、取消传输、入口开关、外置盘与新挂载卷；扩展缺失/未注册/禁用时的底部引导、系统设置返回后的状态刷新。
5. 左键打开系统 LowMemoryPanel、右键工具面板、实际内存压力下的自动提醒与冷却间隔、辅助功能/自动化权限拒绝和临时系统偏好恢复。
6. 鼠标重置的系统管理员授权、取消授权、应用拒绝退出、重启/恢复失败及状态图标，以及开机自启批准/禁用/重新登录。模拟检查不会实际终止应用或刷新系统服务。
7. GitHub 中实际执行 CI 与开关启闭后的 Package，并核对 DMG 架构、版本、校验和及 Discord 通知。
8. 鼠标重置或内存窗口调用期间正常退出、由 Sparkle 安装更新触发退出，确认等待恢复完成；恢复失败时验证取消、重试、明确继续退出及内存记录查看。确认取消后可再次恢复，重试不再次重置服务或请求管理员授权。
9. 已授权的旧版本通过 Sparkle 更新后，验证新版本权限检测、重新授权指引和重新检查；不能以相同版本的模拟权限检查代替真实升级验收。

项目明确不购买付费 Apple 开发者证书。开发与 GitHub 分发以无需账号的 ad-hoc 签名为目标，不将 Developer ID、公证或 App Store 上架作为交付前提。ad-hoc 签名不提供 Apple 验证的开发者身份，也不能用于常规 Developer ID 公证；从网络下载时用户可能需要在系统设置中明确允许运行，并单独启用 Finder 扩展。主应用和扩展的签名、注册、加载及权限必须按该无付费证书方案实测，不能仅凭主应用可编译便宣称扩展可用。不要引入必须依赖付费团队或 provisioning 的能力作为基础功能前提。开源许可证需由项目所有者选择。

## 系统窗口与原生图标调查

本机 loginwindow 资源中分别存在 `ForceQuitPanel` 与 `LowMemoryPanel`，后者包含“系统的应用程序内存不足”的提示；两者不能混为同一个窗口。正常内存状态也能读取进程内存，是否显示该面板由系统决定。对当前本机 macOS 27.0.1 二进制的只读检查发现 `showForceQuitPanel` 会读取 `DebugShowLowMemoryPanel` 并进入低内存面板的调试路径；该路径已使用临时调试设置与系统快捷键在本机打开，用户确认正是需要的窗口，随后删除临时设置恢复了原值。现在已接入 App 的内存入口与提醒；集成代码有成功、失败及恢复失败的模拟检查，但未执行完整 App 实机验收，也不能当作跨 macOS 版本的已验证接口。

原生 AirDrop 图标已通过公开的 `NSSharingService(named: .sendViaAirDrop).image` 成功读取；实现时应在运行时取图，沿用系统当前样式。图标可获取不等于可以直接控制 Finder 自带的共享菜单。SDK 明确注明 `NSSetShowsServicesMenuItem` 无效果，不能用它冒充入口开关。

Finder 一级右键入口已有源码依据，适合通过内嵌 Finder Sync 扩展实现，不必经「服务」：

- [Apple 的 menu(for:) 文档](https://developer.apple.com/documentation/findersync/fifindersyncprotocol/menu(for:)) 提供文件选中、文件夹空白处等上下文菜单接口；菜单项可直接加入返回的 NSMenu，无需再包一层 submenu。
- [OpenInTerminal 的实现](https://github.com/Ji4n1ng/OpenInTerminal/blob/537ac2a5ee69ae46d4948c9b259e067a0c179a5f/OpenInTerminalFinderExtension/FinderSync.swift) 用 `isContextMenuUseSubmenu` 决定一级平铺还是子菜单，终端、编辑器和复制路径均可直接加入一级；`isHideContextMenuItems` 控制是否返回空菜单。
- [RClick 的实现](https://github.com/wflixu/RClick/blob/d3adb9f902be082583501503a98951d993bceec9/FinderSyncExt/FinderSyncExt.swift) 同样支持多个操作直接平铺，并已提供 AirDrop。只参考其接口使用与职责分工，未复制其 GPL 源码。

可以用一个内嵌 `.appex` 提供多个独立开关的菜单项，不需要第二个独立 `.app`。扩展负责显示菜单和读取选中的 URL，主应用负责配置和实际操作；关闭某个入口时，下次构建菜单不再加入它。当前已实现该分工。本机已以空 Team、ad-hoc 签名完成 Universal 2 构建，验证嵌套签名、版本与架构，完成 `pluginkit` 注册及启用，并确认 Finder 实际启动扩展 XPC 进程。相同沙盒权限的独立检查程序验证了真实配置目录可读且不可写，已纳入检查脚本。上述检查未打开主应用界面或操作右键菜单，不代表实际 AirDrop 传输和所有 macOS 版本已验收。

Finder 决定扩展菜单项与系统菜单的排列，不能保证任意指定插入位置。目录覆盖依赖 `directoryURLs`，外置盘和新挂载卷应独立验证。首次启用与签名仍需实测；OpenInTerminal 的配置文档记录了新系统上的设置入口差异和 pluginkit 选举方式，不能假设所有版本的系统设置路径相同。Apple 的[归档设计指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)明确表示 Finder Sync 原本面向文件同步应用，并非通用 Finder UI 改造工具；通用右键工具是在复用该扩展点的菜单能力。

## 无账号签名与 Sparkle 运行验证

Release 使用 ad-hoc 签名并保留 Hardened Runtime。ad-hoc 没有 Team ID，不能满足默认同团队库验证，因此仅主应用通过 `com.apple.security.cs.disable-library-validation` 加入必要例外；Finder 扩展不添加此权限。不关闭其他运行时保护，更新归档与清单仍必须通过 Ed25519 验签。这不提供 Developer ID 身份、公证或 Gatekeeper 自动信任。

`Scripts/check-sparkle-runtime.sh` 复制锁定的实际 Sparkle 框架，用 Release 签名约定和主应用权限签署临时命令行程序，实际加载框架；不启动更新器或应用界面。包检查同步拒绝缺少必要例外的 ad-hoc Hardened Runtime 主应用。

依据：[Sparkle 签名说明](https://sparkle-project.org/documentation/)、[Apple 库验证例外](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation)、[应用退出协调](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:))、[Apple Event 发送接口](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/sendevent(options:timeout:))、[无障碍播报](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested)。自动化权限 API 的目标必须运行、不得在主线程阻塞及禁止授权弹窗的发送选项，以当前 SDK 的 `AppleEvents.h` 声明和注释为准。
