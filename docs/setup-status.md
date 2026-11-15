# Buckle 工程规范接入状态

规范版本和项目身份以 [`Config/standards.json`](../Config/standards.json) 为准。本表记录源码接入与验收边界；代码和离线检查不等于在线工作流、安装或更新已经通过。

当前发行目标为 `0.2.1`／构建 `5`，打包开关已按用户要求开启。开关开启时，main 的实际完整 CI 构建成功后自动打包、发布未发行版本并同步 Sparkle／Homebrew；文档／辅助变更和 PR 不发行，可选手动 Package 仅供测试。后续发行仍须同时递增版本与构建号。源码提交和推送不代表已替换安装版、创建 tag 或完成线上验收。

| 项 | 当前源码接入 | 仍需完成的外部或人工验收 |
|---|---|---|
| 1 通知 | push、PR／Issue、同仓审核／代码评论、CI／Package／Release／分发流程；真实阶段各一次开始／结果及实际 job 检查，禁 mentions，默认分支受信脚本 | 新工作流上线后逐项核对 Discord 开始／结束／失败／取消／跳过；fork Review 无 Secret 时明确跳过 |
| 2 DMG | `dmgbuild==1.6.7`、左右图标／工具箭头背景，manifest／identity／版本／build 校验，build 内输出、拒绝覆盖；默认测试模式关闭更新 | 真实 DMG 生成、外观及拖放安装；本轮不打开 Finder 或执行安装 |
| 3 README | 英文及七语、共用真实截图、安装和能力限制；本轮按 create-readme Skill 同步发行流程变化 | 后续发布或 Cask 上线时同步八语安装状态；译文和截图视觉检查 |
| 4 签名 | 空 Team、ad-hoc；主 App／扩展独立身份校验，已有 Sparkle 库加载检查 | 新版 Gatekeeper、正式安装、扩展加载及跨版本 TCC 行为，不能以编译替代 |
| 5 Homebrew | 分发工作流从真实已发布 DMG 生成 Buckle Cask、SHA-256 及 Tap README 条目，仅同步本 App 文件 | 自动发行后核对 Tap 的真实 Buckle Cask、同步结果并验收安装；未验证前不声称已可安装 |
| 6 Sparkle／凭据 | 锁定 2.10.0；既有独立密钥身份保留；正式构建前配对检查，包／feed 验签；统一更新开关 | 既有文档记载过备份读回与篡改测试，本轮不重读私钥；新版在线更新、失败／偏好和重启后扩展验收 |
| 7 图标 | 根 `Buckle.icon` 设计源，主 App Resources／App Icon 接通；关于页实际图标，菜单栏独立模板 | 新包实际显示及旧系统兼容外观 |
| 8 清理 | [清理规则](development-cleanup.md)记录当前 target、输出、外部归属证据和运行数据保护 | 只有用户另行要求才执行；本轮未清理 |
| 9 Git 排除 | 构建／凭据／用户 IDE／个人资料排除；CI 发行临时文件集中 build／runner 临时目录 | 新输出接入时复查；排除不授权删除、不保护已跟踪凭据 |
| 10 文档关联 | 根 AGENTS、开发指南、清理规则、本表和规范版本形成入口；保留已有业务决策及历史验证边界 | 设计或工作流变化同步维护权威来源，不另建重复说明 |
| 11 八语 | en／zh-Hans／zh-Hant／ja／ko／de／fr／es；系统优先与应用内覆盖；格式参数检查及歧义警告 | 简繁地区匹配、偏好顺序、英文回退、八语排版、VoiceOver 与译文质量 |
| 12 关于页 | 实际 icon／Bundle 版本、同一个 updater、Studio 署名；配置缺失或启动失败原因在关于页显示 | 新版窗口与错误状态的实际视觉检查；Debug 不显示开发提示例外保留 |
| 13 版本／开关／发行 | 唯一 manifest／生成 xcconfig；CI 分类，手动完整 CI，同 SHA／当前 attempt Debug build 门禁；可选手动测试 Package 与自动正式 Release 分离；发行前递增与密钥检查；同源英文 CHANGELOG | GitHub 实际执行分类、开启开关触发完整 CI、关闭开关跳过编译、历史跳过编译后手动 CI、打包及发布门禁；当前已发行版本会被递增检查拒绝 |
| 14 运行文件 | UserDefaults、系统 Application Support／临时 API／系统日志；Finder 共享目录例外；持久数据保护及卸载保留语义见清理规则 | 新版真实升级和卸载后的保留行为，不主动删除状态或撤销权限 |

## 已登记的项目例外

以下例外在 `Config/standards.json` 中有稳定标识，不能为模板一致直接改掉：

- `finder-read-only-shared-configuration`：无付费 Team、App Groups 或 provisioning 的约束下，主 App 写入真实用户 Application Support 的 Buckle/Finder 目录，沙盒扩展仅凭精确的 home-relative read-only 例外读取。`getpwuid_r` 用于取得真实 home，避免 Foundation 将路径重定向到扩展容器；已有沙盒检查验证只读且写入被拒绝。改成扩展自己的 Application Support 会读错配置。本轮保留这条已验证的共享路径，不新增 Helper／IPC，也不扩大目录权限。
- `debug-update-status-hidden`：Debug 和测试包禁用 updater，不为了禁用状态显示开发模式提示；Release 配置缺失或初始化失败仍须显示原因。
- `dependabot-push-notifications`：Dependabot push 不能读取 Actions Secret，保留分支排除；依赖变更通过 PR 和 CI 事件报告。不要为了“每次推送”恢复一个已确认会失败的通知路径。

fork Review 的 Secret 限制是通知机制的明确边界：同仓 Review 可通知，fork PR 生命周期／会话评论仍走受信默认分支路径；不能执行 fork 代码来获取 Secret。

## 验证入口

- 工程辅助、版本、文档存在性、Python／Node 离线回归和本地化：`python3 -B Scripts/check.py`。
- Swift 及应用相关完整静态／模拟检查：`bash Scripts/check.sh`，不启动 App，不执行真实文件移动或系统授权。
- 完整应用构建仅在用户明确要求时执行；GitHub 自动 CI／Release 与可选手动 CI／Package 的在线构建另按工作流执行。
- [开发指南](development.md#实机验收)中的真实权限、Finder 完整点击链路、更新及系统交互仍独立验收。本轮交付报告记录实际执行的检查，不将本表的“已接入”解释为已上线。
