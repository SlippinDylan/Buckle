# 开发与仓库约定

## 工程

`App/` 是唯一 macOS 主应用的源码，`App/Core/` 同时作为 Swift Package 参与独立测试。`FinderExtension/` 编译为主应用内嵌的 `BuckleFinder.appex`（`studio.slippindylan.Buckle.Finder`），提供一级右键菜单；不生成第二个独立 `.app`、登录辅助应用或开发版主应用身份。`Config/Debug.xcconfig` 与 `Config/Release.xcconfig` 都使用本地 ad-hoc 签名，不继承个人 Team 或证书。

Sparkle 2.10.0 通过 Xcode SPM 依赖仅链接到主应用，锁文件纳入 Git。更新框架及其内部更新组件内嵌在主应用中；内部 Updater 使用 `LSUIElement`，不增加独立安装入口。更新器只在主应用完成单实例检查后创建，扩展进程不启动更新器。

版本、构建号与安装包开关的唯一编辑入口是 `Config/Release/manifest.json`。`node .github/scripts/sync-version.mjs` 更新 `Config/Generated/Version.xcconfig`，两个构建配置共同包含它。不要在 Xcode Build Settings 再设置版本覆盖值。使用 `Scripts/build.sh` 时自动同步；CI 用 `--check` 检测遗漏。

## README 与截图

仓库首页 `README.md` 使用英文；`docs/README.<语言>.md` 提供简体中文（`zh-CN`）、繁体中文（`zh-TW`）、日语（`ja`）、韩语（`ko`）、德语（`de`）、法语（`fr`）、西班牙语（`es`）版本，与 App 的八种语言对应。多语言同步要求以根目录 [AGENTS.md](../AGENTS.md) 的 README 规则为准；修改共享内容时必须在同一变更中同步其他语言版本。开发细节仍集中在本文。

所有语言版本共用 `docs/images/readme/` 下真实运行界面的英文截图，不单独维护各语言图片。截图包含主菜单、浏览器语言子菜单、Finder 右键菜单和通用／权限设置页；保留真实权限与禁用状态，不在图片中伪造界面文字。更换截图时避免包含个人窗口内容，并恢复为拍摄临时调整的语言及功能开关。

## 检查与构建

`bash Scripts/check.sh` 包含核心单元测试、Finder 配置与 URL 路由测试、真实沙盒配置读写权限检查、Release 签名下实际加载 Sparkle 的检查、更新配置与密钥匹配测试、官方 Sparkle 工具生成签名清单及拒绝篡改的检查、Swift 6 主应用和扩展源码类型检查、鼠标重置及部分退出失败回滚检查、系统内存窗口事件构造、权限拒绝和跨实例偏好恢复检查、格式、多语言、版本配置、通知脚本测试及 plist 检查。它通过 `Scripts/resolve-dependencies.sh` 解析锁定的 SPM 依赖，需要网络或已有缓存；不会启动应用界面或完整构建 Buckle。更新工具检查只生成临时测试归档，不使用用户私钥，不启动测试程序。

Swift 改动后执行：

```bash
xcrun swift-format format -i --recursive App FinderExtension Support Tests Package.swift
bash Scripts/check.sh
```

需要完整构建时运行 `bash Scripts/build.sh Debug` 或 `bash Scripts/build.sh Release`。输出在 `build/DerivedData/Build/Products/`。构建后自动运行 `Scripts/verify-bundle.sh`，检查主应用及内嵌扩展的签名、ad-hoc Hardened Runtime 下的库验证例外、版本一致性、架构和扩展权限，以及 Sparkle 框架、内部组件、架构覆盖与更新校验配置；CI 与本地构建共用该检查。所有构建检查都要求主应用和 Finder 扩展分别使用固定标识 `studio.slippindylan.Buckle` 与 `studio.slippindylan.Buckle.Finder`。开发检查允许单架构；分发入口额外传入 `--distribution`，要求两者均包含 arm64 和 x86_64。DMG 创建及更新发布的挂载检查采用同一分发规则。应用图标的设计源为仓库根目录的 `Buckle.icon`，保留用户提供的 Icon Composer 文档和素材。Debug、Release 的主应用均设置 `ASSETCATALOG_COMPILER_APPICON_NAME = Buckle`，并将文档加入 Resources；由 Xcode 编译 `Assets.car`、生成旧系统兼容的 `Buckle.icns`，合并 Info.plist 图标元数据。关于页通过 `NSApp.applicationIconImage` 读取同一图标，不单独复制图标。构建检查同时校验图标元数据和资源，拒绝捆绑旧版 `AppIcon.icns`。

