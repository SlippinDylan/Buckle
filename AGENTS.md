# Buckle 工程约定

Buckle 是 macOS 15+ 原生后台菜单栏工具。产品入口见 `README.md`；开发、打包、排除项及实机验收见 `docs/development.md`。

- 修改前检查 Git 状态和目标目录指令，保留用户变更；沿用现有职责边界，不顺带重构。
- 保持一个主应用与稳定的主 bundle identity；允许已授权的内嵌 Finder Sync `.appex`，不新增独立 helper app 或开发版应用身份，除非需求明确要求。
- 用户明确不购买付费 Apple 开发者证书。Debug 与分发以无需账号的 ad-hoc 签名、空 `DEVELOPMENT_TEAM` 为目标；不将 Developer ID、公证或付费团队能力作为基础功能前提。Finder 扩展的无付费签名、注册与加载必须实测，不能以主应用可编译代替。
- 版本、构建号和打包开关只编辑 `Config/Release/manifest.json`，然后同步生成配置；不在工程中重复设置。
- 系统边界显式处理失败，UI 保持主线程隔离；内存采样在后台执行，不自动清理或终止应用。
- 不修改用户的个人脚本、不记录凭据；Webhook 只能放在 GitHub Secret。
- 界面八种语言与 glilo 一致，默认跟随系统；新增文本必须补齐全部资源。
- Swift 代码按 `.swift-format` 格式化，运行 `bash Scripts/check.sh`。完整应用构建仅在用户明确要求时执行；视觉与系统实测未经执行不得宣称通过。
- 文档用中文，代码注释用英文；未经明确要求不提交、推送、打 tag 或创建 Release。
