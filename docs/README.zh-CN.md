<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Buckle">
  <h1>Buckle</h1>
  <p>把常用的 Mac 小工具，收进菜单栏。</p>
  <p><a href="../README.md">English</a> · <strong>简体中文</strong> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a></p>
</div>

Buckle 是原生 macOS 菜单栏工具，提供系统工具、按语言启动浏览器，以及常用的访达右键操作。后台运行，不显示 Dock 图标。

**[下载 macOS 版本](https://github.com/SlippinDylan/Buckle/releases/latest)** · [开发指南](development.md)

> [!NOTE]
> 本文介绍当前源码中的功能。下载版本的具体变化和使用限制，请以对应版本的发布说明为准。

## 安装与首次使用

需要 **macOS 15 或更新版本**，支持 Apple Silicon 和 Intel；CI 构建目标为 Universal 2。

1. 前往 [GitHub 最新发布](https://github.com/SlippinDylan/Buckle/releases/latest)，在 **Assets** 中下载 `Buckle-<版本>.dmg`。源码压缩包供开发使用，不是安装包。
2. 更新前，先在已运行 Buckle 的菜单中选择「退出」，等待应用结束。打开 DMG，将 `Buckle.app` 拖入「应用程序」，按需替换旧版本。
3. 打开 `/Applications/Buckle.app`。Buckle 会显示在菜单栏，不显示 Dock 图标；保留一份已安装的应用。
4. 通过菜单栏使用工具或开启访达右键功能。四项访达功能首次使用时默认关闭，之后会保留选择。
5. 在「设置 → 权限」中启用访达扩展或授予所需权限。状态自动刷新；绿色文字和勾选表示已授权或已启用。

> [!IMPORTANT]
> 构建采用 ad-hoc 签名，未经公证。下载的构建可能需要在系统设置中允许运行；更新后可能需要重新授权。

## 功能一览

<table>
  <tr>
    <td width="36%"><strong>系统工具，点击即用</strong><br><br>手动打开系统内存窗口，查看鼠标重置的进度与结果，或重启系统菜单栏。访达功能可分别开启和关闭，勾选表示已开启。</td>
    <td width="64%" align="center"><img src="images/readme/menu-bar.png" width="310" alt="系统工具，点击即用"></td>
  </tr>
  <tr>
    <td width="36%"><strong>在访达里直接操作</strong><br><br>将隔空投送、在终端中打开、复制路径、将项目移到这里加入访达右键菜单。在选中的文件夹或当前目录打开终端；多条路径按行复制。</td>
    <td width="64%" align="center"><img src="images/readme/finder-context-menu.png" width="285" alt="在访达里直接操作"></td>
  </tr>
  <tr>
    <td width="36%"><strong>按八种语言启动浏览器</strong><br><br>先选本机浏览器，再选语言。每次打开菜单都会重新检测受支持的浏览器，由应用代码直接启动，无需配置个人脚本。</td>
    <td width="64%" align="center"><img src="images/readme/browser-language.png" width="580" alt="按八种语言启动浏览器"></td>
  </tr>
</table>

## 设置

在「设置 → 通用」管理开机自启和应用语言。默认跟随系统，也可选择英语、简体中文、繁体中文、日语、韩语、德语、法语或西班牙语。更改语言后需重启 Buckle。

在「设置 → 鼠标重置」中添加、移除应用，并设置重新打开应用前的等待时间：0–60 秒，默认 3 秒。修改自动保存，重置过程中暂时禁止编辑。

<p align="center">
  <img src="images/readme/general-settings.png" width="340" alt="通用设置">
  <img src="images/readme/permissions-settings.png" width="340" alt="权限状态">
</p>

截图展示英文界面，可能与已安装版本有所差异。菜单会随已安装的浏览器、已启用的功能及已拷贝的文件变化。

## 使用前须知

- **内存窗口：**手动打开 macOS LowMemoryPanel，内存正常时也可调用。窗口自带的“系统的应用程序内存不足”不是 Buckle 的诊断。该功能使用私有系统调试路径；Buckle 会检查目标内存警告窗口、恢复临时设置，无法确认窗口时报告失败。兼容性仍需逐个 macOS 版本实测。需要辅助功能与 System Events 自动化授权，不进行后台内存监测。
- **重置鼠标：**在「设置 → 鼠标重置」中管理应用名单，默认包含 Moom、MonitorControl、BetterMouse、iShot Pro。每次操作都会先退出名单中正在运行的应用，刷新 macOS 共享偏好与系统权限服务，再统一恢复这些应用。只重新打开原本正在运行的应用。刷新服务可能短暂影响其他应用，并要求管理员授权。已卸载的应用会跳过，空名单也会执行服务刷新。待恢复名单会保存；操作中断后，下次启动会询问是否重新打开这些应用，选择“稍后”会保留记录。
- **重启系统菜单栏：**重启当前用户的 SystemUIServer，无需 sudo；不保证修复其他应用自行管理的图标。
- **浏览器配置：**使用浏览器原有资料与已保存的登录状态，不创建独立配置。多个用户资料的选择遵循浏览器自身行为。切换启动语言前请先退出浏览器；浏览器已经运行时，Buckle 只显示提示。日语启动时按原脚本为浏览器进程指定东京时区；其他语言保留系统时区。不修改 macOS 设置或 IP，也不保证网站语言或地区格式。时区行为仅在 Chrome Beta 上完成实测。
- **访达操作：**复制路径由扩展直接写入纯文本，多条路径按行分隔；其他操作按需启动 Buckle。移动时先在访达拷贝文件，再右键目标文件夹或空白处。Buckle 在访达打开目标文件夹并触发原生移动，需要辅助功能权限以及控制 Finder、System Events 的自动化权限。进度、同名冲突和撤销由访达处理，操作结果以系统对话框为准；Buckle 不等待传输结束。菜单位置由访达决定。Buckle 自定义的访达菜单文字在重启 Buckle 后跟随应用语言，原生 AirDrop 名称跟随系统。 权限页分别显示访达与 System Events 的自动化授权状态。 为避免执行被重新分配的命令，存在自定义访达或全局菜单快捷键时，Buckle 会停止自动移动，请直接在访达中操作。
- **隔空投送：**打开系统分享界面，不等待传输结束。同一时间只允许一个隔空投送会话，其他访达操作仍可使用。Buckle 不会为隔空投送延迟退出，使用分享窗口时请保持 Buckle 运行。
- **更新：**已接入 Sparkle，手动检查在「设置 → 关于」，自动检查开关在「通用」。开发与 PR 检查构建禁用更新，main 的 CI 发布构建启用更新；在线更新需先发布安装包和签名更新清单。

## 从源码构建

<details>
<summary>展开源码构建与开发步骤</summary>

需要 Xcode 26 或更新版本、Node.js、Python 3。Debug 构建无需 Apple 开发者账号。

```bash
git clone https://github.com/SlippinDylan/Buckle.git
cd Buckle
bash Scripts/check.sh
bash Scripts/build.sh Debug
```

构建完成后，按用途选择以下一种方式。

### 安装日常使用的版本

先在已运行 Buckle 的菜单栏菜单中选择「退出」，等待应用结束。在访达中，将 `build/DerivedData/Build/Products/Debug/` 下的整个 `Buckle.app` 移入 `/Applications`；如需替换已有版本，也先退出再替换。打开 `/Applications/Buckle.app`，保留一份已安装的应用。

### 开发时运行构建结果

先通过「退出」关闭已有 Buckle，等待应用结束，再执行下方命令。也可以在退出已有应用后，打开 `Buckle.xcodeproj`，运行 `Buckle` scheme 的 Debug 配置。Buckle 只允许一个实例运行：已有实例未退出时，新启动的进程会退出。开发时使用正在测试的构建，不要同时打开安装目录中的副本。

```bash
open build/DerivedData/Build/Products/Debug/Buckle.app
```

</details>

## 开发文档

[开发指南](development.md)包含架构、检查、CI 打包、更新发布、签名与实机验收说明。已发布的安装包见 [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases)；[版本变更说明](../CHANGELOG.md)统一使用英文。
