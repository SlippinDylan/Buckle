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

菜单栏空闲状态使用独立的线稿模板，设计源为 `App/Resources/MenuBarIconTemplate.svg`，不从彩色应用图标提取轮廓。`MenuBarIconTemplate.png` 为 20×20 的 1× 图，`MenuBarIconTemplate@2x.png` 为 40×40 的 Retina 图，均按 20pt 显示，使用已确认的加粗线稿，并随系统明暗外观着色。修改线稿时同步更新 SVG 和两张 PNG；Xcode 通过 `COMBINE_HIDPI_IMAGES` 将两种尺寸合并成 `MenuBarIconTemplate.tiff`，构建校验确认其中同时包含 20px 和 40px 图像。SVG 仅保留在源码中，不作为运行时资源打包。鼠标重置期间及完成后保留进度、成功和失败状态图标。README 的 `docs/images/readme/app-icon.png` 使用 Icon Composer 导出，文档截图来自实际运行的应用。

```bash
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" \
  Buckle.icon --export-image --output-file docs/images/readme/app-icon.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

CI 对 main 推送、PR 和手动触发执行检查及 Universal 2 构建。main 的检查全部通过且 manifest 的打包开关开启时，同一次构建继续生成 `Buckle-<version>.dmg`、SHA256 校验文件和发布说明，再由独立的 GitHub 发布任务自动创建稳定 Release；不经本地下载或上传。PR 不打包发布，编译检查任务只有只读权限。发布任务只接收当前 CI 的安装包；发布前通过 GitHub Git References／Tags API 检查已有版本标签最终指向本次构建的提交，兼容普通标签与附注标签；不一致或查询失败时停止，不自动移动或覆盖标签。标签不存在时由 GitHub CLI 按本次构建提交创建。已发布的版本跳过，不覆盖已有附件，新增版本须递增 manifest。构建产物保留 7 天，Release 附件长期保存。不再使用独立 Package 工作流。

### 版本变更说明

根目录 `CHANGELOG.md` 是 GitHub Release 与 Sparkle 更新说明的唯一内容来源，全部使用英文，面向用户说明真实变化，不直接堆叠 commit message。开发时写在 `## [Unreleased]` 下；准备发布时移入 `## [版本] - YYYY-MM-DD`，分类使用 Added、Improved、Changed、Fixed、Removed、Security，必要时使用 Known Issues；没有内容的分类省略，每条为单行 `- ` 列表。

`node .github/scripts/release-notes.mjs --check` 验证当前 manifest 对应版本的说明；`--tag v0.1.2` 额外核对目标标签；默认输出当前版本段落，`--output <路径>` 写入指定文件。脚本拒绝重复版本、非法标题或日期、缺失版本、空分类及占位内容。英文和内容真实性仍需人工审核，脚本不替代语义审查。`Scripts/check.sh` 包含此检查；CI 只把当前版本段落作为 Release 正文，发布前再次核对构建产物里的正文。