菜单栏空闲状态使用独立的线稿模板，设计源为 `App/Resources/MenuBarIconTemplate.svg`，不从彩色应用图标提取轮廓。`MenuBarIconTemplate.png` 为 18×18 的 1× 图，`MenuBarIconTemplate@2x.png` 为 36×36 的 Retina 图，均按 18pt 显示，并随系统明暗外观着色。修改线稿时同步更新 SVG 和两张 PNG；Xcode 通过 `COMBINE_HIDPI_IMAGES` 将两种尺寸合并成 `MenuBarIconTemplate.tiff`，构建校验确认其中同时包含 18px 和 36px 图像。SVG 仅保留在源码中，不作为运行时资源打包。鼠标重置期间及完成后保留进度、成功和失败状态图标。README 的 `docs/images/readme/app-icon.png` 使用 Icon Composer 导出，文档截图来自实际运行的应用。

```bash
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" \
  Buckle.icon --export-image --output-file docs/images/readme/app-icon.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

CI 对 main 推送、PR 和手动触发执行检查及 Universal 2 构建。main 的检查全部通过且 manifest 的打包开关开启时，同一次构建继续生成 `Buckle-<version>.dmg`、SHA256 校验文件和发布说明，再由独立的 GitHub 发布任务自动创建稳定 Release；不经本地下载或上传。PR 不打包发布，编译检查任务只有只读权限。发布任务只接收当前 CI 的安装包；已发布的版本跳过，不覆盖已有附件，新增版本须递增 manifest。构建产物保留 7 天，Release 附件长期保存。不再使用独立 Package 工作流。

通知工作流读取默认分支上的脚本，不执行 fork PR 的代码或下载其构建产物。权限只读；`DISCORD_WEBHOOK_URL` 只通过 Secret 进入通知步骤，消息禁用提及，错误不打印带凭据的请求地址。通知失败会让相应工作流失败，不伪装为成功。目前没有自动重试，需通过 GitHub 重新运行失败任务。`Publish Update Feed` 的开始及完成结果也发送通知；GitHub Release 发布消息只说明 Release 已发布，不代表更新清单已同步。

### 浏览器启动参数

Chromium 浏览器只传语言开关，不传 `-AppleLanguages` 和独立的语言列表参数。Chromium 将非开关参数作为启动网址；例如独立的 `(ja)` 会被当成 `http://(ja)/`，覆盖浏览器原本的新标签页或启动页选择。Safari 的语言参数保留在独立分支。继续沿用浏览器现有资料，不指定网址、不创建独立用户目录或强制切换用户资料。

