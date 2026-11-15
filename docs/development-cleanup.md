# Buckle 开发产物清理

只有用户明确要求时才执行清理。清理目标是可再生开发输出，不包括正常安装的应用、用户运行数据、权限或开发环境。`.gitignore` 只是提交排除规则，不是删除许可。

## 项目归属

执行时先用 `git rev-parse --show-toplevel` 确认当前工作树，不沿用其他 clone／worktree 的绝对路径。

| 对象 | 当前身份或用途 |
|---|---|
| 主 App | `Buckle.app`，`studio.slippindylan.Buckle` |
| Finder 扩展 | 主 App 内的 `BuckleFinder.appex`，`studio.slippindylan.Buckle.Finder` |
| Xcode 工程／scheme | `Buckle.xcodeproj`／`Buckle` |
| Swift Package | `BuckleCore`、`BucklePermissionSupport` 及其测试 |
| 普通本地构建 | `build/DerivedData/`、`build/SourcePackages/` |
| CI／测试包／正式包构建 | `build/DerivedData-CI/`、`build/DerivedData-Package/`、`build/DerivedData-Release/` |
| 独立检查输出 | `build/Checks/`；检查脚本仅自动删除自己本次建立的 staging |
| SwiftPM 输出 | `.build/` |
| DMG、校验和、发布说明 | `build/` 内的 DMG、`SHA256SUMS`、Markdown 和 `build/release-assets/` |

`buckle-command-*`、`buckle-dmg-*`、`buckle-feed-*`、`buckle-mount.*` 等前缀只是排查线索。只有运行记录、绝对路径、文件内容／bundle identity 能证明归属时，才将具体对象列入候选；不能按名称模糊批删。

## 范围与授权

“清理仓库内开发产物”只审计当前工作树内的可再生产物。先检查 `build/`、`.build/`、仓库内 DerivedData、App 副本、DMG、dSYM 和归档没有混入用户输入，再列明具体路径。

“清理当前项目所有开发产物”还审计外部 Xcode DerivedData、Archives、打包 staging、临时挂载和验证副本。外部 DerivedData 要核对记录的工程绝对路径；Archive 要核对归档元数据和 App／扩展身份；临时目录要核对当前项目运行记录。其他 clone／worktree、归属不明或仅名称相似的对象保留并说明。

“清理所有开发和验证残留”才进一步审计为了本次验证安装的 App／扩展。必须证明是当前项目的测试副本，不能卸载用户正常使用的 `/Applications/Buckle.app`。关闭、注销扩展或重置 TCC 属于运行环境变更，不因“清理缓存”自动获得授权。

删除前停止仍使用这些产物的本项目任务。挂载中的磁盘映像先确认来源、没有用户文件操作后正常卸载；不能为释放目录强制结束无关进程。脚本只能自动回收自己本次创建的临时 staging，不在编码或检查时顺带清除旧产物。

## 永久保护

以下内容不能按构建垃圾删除：

- 源码、Git、工程配置、共享 scheme、锁文件、`.icon` 设计源和素材、正式文档与截图。
- 用户修改、个人脚本、证书、私钥、钥匙串、provisioning、真实凭据及 1Password 条目。
- Xcode `xcuserdata`、断点、个人 scheme、编辑器状态；即使被忽略，也不默认删除。
- `~/.codex/`、`~/.agents/`、`.local/`、原始对话及 Agent 工作状态；不清除全局工具或依赖缓存。
- 正常安装的 App、用户偏好、浏览器资料、系统权限和运行诊断记录。

Buckle 的以下运行数据尤其需要保留。这里展示的是非沙盒主 App 的典型位置，不要求手工拼接目录：

| 数据 | 典型位置／机制 | 保护原因 |
|---|---|---|
| 应用语言、鼠标重置名单和等待时间 | 主 App UserDefaults，`studio.slippindylan.Buckle` 偏好域 | 用户设置，不是缓存 |
| Finder 菜单配置 | `~/Library/Application Support/Buckle/Finder/menus.json` | 四项开关与运行语言 |
| 移动请求密钥 | 同目录 `move-request.key` | 既有请求认证身份；删除会改变行为 |
| 配置恢复备份 | 同目录 `menus-backup-<UUID>.json` | 用户确认恢复前保留的原配置 |
| 内存窗口恢复记录 | `~/Library/Application Support/Buckle/MemoryPanel/pending.plist` | 原系统设置的唯一恢复记录 |
| 鼠标工具待恢复记录 | `~/Library/Application Support/Buckle/MouseReset/pending.json` | 中断操作后需要恢复的应用名单 |
| 旧浏览器资料 | `~/Library/Application Support/Buckle/BrowserProfiles/`（如存在） | 旧版用户资料，当前虽不再使用也不自动删除 |

只删除 App bundle 不会主动删除上述支持数据或系统授权，升级沿用这些状态。卸载后的数据删除、恢复记录处理、权限撤销或重建移动密钥均需用户另行明确授权；未完成恢复的记录不能因卸载或清理被丢弃。

## 执行与报告

1. 列出候选的精确路径、项目归属证据、可再生性和预计释放空间；对包含用户输入的目录缩小范围。
2. 确认候选在本次用户要求内；对无法证明归属或超过范围的对象保留，必要时单独说明。
3. 仅删除已确认对象，不清空全局 DerivedData、Archives、Homebrew／系统缓存，也不按前缀扫描后直接递归删除。
4. 报告实际删除、实际释放空间、保留项及无法判断的项目。没有清除的内容明确写出，不把“已忽略”算作“已清理”。

本文件定义清理边界，不提供泛化删除脚本。维护新 target、临时工具或输出位置时同步补充归属信息。