更新源工作流从已发布标签中的 CHANGELOG 与 manifest 提取同一段文字，不读取可手动修改的 GitHub Release 正文。同名 `.md` 文件交给锁定的 Sparkle 2.10.0 `generate_appcast --embed-release-notes` 处理 Markdown 并嵌入签名清单，不自行维护第二份 HTML。此规则从 0.1.2 开始；旧标签没有 CHANGELOG 时会明确拒绝重建其更新说明，不改写已有发布或线上清单。依据：[Sparkle 2.10.0 更新说明实现](https://github.com/sparkle-project/Sparkle/blob/2.10.0/generate_appcast/FeedXML.swift)。

通知工作流读取默认分支上的脚本，不执行 fork PR 的代码或下载其构建产物。权限只读；`DISCORD_WEBHOOK_URL` 只通过 Secret 进入通知步骤，消息禁用提及，错误不打印带凭据的请求地址。推送通知排除 `dependabot/**` 分支，避免机器人推送无法读取 Actions Secret 而失败；依赖更新仍通过 PR 和 CI 开始／完成事件通知，普通分支推送、Issue、评论和 Release 通知保留。通知失败会让相应工作流失败，不伪装为成功。目前没有自动重试，需通过 GitHub 重新运行失败任务。`Publish Update Feed` 的开始及完成结果也发送通知；GitHub Release 发布消息只说明 Release 已发布，不代表更新清单已同步。

### 浏览器启动参数

Chromium 浏览器只传语言开关，不传 `-AppleLanguages` 和独立的语言列表参数。Chromium 将非开关参数作为启动网址；例如独立的 `(ja)` 会被当成 `http://(ja)/`，覆盖浏览器原本的新标签页或启动页选择。Safari 的语言参数保留在独立分支。继续沿用浏览器现有资料，不指定网址、不创建独立用户目录或强制切换用户资料。

本机使用已安装的 0.1.0 从菜单启动 Chrome Beta 159.0.8154.6，复现了该错误；原日语脚本和修复后的实际 `BrowserLauncher` 都打开 `chrome://newtab/`。这项验收只覆盖该浏览器的日语启动，不代表其他浏览器和所有语言均已实机验收。依据：[Chromium 参数解析](https://github.com/chromium/chromium/blob/main/base/command_line.cc)。

日语脚本对照：通过 `NSWorkspace.OpenConfiguration.environment` 传递 `TZ=Asia/Tokyo`，只影响新启动的浏览器进程，不修改系统时区。使用当前实际启动器的独立检查程序启动 Chrome Beta 159.0.8154.6，网页返回 `language=ja-JP`、`languages=[ja-JP,ja]`、`timeZone=Asia/Tokyo`、`offset=-540`，启动页仍为 `chrome://newtab/`；原脚本返回相同结果。`offset` 是 UTC 减本地时间的分钟数，日本 UTC+9 对应 -540。这不是已安装 Buckle 新版本的验收，Safari 及其他浏览器仍需实测。依据：[NSWorkspace 启动环境](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/environment)。

这两种启动方式下，`Intl.DateTimeFormat().resolvedOptions().locale` 仍为 `zh-CN`。Chrome 在 macOS 上以应用的首选本地化覆盖自身地区格式，网页语言和时区参数不等同于这项设置。尚未找到同时满足“临时生效、不修改持久化偏好、不创建用户目录、不添加启动网址”的可靠地区格式覆盖方式；不把语言参数测试通过视为地区格式已经切换。依据：[对应版本 Chromium 的 macOS 本地化实现](https://github.com/chromium/chromium/blob/159.0.8154.6/ui/base/l10n/l10n_util_mac.mm)。

鼠标脚本对照：默认四款应用与脚本一致；DockDoor、OneSwitch 在脚本里只用于状态显示，不是退出或恢复对象。按后续需求统一为“退出所选且原本运行的应用 → 刷新服务 → 恢复这些应用”，未运行或已卸载的应用不启动。服务刷新后默认等待三秒，可在鼠标重置设置中调整；不照搬旧脚本各组应用之间的固定等待。原脚本的 MonitorControlHelper `bootout` 调用把 bundle ID 放在路径参数位置且忽略错误，不能据此认定服务卸载有效；当前通过运行实例与恢复记录管理 helper，不新增无依据的 launchd 卸载。本轮仅完成代码与脚本对照，未执行真实服务刷新或管理员权限重置。

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

- 浏览器启动沿用个人脚本的资料目录语义：不传 `--user-data-dir`、`--profile-directory` 或无痕参数，不创建、复制或修改用户资料目录。Chromium 使用已有浏览器资料及其自身的用户选择逻辑；多个资料时不猜测哪个账户应当打开。Chromium 只传语言开关；Safari 使用本次进程的 AppleLanguages 参数。不修改持久化语言偏好。日语启动按原脚本传入 `TZ=Asia/Tokyo`，Chromium 参数为 `--lang=ja-JP --accept-lang=ja-JP,ja`；其他语言未约定唯一地区，保留系统时区。启动前统一检查浏览器是否正在运行，已运行时只提示“浏览器已经在运行”，不退出或重启浏览器。旧版本已创建的 `~/Library/Application Support/Buckle/BrowserProfiles/` 保留原样，但不再用于启动，不自动合并或删除其中数据。依据：[Chromium 用户资料目录](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)、[NSWorkspace 启动参数](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/arguments)。
- 应用语言偏好保存在 Buckle 的 UserDefaults；登录项状态以 `SMAppService.mainApp.status` 为准。内存提醒已移除，不再读取提醒偏好、定时采样或监听内存压力。
- 鼠标重置：在「设置 → 鼠标重置」中用添加应用及逐行移除管理统一名单，默认包含 Moom、MonitorControl、BetterMouse、iShot Pro；应用选择器拒绝非 App 和 Buckle 自身，同一 bundle ID 不重复添加。名单以 bundle ID 与显示名称保存在 Buckle 的 `mouseReset.applications` 偏好中，未设置时使用默认名单，已保存的空名单不会恢复默认。名单记录损坏时停止鼠标重置并报告错误，不清空记录、不自动恢复默认名单；这与已卸载应用的跳过行为不同。通过系统按 bundle ID 查找已安装应用，用 NSRunningApplication 请求退出并等待其实际结束，通过 NSWorkspace 后台重启。失败回滚只恢复本次成功发出退出请求的已运行工具；未运行或拒绝退出的工具不会被恢复逻辑额外启动。每次重置均刷新当前用户的 `cfprefsd`；`tccd` 通过系统管理员授权执行固定命令刷新。不调用个人脚本、不打开终端、不获取或保存密码。不强制终止拒绝退出的工具，等待超时后报告失败并恢复可恢复的应用。
- 重置流程：固定执行统一退出应用、刷新当前用户的偏好服务及不限用户的系统权限服务、统一重新打开、检查运行状态，不提供仅重启应用的模式。服务刷新沿用个人脚本的目的与范围，通过系统窗口请求管理员授权。执行时读取本次名单并快照正在运行的应用。已卸载或找不到的应用直接跳过，空名单或全都缺失也继续刷新服务；原本未运行的应用不会启动。偏好与权限服务刷新后，按「设置 → 鼠标重置」中的等待秒数再统一恢复应用；默认 3 秒，可设 0–60 整秒，0 表示不额外等待。等待秒数单独保存在 `mouseReset.serviceWaitSeconds`，不改变已有应用名单格式；重置开始前读取并固定本次值，设置页在重置中禁止编辑。该等待不代表已验证服务就绪。设置页在重置期间禁止编辑名单，恢复使用本次快照，不重新读取设置。进度按实际步骤推进，失败恢复完成后才显示结果；成功或失败状态保留到点击「确定」，菜单栏图标同步切换。图标的无障碍描述包含当前步骤或结果，完成与失败通过 Apple 无障碍通知播报。
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

AirDrop 将调用系统分享服务与分享会话分开：`perform(withItems:)` 返回后即释放 `.finderAction`，不等待传输回调，正常退出与 Sparkle 更新退出也不等待 AirDrop。调用返回不表示窗口已呈现或文件传输成功。每次分享使用独立 delegate，会话保留服务及 delegate；结束回调只处理一次，按 delegate 所属会话清理，不能按系统传回服务包装对象的引用身份或值相等识别请求。会话未结束时拒绝再次打开 AirDrop，终端和移动不受此状态影响。用户取消不报错；其他异步分享错误显示系统错误，退出期间按原生命周期规则抑制错误窗口。日志仅记录事件、项目数量及错误 domain/code，不记录文件路径。没有结束回调时只保留 AirDrop 会话，不占用共用操作状态；不引入超时、窗口监听或自动重试。退出宿主可能关闭分享窗口，传输中的退出影响尚未验收，不承诺系统分享完全独立于 Buckle。

### 更新后的权限复查

ad-hoc 签名的指定要求绑定具体构建，不能保证跨版本保留 TCC 授权。启动、打开权限页和应用重新激活时静默复查辅助功能、自动化权限及访达扩展状态，复查失败单独报告，不覆盖内存设置恢复错误。「设置 → 权限」以辅助功能、System Events 自动化、访达自动化、访达右键菜单四行卡片显示状态及必要操作；已授权或已启用时显示绿色文字和勾选标识，不另设手动检查权限按钮。辅助功能按钮复用 PermissionFlow 的飞入动画、应用拖拽卡片和系统设置窗口跟随，卡片对应当前 Buckle.app；不弹系统信任提示。自动化不属于 PermissionFlow 的引导面板；System Events 与 Finder 使用相同的 `AEDeterminePermissionToAutomateTarget` 查询，分别保存和显示授权状态，只在对应授权按钮点击后请求该目标的授权；仍未获授权时才跳转到系统自动化设置。更新后若原授权失效，可在系统设置移除旧辅助功能条目、添加当前版本，并按所用功能允许控制 System Events、Finder；返回权限页后自动刷新两个目标的状态。后台检查不弹授权窗口，只有用户显式操作才请求自动化授权。

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

### 本机最小验证（2026-11-15）

环境为 macOS 27.2.1，已安装 Buckle 0.1.2（构建 3）。下列首轮原生移动实验直接通过 Finder 快捷键验证，实验时尚未接入 Buckle；后续源码接入后的验证单独记录，不代表已安装应用具备新实现。

- 桌面临时目录内，进入目标文件夹后发送 `Command–Option–V`，50 个文件全部移入，包含子目录和中文、空格、引号文件名；逐文件内容校验一致，`Command–Z` 全部恢复。只选中目标文件夹而不进入时，同一快捷键将文件移到当前父目录，因此不能直接替换现有的指定目录移动入口。
- 原生移动遇到同名测试文件时，Finder 显示「保留两者／停止／替换」；选择停止后，源与目标内容均保持不变。
- OneDrive 与 iCloud 各使用 3 个临时文件，原生移动和撤销后内容一致。iCloud 撤销过程中出现从云盘移回本机的系统确认。两处临时目录的空白处菜单均未观察到 Buckle 的终端和复制路径入口；不据此推断所有云盘场景。未验证远端设备同步、外置盘、SMB、空间不足或断连。
- 通过已安装应用的 Finder URL 路由打开 Terminal，检查新建 shell 的实际工作目录与测试目标一致；此项不等同于扩展菜单点击链路验收。复制路径写入逻辑的独立剪贴板检查通过；后续直接操作 Finder 的 `Command–Option–C`，单文件、多文件和文件夹均取得正确路径，包含中文、空格和引号。本机快捷键输出对空格、引号添加反斜杠转义，多文件以空格分隔，与 Buckle 当前不转义、按行连接的文本格式不同。两项检查均不能代替已安装扩展菜单点击链路的验收。
- 通过同一路由打开系统 AirDrop，附近没有可用接收者，未发送文件。按 Escape 后分享窗口关闭，但后续终端请求仍收到 Finder 操作忙碌提示；因此取消后的生命周期释放未通过。用户授权后仅重启同一安装副本，终端请求恢复正常，未替换或更新应用。不能把窗口关闭视为分享操作已经完成。

本轮随后通过临时命令行工具调用当前源码的 `FinderMoveRunner` 与实际脚本，将含中文、空格、引号的文件和带子文件的目录移入另一目标目录，内容校验通过；Finder 原生撤销恢复两项。工具使用桌面自动化宿主已有权限，并绕过仅用于检查主应用授权的辅助功能探测；不代表新签名应用的授权、扩展点击、多个窗口／标签页竞争或用户切换焦点均已验收。`bash Scripts/check.sh` 全部通过，未完整构建、替换或重启已安装应用。

本轮 AirDrop 单独调查使用临时原生命令行程序与 AppKit 事件循环，不替换或重启已安装 Buckle，不选择接收者、不发送文件、不操作剪贴板。临时副本仅为当前 `AirDropService` 增加观测，并复用实际 `ApplicationLifecycle`：`perform` 返回后，Escape 关闭分享窗口触发了 `didShareItems`，但回调服务与 `pending.service` 的引用身份不同，当时实现的 `===` 检查拒绝结束回调，`.finderAction` 保持活跃。在仅将临时副本该检查改为值相等后，同一关闭流程恢复 continuation 并释放操作状态。因此本机已复现的直接原因是回调对象引用身份检查，不能继续笼统归因于未收到系统回调。没有实际发送文件，不能把该 `didShareItems` 回调当作接收端已收到文件。

独立实验同时确认：

- 打开分享服务后立即释放快捷入口操作登记，实际 `ApplicationLifecycle` 可接收下一次 Finder 操作；该检查没有通过已安装扩展启动终端。
- 同一 `NSSharingService` 在窗口关闭后可再次使用；窗口未关闭时重复调用会产生两套分享窗口，因此重复点击仍需单独明确处理。
- 本机释放最初创建的服务对象后，弱引用变空，分享窗口仍存在，Escape 仍触发 delegate；这只验证呈现与关闭，不证明传输阶段或其他系统版本无需保留服务。
- 两个独立创建的 AirDrop 服务也可能值相等（`==`），因此不能把改用值相等当成可靠的逐次请求身份校验；正式修改应明确每次分享与其回调的归属。
- 分享选择窗口打开期间退出临时宿主，窗口服务器检查确认该组窗口消失；未实测传输中退出，不能声称退出宿主不会影响 AirDrop。

当前源码已通过临时工具进行两轮实际 AirDrop 呈现、Escape 关闭与重新打开，重复请求均被拒绝，分享窗口打开期间的其他 Finder 操作通过注入的终端执行入口被接受，结束后正常退出登记无需等待。测试链接实际 `AirDropService`、`FinderActionService` 和 `ApplicationLifecycle`，没有打开真实终端或发送文件；不代表新版安装扩展链路、实际接收端传输或传输中退出已验收。

随后使用用户确认的 iPhone 验证了实际图片接收。临时脚本链接当前 `AirDropService`，只增加转发回调的诊断 delegate，不修改产品代码；图片由 AppKit 生成，不读取私人照片，不操作剪贴板，不替换或重启已安装 Buckle。

- PHONE-01：509,354 字节 PNG，Mac 显示已发送，用户确认收到且可打开；点击完成后收到 `didShareItems`。
- PHONE-02：40,034,372 字节 PNG，用户确认收到且可打开。测试工具的文字识别耗时约 31 秒，错过发送状态，没有在传输中退出，不能算作中途退出验证。期间设备短暂不可发现，保持 iPhone 解锁后恢复。
- PHONE-03：40,034,362 字节 PNG，选择已确认的设备并点击发送后，立即写入退出信号，测试程序在下一次约 250 毫秒轮询内结束进程。用户确认随后收到 PHONE-03 且可打开。本机这次发起发送后立即结束测试进程没有阻止接收；没有精确捕捉退出时的传输阶段，不能等同已确认传输中退出，也不能代替正式 Buckle 的正常退出或 Sparkle 更新链路验收。

上述结果不构成所有系统版本和网络环境下分享完全独立于宿主的保证。Mac 上的临时脚本、测试图片和局部分享窗口截图已清理；iPhone 上的测试图片由用户自行保留或删除。

本轮 Review 修复后，独立工具链接当前移动源码并使用实际权限探测，分别在美式 QWERTY、标准 Dvorak、Dvorak–QWERTY ⌘、中文拼音下完成临时文件与带子文件目录的移动和 Finder 原生撤销，内容校验通过；保留多个测试 Finder 窗口，并额外验证了新建标签页后的移动和撤销。测试恢复原有剪贴板、活动输入源与输入源启用列表，关闭自建窗口并删除临时文件。按字符发送的候选方案在 Dvorak–QWERTY ⌘ 下未触发移动，该阶段曾改用原生菜单操作；后续确认快捷键属性不能标识命令，最终采用下文记录的按当前布局解析键位方案。

安全测试的反向验证在临时副本中故意移除最终拒绝门控，测试在错误窗口场景失败，证明不再只是检查预设返回字符串。完整工程检查通过。未替换、重启已安装 Buckle；独立工具的真实权限通过不能代替新签名安装版的授权身份及完整扩展点击链路验收。

本次实现后的 `bash Scripts/check.sh` 全部通过，包含类型检查、格式、多语言、分享会话回归与无回调时的其他操作和退出检查。未完整构建或替换已安装应用。

上述调查阶段未修改产品 AirDrop 实现；后续已按本节生命周期契约实现独立会话和即时结束快捷入口任务。临时诊断工具已清理；已安装 Buckle 保持原进程。Apple 文档说明 `perform(withItems:)` 通常显示分享窗口，返回值为 `Void`，没有“已显示”确认；delegate 的结束回调和宿主退出策略仍需分别建模。

验证工具最初未统一临时目录的 `/var` 与 `/private/var` 路径，错误判定剪贴板不属于测试并未恢复该次快照；已修正比较方式，最终验证确认恢复到其运行前内容，但不能追溯恢复此前丢失的快照。此问题属于临时测试工具，不在产品代码中。

移动验证的测试目录、临时窗口与功能开关已恢复；当时剪贴板出现新的非测试内容，保留最新内容，未用旧快照覆盖。后续原生复制验证的测试工具曾在恢复剪贴板时出错，未能恢复那次验证前的内容；该错误来自测试工具，不作为 Buckle 复制功能的故障依据。

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

Finder 菜单自定义文字跟随 Buckle 的运行语言，原生 AirDrop 标题仍由系统共享服务提供。右键菜单仅 AirDrop 保留系统图标，终端、复制路径及移动入口只显示文字。Finder 菜单区分 `.contextualMenuForItems` 和 `.contextualMenuForContainer`。上下文快照放在菜单项中，不在执行时重新读取可能已改变的选区。终端使用公开 `NSWorkspace.open` 将目录 URL 交给系统 Terminal，不拼接 shell 命令。复制路径在扩展内向剪贴板写入纯文本；公共 URL 不接受复制路径操作。普通文件夹才作为终端与移动目标，应用包不是普通目标目录。

`FinderActionRequest` 扩展原有路由，保留 `buckle://finder/airdrop`；终端、移动同样校验本地文件 URL、动作和数量。移动请求携带菜单创建时的剪贴板版本。主 App 再次检查功能开关与剪贴板，建立不可变源/目标计划后直接派发，不额外弹出移动确认框。退出后不接收新操作；生命周期只等待快捷键派发返回，不等待 Finder 的实际传输结束。

`FinderMoveRunner` 不再执行文件移动。执行前分别检查辅助功能及 Finder、System Events 自动化授权，拒绝时明确指出缺少哪一项。固定的 AppleScript 通过参数取得目标路径与剪贴板版本，进入目标文件夹、清空旧选区并激活 Finder；等待窗口和插入位置就绪。使用 AppKit `NSEvent.characters(byApplyingModifiers:)` 按当前键盘布局及 Command 修饰键解析 V 的物理键位，包含 Dvorak–QWERTY Command 的专用映射；随后重新读取并验证窗口、目标、插入位置、焦点、附属对话框与剪贴板，向 Finder 发送 Command–Option–V。只接受唯一键位，不硬编码美式键码，不发送字符事件，不扫描菜单、不匹配标题或依赖私有菜单标识。Finder 或全局 `NSUserKeyEquivalents` 存在自定义菜单快捷键时明确停止，避免默认组合被重新分配后触发其他命令。该检查会拒绝这些域内的任意菜单快捷键自定义，并不只检查移动命令。

路径不插入脚本文本，不转换源文件为 alias，不自动重试或回退到 FileManager。发送快捷键前仍有状态读取与执行之间的竞争窗口，不能宣称 UI 自动化具有原子性。快捷键派发超时或报错也不能推断移动一定未开始。

原生移动的进度、同名冲突、替换选择、失败结果及撤销由 Finder 管理。`sent` 仅表示快捷键派发已返回，不表示文件移动完成；Buckle 不维护传输进度、结果清单、回滚或恢复日志。复制路径保持菜单创建时的 URL 快照，预先生成纯文本后写入系统剪贴板，写入失败显示错误而不尝试恢复旧内容。目录属性检查的失败只影响终端与移动入口，不阻止复制路径。

检查包含旧配置迁移、文件夹/空白上下文、中文及特殊字符路径、URL 边界、独立开关、直接派发与剪贴板变化、按目标区分的授权拒绝、权限查询错误和静默检查、请求取消与命令不可用。移动测试实际执行正式脚本入口、目标验证及最终派发门控，仅替换剪贴板读取、目录解析、Finder 准备、上下文读取、自定义快捷键检查、键位解析和最终按键派发等系统边界；验证错误窗口、目录、插入位置、后台 Finder、附属对话框、文本输入焦点、剪贴板变化时派发次数为零，正确上下文只派发一次。普通检查不会实际操作 Finder 或个人文件。安装版完整授权身份及扩展点击链路仍需单独验收。

依据：[Finder 菜单类型](https://developer.apple.com/documentation/findersync/fimenukind)、[Finder 目标路径](https://developer.apple.com/documentation/findersync/fifindersynccontroller/targetedurl())、[应用打开 URL](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:))、[Finder 原生快捷键](https://support.apple.com/en-us/102650)、[键盘布局与修饰键转换](https://developer.apple.com/documentation/appkit/nsevent/characters(byapplyingmodifiers:))、[用户菜单快捷键](https://developer.apple.com/documentation/appkit/nsmenuitem/userkeyequivalent)、[自动化授权查询](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet)、[剪贴板写入](https://developer.apple.com/documentation/appkit/nspasteboard/setstring(_:fortype:))、[macOS 设置窗口规范](https://developer.apple.com/design/human-interface-guidelines/settings)。

应用语言通过 `application.language` 保存选择，默认值为 `system`。手动选择时仅在当前应用偏好域写入 `AppleLanguages`，选择系统时移除该覆盖，由 Foundation 匹配系统偏好与八种已打包语言。语言变更在下次启动生效，与 Alcove 的行为一致。开发模式保留更新禁用逻辑，不显示开发模式提示。

### 本轮范围收敛与调查结论（2026-11-15）

该阶段复制路径保持现状、AirDrop 仅验证现有实现，并曾暂停原生移动实现，等待用户明确完整原生行为的要求。手动 Finder 授权等待在途检查，检查已授权则直接完成，仍未授权或检查失败则继续用户明确请求的授权。并发检查共享同一任务，状态写回后才释放任务；测试覆盖等待、已授权以及检查失败，不触发真实授权窗口。

临时工具直接使用当前 `AirDropService`，两次打开后按 Escape 取消，第三次仍可打开；前两次窗口打开期间的重复请求均被拒绝，未选择接收设备、未发送个人文件。该结果验证取消后的会话释放和重复请求处理，不代表附近完全没有设备，也不代替安装版扩展链路与正常传输验收。本轮另向用户确认的 Dylan 的 iPhone 发送临时生成的 `PHONE-04` PNG（391123 字节），系统窗口显示“已发送”，用户随后确认手机已收到且能打开。该测试未在传输中退出宿主，不验证传输期间退出的影响。

查阅 Finder Sync 协议、AX 标识属性及本机 Finder 脚本字典后，尚未找到可作为公开契约依赖的原生“将项目移到这里”菜单命令标识。本机读到的 `AXIdentifier` 为 `_NS:38`，没有找到 Apple 对该值语义与跨版本稳定性的承诺，不能硬编码。Finder 脚本字典另有公开 `move` 命令，接受源项目、目标及是否替换；它不是剪贴板原生菜单接口；随后验证了同盘撤销可用、跨卷仅复制的问题，因此没有采用。调查结论是“当前证据不足以接受菜单识别方案”，不推断所有原生触发方法都不存在。

依据：[Finder Sync 协议](https://developer.apple.com/documentation/findersync/fifindersyncprotocol)、[AX 标识](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilityidentifier())；本机 Finder 字典位于 `/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.sdef`。

### Finder 脚本跨卷与冲突界面验证（2026-11-15）

用户已接受评估 Finder 公开 `move` 命令、同名冲突停止报错且不自动替换。进一步用临时 32 MB HFS+ 磁盘映像验证从本机卷移动至另一卷：命令返回 0，源文件仍存在，目标文件也存在且内容一致。这条命令不能未经限制就作为跨卷移动实现，不通过追加删除源文件来补偿。测试卷已卸载；当前尚未把脚本移动替换进产品。

同卷临时文件测试中，Finder 的撤销菜单记录了脚本移动；实际触发该条撤销并等待文件状态变化后，源文件恢复、目标消失，内容一致。同名冲突脚本返回 -15267，源与目标各自内容均保留。以上是本机结果，不代表所有卷、文件类型和系统版本的承诺。

为核实用户要求的冲突提示外观，用专属临时文件触发了 Finder 原生“将项目移到这里”的冲突窗口。当前系统为约 404×106 pt 的紧凑窗口，含文件图标、警示标识及“保留两者／停止／替换”三按钮；它并非普通 `NSAlert` 的默认排版。随后选择“停止”，核对两边文件内容未变，关闭专属测试窗口并恢复剪贴板。另用独立临时程序展示标准 `NSAlert` 作视觉对照，未修改正式应用的提示实现。用户随后明确要求完整原生功能，因此最终直接触发 Finder 的原生移动，不仿制冲突窗口，也不在 Buckle 中实现替换或保留两者。

### 原生快捷键最终验证（2026-11-15）

按用户最终明确的完整原生功能要求，保留 Finder Sync 入口及目标窗口准备（后续已按用户要求删除移动确认），删除菜单扫描，使用当前键盘布局解析 Command–Option–V。Finder 仍会进入右键指定的目标目录；不承诺无窗口变化或 UI 自动化具有原子性。Buckle 只等待派发，不报告传输成功；进度、同名选择、跨卷实际移动与撤销全部由 Finder 处理。

临时工具执行当前生产脚本，在 Finder 实际获得焦点后选择并核对输入源，验证美国英语 QWERTY、标准 Dvorak、Dvorak–QWERTY Command 及本机微信拼音。四种实际输入源下，普通同卷移动与原生撤销均通过；在独立 HFS+ 测试卷上，四种输入源的原生移动均确认源消失、目标内容一致，撤销后源恢复、目标消失。输入源及剪贴板随后恢复、测试卷卸载。早期工具只在激活 Finder 前切换布局，可能被系统按应用恢复输入源；该结果未用作最终布局验收。系统自带拼音在临时宿主中无法选中，未把它算作测试通过，使用的是本机实际可选的微信拼音。

使用 255 字节文件名及当前生产脚本触发真实 Finder 同名冲突框：窗口宽度仍为 404 pt，高度由普通名称时的 106 pt 增至 232 pt，文件名自动换行，保留两者、停止、替换三个按钮均可见。选择停止后两边内容不变。原生对话框由当前系统布局，Buckle 不固定尺寸或截断文件名。尚未验证安装版的新授权身份、扩展完整点击链路、外置实盘、SMB、断连及空间不足；临时工具的现有宿主权限不能代替这些验收。

### 移动错误提示与权限入口

移动前不再询问是否移动。缺少辅助功能、Finder 自动化或 System Events 自动化时，提示框提供左侧「取消」、右侧「去授权」，取消不请求授权；确认后直接调用设置页的既有授权入口。辅助功能复用 PermissionFlow 的飞入动画和拖拽卡片；自动化仍先请求对应目标的系统授权，未获授权时打开系统自动化设置，不新增动画或授权框架，也不自动重试移动。

其他移动前检查或派发错误统一使用 AppKit 原生警告三角形（`NSAlert.Style.critical`）；目标文件夹或目录读取问题配系统文件夹图标，剪贴板、快捷键、功能开关、无效请求及脚本执行问题配 Buckle 应用图标，错误原因和下一步操作分为标题与说明，八种语言同步。派发状态不明和超时明确提醒用户先检查源、目标和 Finder 进度，不能宣称文件未移动。Finder 自己管理的冲突框保持原样。

移动 URL 的剪贴板版本仅用于检测内容变化，不作为授权依据。主应用在现有私有 Finder 配置目录准备 256 位随机密钥 `move-request.key`（文件权限 600），扩展仅按现有沙盒权限读取。扩展用 CryptoKit HMAC-SHA256 对规范化的目标 URL 与剪贴板版本签名，主应用验签通过后才接受免确认移动；密钥不进入 URL 或日志。未签名、错误密钥签名以及改动目标或版本的请求均拒绝。此机制隔离任意外部 URL，不能防御已经能读取同一用户私有文件的本地进程。已有菜单配置格式不变，不新增 IPC、Helper 或授权弹窗。

用户明确点击 Finder 自动化授权时，总会查询系统，不能依据历史的「已授权」缓存直接返回。若静默检查正在进行，先等其完成，再执行显式授权查询；显式请求之间共享任务，后台刷新可等待同一任务，不丢弃用户操作。

移动签名密钥属于移动功能的依赖，不是菜单配置有效性的条件。仅开启移动或刷新已开启的移动功能时准备密钥；刷新发现密钥损坏时保留有效菜单配置，在权限页单独报告移动功能错误。其他开关及关闭移动不读取密钥，关闭移动后清除此提示；不自动重建损坏密钥或忽略验签失败。

脚本在解析目标路径时单独捕获错误，以固定的 `destination-error:<错误码>` 首行和原始错误说明返回主应用，转换为带原始错误上下文的目录错误，显示警告三角形与文件夹图标。目标不存在、磁盘断开或无法访问时说明用户应检查目录和访问权限；其他脚本错误继续作为应用执行错误处理，不解析本地化错误文案来猜测类别，也不重试移动。