本机使用已安装的 0.1.0 从菜单启动 Chrome Beta 159.0.8154.6，复现了该错误；原日语脚本和修复后的实际 `BrowserLauncher` 都打开 `chrome://newtab/`。这项验收只覆盖该浏览器的日语启动，不代表其他浏览器和所有语言均已实机验收。依据：[Chromium 参数解析](https://github.com/chromium/chromium/blob/main/base/command_line.cc)。

### 命令边界与运行观测

`CommandRunner` 统一执行固定外部命令，不拼接用户输入。普通命令通过 `posix_spawn` 原子创建独立进程组，默认期限为 15 秒；取消或超时先向该组发送 SIGTERM，一秒后再发送 SIGKILL，并等待仍在组内的后代停止，即使最初的子进程已经退出。输出写入创建后立即解除目录链接的临时文件，避免管道写满或继承管道导致等待 EOF。非零退出保留状态与输出，启动失败、超时和取消分别报告。管理员授权使用 `waitForExit` 等待实际结果，不设置客户端超时；关闭或取消授权客户端不能证明特权工作已停止，不能据此提前恢复应用。退出仍按生命周期等待操作返回再恢复。检查只运行临时测试子进程，不刷新真实系统服务。

命令完成日志记录可执行文件名、退出状态和耗时，不记录参数、路径或凭据。Instruments 的 Points of Interest 可按子系统 `studio.slippindylan.Buckle` 查看 `Launch Setup`（启动回调中的初始化）、`Menu Build` 和 `Browser Discovery` 区间。它们用于定位后续性能测量，不代表已经完成冷启动、空闲 CPU／内存和 Finder 交互延迟的实机基线。

PermissionFlow 固定版本的查找器在 native SwiftPM 测试中漏查测试 bundle 的父目录。适配层在创建上游控制器前登记对应资源 bundle，利用 Apple 文档规定的 `Bundle.allBundles` 动态资源登记行为补全查找，仍使用上游翻译与引导，不复制翻译、不修改依赖缓存。CI 同时验证默认和 native 测试布局；升级依赖时只有在确认上游覆盖该布局且两条路径都通过后，才移除适配。

依据：[Bundle 动态资源登记](https://developer.apple.com/documentation/foundation/bundle/allbundles)、[Apple posix_spawn](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/posix_spawn.2.html)、[Apple Shell Scripts 的管理员授权](https://developer.apple.com/library/archive/technotes/tn2065/_index.html)、[共享完成回调](https://developer.apple.com/documentation/appkit/nssharingservicedelegate/sharingservice(_:didshareitems:))、[AX 属性查询](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue)、[AX 对象消息期限](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)。系统资源的文件布局和键属于已存在的私有内存窗口集成，不是 Apple 的跨版本兼容承诺。

## 本机数据与权限

### Sparkle 更新签名密钥

Buckle 使用独立的 Ed25519 密钥，不能复用其他 App 的更新私钥。1Password「开发」保险库的「Sparkle · Buckle」保存公钥、`SPARKLE_ED_PRIVATE_KEY` 和本机钥匙串账户名 `studio.slippindylan.Buckle`。公钥已写入 `App/Info.plist` 的 `SUPublicEDKey`，可以公开；私钥只能保存在钥匙串、1Password 和 GitHub Secret 中，不能进入仓库或日志。

GitHub 仓库 `SlippinDylan/Buckle` 已配置 Secret `SPARKLE_ED_PRIVATE_KEY`、`HOMEBREW_TAP_TOKEN` 与普通 Variable `SPARKLE_PUBLIC_KEY`。更新发布工作流验证私钥推导出的公钥与 Variable、源码及实际发布 App 内的公钥一致，再签署更新包和清单。私钥通过标准输入传递给官方工具的 `--ed-key-file -`，不作为命令行参数；Tap Token 仅用于读取和提交更新宿主仓库。

密钥由校验 SHA256 后的官方 Sparkle 2.10.0 `generate_keys --account studio.slippindylan.Buckle` 生成。已从 1Password 读回核对，用导出的私钥签署测试归档，并验证公钥能验签、篡改后的归档验签失败。以后恢复或导出密钥时使用同一账户名，避免误用默认账户的密钥或替换既有更新身份。

### App 更新与发布

`ApplicationUpdateController` 管理一个 Sparkle 标准更新器；主应用确认单实例后立即启动更新服务，不依赖用户激活应用或打开设置。设置窗口的通用页仅提供自动检查开关，手动检查更新统一放在关于页；自动检查开关直接读写 Sparkle 自己持久化的偏好，并通过主线程 KVO 更新界面，不在每次启动时覆盖用户选择。检查不可用时禁用入口，配置错误或启动失败在设置窗口中明确显示。网络错误及下载安装交给 Sparkle 原生界面。八种语言均补齐入口文本。

Debug 的 `BUCKLE_UPDATER_ENABLED=NO`，不要求更新源或私钥；PR 构建停用更新；main 的 CI 使用 Release 配置并启用更新。Release 使用 `BUCKLE_UPDATER_ENABLED=YES` 及 HTTPS 地址 `https://slippindylan.github.io/homebrew-tap/buckle/appcast.xml`。启动前校验地址、公钥；`SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 始终开启。首次发布前地址尚无 Buckle 清单，不能把接入代码完成当作已有更新可下载。

正式更新沿用现有 `homebrew-tap` 的 GitHub Pages `docs/` 托管，不将安装包提交到 Tap 或源码仓库：

1. 在 manifest 中递增 `version` 和 `build`，并设置 `packagingEnabled: true`。保持版本与构建号同时递增，避免 Sparkle 将新包视为旧构建。
2. 推送 main 或在 GitHub Actions 手动运行 CI，检查通过且打包开关开启时自动构建并发布，无需本地编译或中转上传。只有明确需要本地构建时才运行 `bash Scripts/build.sh Release`，再运行 `bash Scripts/create-dmg.sh build/DerivedData/Build/Products/Release/Buckle.app build/Buckle-<version>.dmg`。两种方式均启用更新器。
3. CI 自动在 `SlippinDylan/Buckle` 创建稳定 GitHub Release，标签为 `v<version>`，附件为唯一同名 `Buckle-<version>.dmg` 与 SHA256 校验文件。保持该下载地址可用，旧清单仍引用的包不要删除。私有仓库允许发布供有权限用户下载的 Release；不自动修改仓库可见性。公开更新源只允许引用公开仓库的安装包。
4. CI 创建公开仓库的稳定 Release 后显式调用 `Publish Update Feed`；手动发布的公开稳定 Release 也会触发它。GitHub 规定由 `GITHUB_TOKEN` 创建的 Release 不会再触发其他工作流，因此不能只依赖 release 事件。私有仓库和预发布版本跳过公开更新源；也可在 main 手动输入已发布稳定版标签重跑。它读取标签中的 manifest，验证开关、稳定版状态与仓库公开性，挂载 DMG 验证签名、版本、构建号、公钥、更新地址和 Sparkle 组件，再调用 `Scripts/prepare-update.sh` 生成并验签清单。历史清单从 Tap 读取，最多保留三个版本；发布说明嵌入签名清单。
5. 工作流只提交 `homebrew-tap/docs/buckle/appcast.xml`，不修改其他 App 的清单，也不自动生成 Homebrew Cask。此处使用 Tap 作为更新源宿主。推送冲突最多重试三次，失败明确报告；已发布包保持不变，可手动重跑清单同步。
6. 首次发布后验收 Pages 地址、正确和错误签名、网络失败、检查偏好保存、从旧版本实际安装更新及重启后 Finder 扩展状态。本地构建或离线签名校验不能替代线上工作流和真实升级验收。

`Scripts/prepare-update.sh <专用归档目录> <HTTPS下载目录>` 也可用于只生成文件而不发布。先解析依赖，以环境变量提供私钥和公钥；目录只存待发布归档及同名发布说明，Sparkle 可能将旧归档移入 `old_updates/`。脚本先验签已有清单，再在临时目录生成和验签候选清单；`Scripts/update_feed.py` 对照原清单验证新版本与构建号都递增，已发布构建的版本、下载地址、归档签名和长度不能改变。同一安装包可重复生成，清单验证失败时保留原清单。修改生成的清单或说明后必须重新签名，不手工修改线上已签名文件。

### 系统功能

- 浏览器启动沿用个人脚本的资料目录语义：不传 `--user-data-dir`、`--profile-directory` 或无痕参数，不创建、复制或修改用户资料目录。Chromium 使用已有浏览器资料及其自身的用户选择逻辑；多个资料时不猜测哪个账户应当打开。只传语言参数及本次进程的 AppleLanguages，不修改持久化语言偏好，不设置时区。启动前统一检查浏览器是否正在运行，已运行时只提示“浏览器已经在运行”，不退出或重启浏览器。旧版本已创建的 `~/Library/Application Support/Buckle/BrowserProfiles/` 保留原样，但不再用于启动，不自动合并或删除其中数据。依据：[Chromium 用户资料目录](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)、[NSWorkspace 启动参数](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/arguments)。
- 应用语言偏好保存在 Buckle 的 UserDefaults；登录项状态以 `SMAppService.mainApp.status` 为准。内存提醒已移除，不再读取提醒偏好、定时采样或监听内存压力。
- 鼠标重置：在「设置 → 鼠标重置」中用添加应用及逐行移除管理统一名单，默认包含 Moom、MonitorControl、BetterMouse、iShot Pro；应用选择器拒绝非 App 和 Buckle 自身，同一 bundle ID 不重复添加。名单以 bundle ID 与显示名称保存在 Buckle 的 `mouseReset.applications` 偏好中，未设置时使用默认名单，已保存的空名单不会恢复默认。名单记录损坏时停止鼠标重置并报告错误，不清空记录、不自动恢复默认名单；这与已卸载应用的跳过行为不同。通过系统按 bundle ID 查找已安装应用，用 NSRunningApplication 请求退出并等待其实际结束，通过 NSWorkspace 后台重启。失败回滚只恢复本次成功发出退出请求的已运行工具；未运行或拒绝退出的工具不会被恢复逻辑额外启动。每次重置均刷新当前用户的 `cfprefsd`；`tccd` 通过系统管理员授权执行固定命令刷新。不调用个人脚本、不打开终端、不获取或保存密码。不强制终止拒绝退出的工具，等待超时后报告失败并恢复可恢复的应用。
- 重置流程：固定执行统一退出应用、刷新当前用户的偏好服务及不限用户的系统权限服务、统一重新打开、检查运行状态，不提供仅重启应用的模式。服务刷新沿用个人脚本的目的与范围，通过系统窗口请求管理员授权。执行时读取本次名单并快照正在运行的应用。已卸载或找不到的应用直接跳过，空名单或全都缺失也继续刷新服务；原本未运行的应用不会启动。偏好与权限服务刷新后保留原脚本的 3 秒等待，再统一恢复应用；该等待不代表已验证服务就绪。设置页在重置期间禁止编辑名单，恢复使用本次快照，不重新读取设置。进度按实际步骤推进，失败恢复完成后才显示结果；成功或失败状态保留到点击「确定」，菜单栏图标同步切换。图标的无障碍描述包含当前步骤或结果，完成与失败通过 Apple 无障碍通知播报。
- Finder：自定义菜单文字通过共享配置中的可选 `language` 字段跟随主应用当前运行语言，旧配置兼容；主应用初始化时固定本次语言，语言设置仍在重启 Buckle 后生效。扩展按该语言读取自身资源，不更改系统语言。内嵌 Finder Sync 扩展通过 `menu(for:)` 返回一级菜单项，使用系统 AirDrop 的标题和图标。扩展观察根目录及已挂载卷，并处理卷挂载变化。通过带参数校验的 `buckle://finder/airdrop` URL 将文件选择交给包含它的主应用；主应用再次检查开关并调用公开 NSSharingService，不使用 shell 拼接文件路径。打开主应用失败时，扩展切回主线程显示重试提示，不只记录日志。
- Finder 开关：`~/Library/Application Support/Buckle/Finder/menus.json`，目录权限 700、文件权限 600，原子保存；扩展每次右键重新读取。主应用负责写入，沙盒扩展仅有该目录的 home-relative read-only 临时例外，不使用 App Groups、Team 或 provisioning。真实用户目录通过 `getpwuid_r` 读取，避免 Foundation 将路径重定向到扩展容器。配置文件缺失时四项右键菜单功能默认全部关闭；已有配置保留。配置损坏时明确报错，确认恢复默认前先备份原文件，恢复后四项功能全部关闭。
- 菜单栏菜单底部显示扩展缺失、未注册、未启用或操作失败的状态提示，启用后隐藏；访达扩展的状态与必要处理入口统一位于「设置 → 权限」的访达右键菜单行；已启用时显示绿色文字和勾选标识，异常时才显示对应处理操作。配置解码失败有独立状态和确认后恢复默认配置的入口，恢复前在同目录创建 `menus-backup-<UUID>.json`；备份失败则不覆盖原文件。已运行时重新打开 App 显示设置窗口，Finder 的错误说明直接指向菜单栏设置入口。通过系统公开接口打开扩展管理界面，通过 `pluginkit` 注册和请求启用，随后读取实际状态，不把命令执行成功等同于系统已启用。菜单打开及应用激活时刷新状态。单独关闭 AirDrop 入口不会禁用整个扩展，便于以后增加其他入口。
- 内存：仅通过菜单中的手动入口调用 SystemMemoryPanel，列表与强制退出完全交给系统 LowMemoryPanel。Buckle 不采样内存、不监听内存压力、不自动打开窗口。状态栏点击打开原生 NSMenu。修改 loginwindow 的 DebugShowLowMemoryPanel 前，先原子保存原值到 `~/Library/Application Support/Buckle/MemoryPanel/pending.plist`；记录保留值是否原本不存在。发送系统快捷键后，通过公开 AX API 检查 loginwindow 中包含目标内存警告文本的窗口；不把普通 ForceQuitPanel、Apple Event 成功或固定等待视为已打开。警告文本从系统自身的 LowMemoryPanel 资源读取，支持当前 `.loctable` 和旧版分语言 `.strings` 布局，避免 Buckle 的语言覆盖影响识别；资源或键变化时明确报错。已存在目标窗口时不重复触发快捷键。以 10 秒为窗口确认期限，每次读取应用、窗口或子元素前，分别将 AX 消息限制为 0.25 秒与剩余时间中的较小值；每轮遍历最多 1 秒且不越过整体期限，查询前后检查取消与截止时间，迟到的结果不算成功；无论确认成功、超时、取消或出错都恢复原值，成功恢复才删除记录。启动和正常退出也检查恢复记录，调用中正常退出会等待恢复。进程被强杀或崩溃后，无法保证立即恢复，下次启动才会继续恢复。记录不可读时拒绝覆盖，不猜测原设置。
- 调用系统窗口需要辅助功能与控制 System Events 的自动化授权。辅助功能由「设置 → 权限」中的 PermissionFlow 引导用户到系统设置手动授权，不调用系统信任弹窗。自动化授权仅在用户点击权限页的自动化按钮或手动打开系统内存窗口时请求。先确保 System Events 运行，再在后台线程调用 AEDeterminePermissionToAutomateTarget 检查权限。使用 System Events 字典中的 `prcs/kcod` Apple Event 发送相同的 Command–Option–Escape，并设置 `kAEDoNotPromptForUserConsent` 和 10 秒发送超时；检查传输错误及目标回复中的错误。该调试路径属于私有系统行为，不能以源码类型检查或模拟测试代替各支持版本的实测。

### 操作期间退出与更新

`ApplicationLifecycle` 统一登记内存窗口操作（含权限检查）、鼠标重置、Finder 操作和系统菜单栏重启，退出分为正常运行、等待操作、退出恢复三个阶段。收到正常退出请求后停止接收新操作，等待已有操作结束，再进入退出恢复；进入恢复阶段后，重复退出请求不会再次启动恢复任务。Sparkle 安装更新通过正常退出事件进入同一协调流程，不单独维护更新专用的忙碌状态。

`ApplicationRecovery` 在退出边界分别恢复内存设置和鼠标工具，其中一项失败也必须尝试另一项；错误类型明确区分内存、鼠标及两项都失败，保留完整原因。完成业务流程不等于已经恢复，退出判断以这次实际恢复结果为准。恢复失败时默认取消退出，允许重试恢复或明确选择仍然退出；重试不重新执行停止应用、刷新系统服务或管理员授权。取消后重新开放操作，鼠标待恢复进程和内存恢复文件保持不变，之后再次退出仍执行恢复。明确继续退出仍保留鼠标与内存恢复记录，界面说明工具可能需要手动重新打开，下次启动可以继续恢复。

鼠标重置按具体进程记录已接受的退出请求；随后有工具拒绝退出时，也先等待已发出的请求完成，再进入恢复。恢复前再次确认原进程已退出，MonitorControl helper 的恢复归属主工具。鼠标待恢复名单原子保存在 `~/Library/Application Support/Buckle/MouseReset/pending.json`，记录原应用与进程身份；异常退出后，下次启动询问是否恢复。启动恢复进行中，新的鼠标重置入口禁用，并在创建窗口前检查同一准入条件，避免显示没有进度的窗口；正常重置的进度和结果窗口仍可重新打开。选择稍后不立即恢复，也不在普通退出时擅自恢复，但保留记录；用户之后选择恢复或发起新重置时先处理旧记录，不用新操作覆盖。退出或恢复超时会明确报告失败并保留记录。只有确认退出并完成恢复启动后才清除对应记录，不强制结束第三方应用。管理员授权沿用原脚本 `sudo killall tccd` 的权限需求，由系统授权弹窗执行固定的 `/usr/bin/killall -q tccd`；`cfprefsd` 只针对当前用户，不提升整个 App 的权限。两者只将 `killall -q` 返回 1 且没有诊断输出视为无匹配进程、无需停止；权限不足及其他错误保留，不忽略所有非零结果。

内存恢复记录损坏或恢复失败时，不覆盖记录、不猜测原设置。退出确认提供查看记录的入口，查看后取消本次退出；内存窗口仍需先成功恢复记录才可修改设置。明确继续退出可能让临时设置继续有效，下次启动仍尝试恢复。

AirDrop 通过共享完成、失败或用户取消回调结束本次 Finder 操作；发起 `perform(withItems:)` 后继续保留服务和生命周期登记。正常退出及 Sparkle 更新退出等待回调，不在共享窗口仍活跃时提前结束登记。用户取消属于正常结束；真正的共享错误返回统一调用方，由生命周期规则决定是否展示，退出期间不再弹普通错误。

### 更新后的权限复查

ad-hoc 签名的指定要求绑定具体构建，不能保证跨版本保留 TCC 授权。启动、打开权限页和应用重新激活时静默复查辅助功能、自动化权限及访达扩展状态，复查失败单独报告，不覆盖内存设置恢复错误。「设置 → 权限」以辅助功能、自动化、访达右键菜单三行卡片显示状态及必要操作；已授权或已启用时显示绿色文字和勾选标识，不另设手动检查权限按钮。辅助功能按钮复用 PermissionFlow 的飞入动画、应用拖拽卡片和系统设置窗口跟随，卡片对应当前 Buckle.app；不弹系统信任提示。自动化不属于 PermissionFlow 的引导面板，先通过 Apple Events 请求控制 System Events；仍未获授权时才跳转到系统自动化设置。更新后若原授权失效，可在系统设置移除旧辅助功能条目、添加当前版本，并允许控制 System Events；返回应用后自动刷新状态。后台检查不弹授权窗口，只有用户显式操作才请求自动化授权。

设置页的手动自动化授权进行中，内存窗口菜单入口禁用，主应用入口和执行层复用同一个准入判断；授权成功或失败后重新开放入口。后台权限检查与打开窗口是独立的操作，两者都参与退出协调。手动打开先登记请求，等待已有检查任务完成（包括状态写回），再继续授权及打开窗口；重复打开不会并行执行。等待时如果收到退出请求，则放弃打开窗口，在检查结束后完成退出。

新增自动检查覆盖：并行操作的退出等待、拒绝退出后的新操作、鼠标成功及失败恢复后的退出、损坏恢复记录时取消或保留记录退出、权限状态重新检查、AirDrop 取消与其他错误的区别。测试不打开系统窗口、不重置实际服务、不执行更新。

回归检查还覆盖延迟退出与部分拒绝退出同时发生、退出超时后的恢复重试、helper 的恢复归属、权限检查中手动打开及重复点击、等待期间退出，以及官方 Sparkle 工具生成清单时拒绝重复构建号和未递增版本，并确认失败不覆盖原清单。

退出恢复检查使用实际 `ApplicationRecovery`，组合覆盖退出请求在重置期间或之后发生、仅鼠标恢复失败或两项都失败，以及重试/取消/明确退出三种决定。另用实际 `NativeMouseReset` 和模拟系统边界检查退出超时、重新启动失败、取消退出及关闭结果页后再次恢复；单独验证内存记录损坏时仍恢复鼠标、干净退出无需确认、异步恢复期间重复退出只处理一次。测试不实际终止应用、刷新服务或弹出授权窗口。

依据：[Apple 退出协调](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:))、[Sparkle 安装与退出契约](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html)、[AirDrop 取消回调](https://developer.apple.com/documentation/appkit/nssharingservicedelegate/sharingservice(_:didfailtoshareitems:error:))、[Apple 签名要求与 ad-hoc 身份](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

## 纳入与排除

应提交：源码、测试、八种语言资源、正式图标、Xcode 工程与共享 scheme、版本 manifest 及生成的版本配置、自动化脚本、正式文档。未来增加依赖时，锁文件应提交。

由 `.gitignore` 排除：`build/`、`.build/`、DerivedData、app/DMG/归档/dSYM、Xcode 用户状态、编辑器私有设置、日志、`.env`、签名凭据、`Config/Local.xcconfig`、个人草稿及参考项目。不得依赖忽略规则保护已经跟踪的密钥，任何凭据都不能写入源码或日志。

## 实机验收

类型检查和模拟测试不能替代下列系统验收。尚未逐项实测的项目保持待验收，不以新增代码或本机检查通过替代结论：

1. 运行和 Spotlight 只有一个正式安装副本，Dock 不显示图标，关闭面板后继续后台运行。
2. 八种系统首选语言下的 UI、菜单、Finder 原生 AirDrop 名称，以及浅色/深色和 VoiceOver 操作。
3. 浏览器沿用原有资料与登录状态、多个用户资料的浏览器自身选择行为、所有受支持浏览器已运行时仅显示提示，以及正常退出后切换启动语言。
4. Finder 一级菜单和系统图标、多文件及文件夹 AirDrop、取消传输、入口开关、外置盘与新挂载卷；扩展缺失/未注册/禁用时的底部引导、系统设置返回后的状态刷新。
5. 菜单栏原生菜单打开系统 LowMemoryPanel，确认正常内存状态也可手动打开、辅助功能/自动化权限拒绝和临时系统偏好恢复。
6. 鼠标重置名单的添加、去重、移除、空态和重启后保存，以及所有已运行应用先退出再统一恢复、未运行应用不启动、卸载应用跳过、空名单仍刷新服务、异常退出后下次启动的恢复与稍后选项；验证每次重置均执行服务刷新、系统管理员授权、取消授权、应用拒绝退出、重启/恢复失败及状态图标，以及开机自启批准/禁用/重新登录。模拟检查不会实际终止应用或刷新系统服务。
7. GitHub 中实际执行打包开关启闭后的 CI，核对检查失败不发布、PR 不发布、已有版本不覆盖，以及 DMG 架构、版本、校验和、Release 附件及 Discord 通知。
8. 鼠标重置或内存窗口调用期间正常退出、由 Sparkle 安装更新触发退出，确认等待恢复完成；恢复失败时验证取消、重试、明确继续退出及内存记录查看。确认取消后可再次恢复，重试不再次重置服务或请求管理员授权。
9. 已授权的旧版本通过 Sparkle 更新后，验证新版本权限检测、重新授权指引和返回应用后的自动复查；不能以相同版本的模拟权限检查代替真实升级验收。

项目明确不购买付费 Apple 开发者证书。开发与 GitHub 分发以无需账号的 ad-hoc 签名为目标，不将 Developer ID、公证或 App Store 上架作为交付前提。ad-hoc 签名不提供 Apple 验证的开发者身份，也不能用于常规 Developer ID 公证；从网络下载时用户可能需要在系统设置中明确允许运行，并单独启用 Finder 扩展。主应用和扩展的签名、注册、加载及权限必须按该无付费证书方案实测，不能仅凭主应用可编译便宣称扩展可用。不要引入必须依赖付费团队或 provisioning 的能力作为基础功能前提。开源许可证需由项目所有者选择。

## 系统窗口与原生图标调查

本机 loginwindow 资源中分别存在 `ForceQuitPanel` 与 `LowMemoryPanel`，后者包含“系统的应用程序内存不足”的提示；两者不能混为同一个窗口。正常内存状态也能读取进程内存，是否显示该面板由系统决定。对当前本机 macOS 27.0.1 二进制的只读检查发现 `showForceQuitPanel` 会读取 `DebugShowLowMemoryPanel` 并进入低内存面板的调试路径；该路径已使用临时调试设置与系统快捷键在本机打开，用户确认正是需要的窗口，随后删除临时设置恢复了原值。现在已接入 App 的手动内存入口；集成代码有成功、失败及恢复失败的模拟检查，但未执行完整 App 实机验收，也不能当作跨 macOS 版本的已验证接口。

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

## 原生界面与新增 Finder 操作

状态菜单使用 `NSStatusItem.menu` 与 `NSMenu`，以原生 sectionHeader 和分隔线按系统工具、应用启动、访达右键菜单分组，底部相邻显示设置和退出，功能入口始终显示，不提供隐藏开关；访达右键菜单的四个功能通过菜单勾选项启停，首次使用默认关闭，保留已有配置。不再使用 `NSPopover`。设置窗口沿用 Alcove 的 400×450 内容尺寸、原生偏好工具栏、卡片行样式与关于页排版；设置包含通用、鼠标重置、权限、关于四页，分别组织偏好、重置应用名单、授权与访达扩展状态、真实版本元数据；访达四项功能开关仍在菜单栏。菜单栏只提供一个设置入口，保留上次选择页；检查更新与关于均在设置窗口内。鼠标进度使用独立窗口，任务和结果不依赖窗口是否可见。

Finder 菜单自定义文字跟随 Buckle 的运行语言，原生 AirDrop 标题仍由系统共享服务提供。Finder 菜单区分 `.contextualMenuForItems` 和 `.contextualMenuForContainer`。上下文快照放在菜单项中，不在执行时重新读取可能已改变的选区。终端使用公开 `NSWorkspace.open` 将目录 URL 交给系统 Terminal，不拼接 shell 命令。复制路径在扩展内向剪贴板写入纯文本；公共 URL 不接受复制路径操作。普通文件夹才作为终端与移动目标，应用包不是普通目标目录。

`FinderActionRequest` 扩展原有路由，保留 `buckle://finder/airdrop`；终端、移动同样校验本地文件 URL、动作和数量。移动请求携带菜单创建时的剪贴板版本。主 App 再次检查功能开关与剪贴板，使用不可变源/目标计划显示确认，确认后再次检查版本。公开 URL 不能静默发起破坏性移动。取消不移动，退出后不接收新操作；已经开始的移动完成后才允许正常退出。

`FinderMoveRunner` 使用 `NSFileCoordinator` 的异步协调接口，为每个文件等待协调设置 15 秒期限，等待期间支持取消。协调回调已开始实际移动后不再用等待期限中断，继续等待该次移动结果，不把仍在执行的移动报告为已取消。通过 `.forMoving` 协调，再用 `FileManager.moveItem` 操作协调器传入的 URL，并在成功后发出 `didMoveTo` 通知。不使用 AppleScript 将源路径强制转换成 alias，避免移动链接的真实目标。移动前校验源、目标、同名项目、重复目标名称与目录自包含；底层移动仍拒绝覆盖，避免仅依赖预检查。跨卷由 FileManager 先复制后删除原项。错误保留底层原因并提示可能部分完成；不自动回滚、不伪装成原子批量事务，不提供 Finder 撤销记录。

新增检查包含旧配置迁移、文件夹/空白上下文、中文及特殊字符路径、URL 边界、独立开关、剪贴板变化、移动取消与退出协调、真实临时文件及符号链接移动、重名拒绝，以及系统菜单栏重启的模拟进程序列。普通检查不重启真实系统服务，不打开浏览器或终端，不操作个人文件。

依据：[Finder 菜单类型](https://developer.apple.com/documentation/findersync/fimenukind)、[Finder 目标路径](https://developer.apple.com/documentation/findersync/fifindersynccontroller/targetedurl())、[应用打开 URL](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:))、[原生文件移动及链接语义](https://developer.apple.com/documentation/foundation/filemanager/moveitem(at:to:))、[异步文件协调](https://developer.apple.com/documentation/foundation/nsfilecoordinator/coordinate(with:queue:byaccessor:))、[取消等待中的协调](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel())、[macOS 设置窗口规范](https://developer.apple.com/design/human-interface-guidelines/settings)。

应用语言通过 `application.language` 保存选择，默认值为 `system`。手动选择时仅在当前应用偏好域写入 `AppleLanguages`，选择系统时移除该覆盖，由 Foundation 匹配系统偏好与八种已打包语言。语言变更在下次启动生效，与 Alcove 的行为一致。开发模式保留更新禁用逻辑，不显示开发模式提示。
