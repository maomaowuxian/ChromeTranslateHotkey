# ChromeTranslateHotkey

macOS 上的轻量后台助手：在 Google Chrome 位于前台时，按 **Control + Option + T（⌃⌥T）**，调用 Chrome 右键菜单的 **“翻译成中文（简体）”**。

使用 Chrome 内置翻译，不跳转到 Google Translate 网页代理。程序不显示 Dock 图标，由 LaunchAgent 登录自动启动。

## 当前版本

- 版本：1.1（build 2）。
- 已验证环境：macOS Sequoia 15.8.1、Chrome 154.0.8037.93、Intel Mac。
- 本次 Release 的 ZIP 是 Intel x86_64 版本；Apple Silicon 可在本机从源码构建，功能尚未实机验证。
- 本项目使用 MIT 许可证，源码与 Release 可在 GitHub 获取。
- 仅授权辅助功能即可完成当前翻译逻辑。

## 下载与安装

从本仓库 Releases 下载 `ChromeTranslateHotkey-1.1-macos-x86_64.zip`，解压后将 App 放到：

```text
/Applications/ChromeTranslateHotkey.app
```

源码仓库内提供安装脚本。将已解压的 App 路径传入：

```bash
bash scripts/install.sh /path/to/ChromeTranslateHotkey.app
```

如文件来自网络，macOS 可能提示无法验证开发者。此 App 使用本机 ad-hoc 签名，没有 Developer ID 公证；请通过 macOS 的“隐私与安全性”确认打开。

然后在 **系统设置 → 隐私与安全性 → 辅助功能** 中添加并开启：

```text
/Applications/ChromeTranslateHotkey.app
```

**重要：** 更新 App 并重新签名后，即使旧同名开关已开启，系统仍可能拒绝新版。此时移除旧权限项，再重新添加新路径的 App。

在 Chrome 英文网页按 ⌃⌥T；地址保持原网址。

## 从源码构建

需要 Xcode 或 Command Line Tools、Python 3，以及 macOS 自带的 sips、iconutil 和 codesign。

```bash
bash scripts/build.sh
bash scripts/install.sh
```

默认按当前 Mac 架构构建，最低部署版本设为 macOS 15.0。构建产物位于 `dist/`，包括 App 和 ZIP。ZIP 不包含 `__MACOSX`、AppleDouble 文件或文件系统扩展属性。

指定架构：

```bash
BUILD_ARCH=x86_64 bash scripts/build.sh
# 在 Apple Silicon Mac 上也可以：
BUILD_ARCH=arm64 bash scripts/build.sh
```

## 文件结构

- `Sources/ChromeTranslateHotkey.swift`：当前内置翻译实现。
- `Resources/AppIcon.png`：1024×1024 图标源文件。
- `Resources/AppIcon.icns`：当前安装版的多尺寸图标。
- `Resources/Info.plist`：App 配置。
- `scripts/build.sh`：编译、生成图标、签名与打包。
- `scripts/install.sh`：备份旧版、安装并更新 LaunchAgent。
- `scripts/package.py`：打包 App，不写入 AppleDouble 文件和扩展属性。

## 实现与限制

Carbon RegisterEventHotKey 注册全局快捷键。按键时先检查前台应用是否为 `com.google.Chrome`，再通过 Accessibility 与 CoreGraphics 弹出网页右键菜单，寻找页面级简体中文翻译项并执行 AXPress，最后恢复鼠标位置。

- 菜单匹配针对中文界面，英文 Chrome 菜单未做适配。
- 内部页面、没有翻译菜单的页面可能无法处理。
- 若点击位置落在链接、图片或选中文本上，会关闭菜单并尝试其它位置。
- Chrome 更新或网页布局变化可能影响菜单调用。
- 按 ⌃⌥T 时需要 Chrome 在前台。

## 日志与诊断

日志：`~/Library/Logs/ChromeTranslateHotkey.log`。

```bash
tail -20 "$HOME/Library/Logs/ChromeTranslateHotkey.log"
launchctl print "gui/$(id -u)/com.ray.chrometranslatehotkey"
/Applications/ChromeTranslateHotkey.app/Contents/MacOS/ChromeTranslateHotkey --ax-status
```

正常翻译日志包含 `handled=1 reason=pressed:翻译成中文（简体）`。

`--ax-status` 是当前命令进程的检查。若命令由其它已授权程序启动，结果可能受其权限影响；应以 **LaunchAgent 后台进程的实际快捷键日志** 为准。

## 已验证

2026-10-05 02:12:17 后台日志成功调用 Chrome 内置翻译，用户确认“已正常”。App 安装与自动启动路径已迁移到 /Applications。

## 许可证

MIT，见 LICENSE。
