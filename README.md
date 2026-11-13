<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Buckle 应用图标">
  <h1>Buckle</h1>
  <p>把常用的 Mac 小工具，收进菜单栏。</p>
</div>

Buckle 是一款原生 macOS 菜单栏工具，提供系统内存窗口、按语言启动浏览器、鼠标服务重置和菜单栏重启，并为访达增加常用右键操作。后台运行，不显示 Dock 图标。

当前版本为 **0.1.0**，尚未发布公开安装包，可从源码构建。

## 功能

<table>
  <tr>
    <td width="36%"><strong>工具集中在菜单栏</strong><br><br>系统工具、应用启动、访达右键菜单分组显示。直接打开系统内存窗口、重置鼠标或重启系统菜单栏；访达功能点击勾选开启，再点关闭。</td>
    <td width="64%" align="center"><img src="docs/images/readme/menu-bar.png" width="310" alt="Buckle 菜单栏中的系统工具、浏览器启动和访达右键功能"></td>
  </tr>
  <tr>
    <td><strong>启动与语言</strong><br><br>设置开机自启、自动检查更新，以及应用语言。默认跟随系统，也可选择英语、简体中文、繁体中文、日语、韩语、德语、法语或西班牙语；语言更改在下次启动生效。</td>
    <td align="center"><img src="docs/images/readme/general-settings.png" width="400" alt="Buckle 的语言、开机自启和自动检查更新设置"></td>
  </tr>
  <tr>
    <td><strong>权限集中管理</strong><br><br>辅助功能、自动化和访达扩展统一放在权限页。点击未授权项目进入引导，打开权限页或返回应用时自动检查；绿色文字和勾表示已授权或已启用。</td>
    <td align="center"><img src="docs/images/readme/permissions-settings.png" width="400" alt="Buckle 权限页中的授权入口、绿色授权状态和访达扩展状态"></td>
  </tr>
</table>

### 系统工具

- **系统内存窗口**：手动打开 macOS 的 LowMemoryPanel，由系统展示应用内存占用及退出操作。正常内存状态下也能打开；Buckle 不后台监测内存或自动提醒。
- **重置鼠标**：通过项目代码刷新相关服务，并重启已安装、原本正在运行的 Moom、MonitorControl、BetterMouse、iShot Pro。独立窗口显示进度与结果，需要管理员权限时使用系统授权弹窗，不读取个人脚本或保存密码。
- **重启系统菜单栏**：重启当前用户的 SystemUIServer，等待系统重新启动后报告结果；不需要 sudo。此操作不能保证修复其他 App 自己的菜单栏图标问题。

### 浏览器语言

从「应用启动 → 按语言启动浏览器」依次选择浏览器和语言。每次打开菜单时重新检测，只显示本机已安装且受支持的浏览器。支持 Chrome（含 Beta、Canary）、Chromium、Edge、Brave、Vivaldi、Opera、Safari 和 Safari Technology Preview。

浏览器由应用代码直接启动，无需配置个人脚本。Chromium 系浏览器为不同语言使用独立配置目录；Safari 需要先退出才能按指定语言重新启动。

### 访达右键菜单

在 Buckle 菜单栏的「访达右键菜单」分类下勾选需要的功能。**✓ 表示开启，无标记表示关闭**；首次使用默认关闭，已有选择会保留，下次打开访达右键菜单时生效。

| 功能 | 操作 |
|---|---|
| 隔空投送 | 右键选中的文件或文件夹，打开系统 AirDrop 分享窗口 |
| 在终端中打开 | 右键文件夹或文件夹内空白处，在对应目录打开系统终端 |
| 复制路径 | 复制所选项目的完整路径，多选时每行一条；空白处复制当前文件夹路径 |
| 将项目移到这里 | 先在访达拷贝文件，再右键目标文件夹或空白处，将文件移动到这里 |

首次使用需要在系统中启用内嵌 Finder 扩展。未安装、未注册或未启用时，菜单底部会显示状态，可从「设置 → 权限」的访达右键菜单行处理。复制路径由扩展直接完成；其他操作由扩展按需唤起 Buckle，无需提前手动启动主应用。

移动前会确认项目和目标，不覆盖同名文件，不提权搬运，也不接入访达的撤销历史。多项目移动中途失败时，请检查源、目标两处；已完成的移动不会自动撤回。

## 安装与更新

公开安装包发布后会出现在 [GitHub Releases](https://github.com/SlippinDylan/Buckle/releases)。当前请使用下方源码构建方式。

将构建出的 `Buckle.app` 放入 `/Applications`，保留一份主应用后启动。应用使用无需付费开发者账号的 ad-hoc 签名，未公证；从网络下载的构建可能需要在系统设置中允许运行，并单独启用 Finder 扩展。

已接入 Sparkle，手动检查入口位于「设置 → 关于」，自动检查开关位于「设置 → 通用」。开发与 CI 测试构建禁用更新；真实更新需先公开发布安装包和签名更新清单。

## 系统要求与使用说明

| 项目 | 要求或行为 |
|---|---|
| macOS | 15 或更新版本 |
| 架构 | Apple Silicon、Intel；CI 构建 Universal 2 |
| 应用类型 | 菜单栏后台应用，无 Dock 图标；一个主应用与一个内嵌 Finder 扩展 |
| 内存窗口权限 | 辅助功能，以及控制 System Events 的自动化权限 |
| 鼠标服务权限 | 刷新系统权限服务时需要管理员授权 |
| 界面语言 | 系统默认或手动选择八种语言；浏览器语言单独选择 |

- 系统内存窗口使用私有调试路径，已在本机 macOS 27.0.1 打开并确认，其他系统版本仍需验证。窗口自带“应用程序内存不足”提示，手动打开时出现这句话不代表当前内存真的不足。Buckle 会保存并恢复临时系统设置，恢复失败时保留记录并报告错误。
- ad-hoc 签名不能保证更新后保留系统授权；需要时请按「设置 → 权限」中的引导重新授权。
- 设置包含通用、权限、关于三页。权限页集中显示辅助功能、自动化和访达右键菜单的状态；打开权限页或返回应用时自动检查，已授权或已启用时显示绿色文字和勾选标识。
- Chromium 系浏览器的隔离配置不复用日常登录状态。Safari 需要先退出才能换语言。浏览器语言不改变系统语言、IP 或时区，也不保证网站采用指定语言。
- Finder 控制右键菜单项的排列位置。扩展注册、系统权限及不同 macOS 版本的行为需按[实机验收清单](docs/development.md#实机验收)验证，不能以编译通过代替。

## 从源码构建

需要 Xcode 26 或更新版本、Node.js 和 Python 3。Debug 使用 ad-hoc 签名和空 Team，无需登录 Apple 开发者账号。

```bash
git clone https://github.com/SlippinDylan/Buckle.git
cd Buckle
bash Scripts/check.sh
bash Scripts/build.sh Debug
open build/DerivedData/Build/Products/Debug/Buckle.app
```

也可以在 Xcode 中打开 `Buckle.xcodeproj`，选择 `Buckle` scheme 的 Debug 配置运行。命令行构建输出位于 `build/DerivedData/Build/Products/Debug/Buckle.app`。

版本、构建号和打包开关统一在 [Config/Release/manifest.json](Config/Release/manifest.json) 管理；当前打包开关为 `false`。图标源文件为 [Buckle.icon](Buckle.icon)，应用图标由 Xcode 编译，关于页读取同一应用图标。

## 开发文档

[开发与仓库约定](docs/development.md) 包含构建检查、CI 与 Discord 通知、版本与打包、Sparkle 更新发布、签名与系统权限、退出恢复及实机验收说明。安装包保存在 GitHub Releases，不进入源码仓库；签名更新清单沿用共享 homebrew-tap 的 GitHub Pages。

第三方许可随应用的 [ThirdPartyNotices.txt](App/Resources/ThirdPartyNotices.txt) 分发。
