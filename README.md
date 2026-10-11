# AltDrag for macOS

按住 **⌥ Option** 键左键拖动任意窗口，或 **右键拖动** 移动窗口——无需点中标题栏。

## 功能

| 操作 | 效果 |
|------|------|
| `⌥ + 左键拖动` | 移动窗口 |
| `右键拖动`（移动 > 5px 后触发） | 移动窗口，不干扰正常右键菜单 |

## 系统要求

- **运行**：macOS 12+（Monterey 及以后），Intel / Apple Silicon 均原生支持
- **构建**：Xcode Command Line Tools（`xcode-select --install`），Swift 5.9+ 工具链；已验证 Swift 6.3.3 无警告编译
- 源码最低可编译到 macOS 10.13 部署目标，但发布二进制统一以 macOS 12.0 为下限

## 构建

```bash
./build.sh
```

产物为 universal binary（同时包含 arm64 和 x86_64），Intel 和 Apple Silicon Mac 均可直接运行。

需要 Xcode Command Line Tools（`xcode-select --install`）。

## 许可证

[MIT](LICENSE)

## 运行

```bash
./altdrag
```

首次运行会弹出辅助功能权限请求。前往 **系统设置 > 隐私与安全性 > 辅助功能**，将 `altdrag` 加入并启用，然后重新运行。

菜单栏会出现一个 **⌥** 图标表示正在运行，点击可退出。

## 技术原理

三个核心 API：

1. **CGEventTap**（`CGEvent.tapCreate`）——系统级事件拦截，在事件到达应用前截获鼠标事件
2. **AXUIElement**（Accessibility API）——读取和设置任意应用的窗口位置（`AXPosition` 属性）
3. **CGWindowList**（`CGWindowListCopyWindowInfo`）——获取屏幕上所有窗口的层级和边界，用于命中测试

右键拖动使用阈值策略：鼠标按下时事件放行（因为 macOS 右键菜单在 mouse-up 时弹出），只有当拖动距离超过 5px 时才进入窗口拖动模式并消费后续事件。如果用户只是单击右键没有拖动，所有事件正常传递，右键菜单照常出现。

## 文件结构

```
altdrag-mac/
├── Package.swift          # SPM 清单（备用，实际用 swiftc 直接编译）
├── build.sh               # 一键构建（universal binary）
├── Sources/
│   └── AltDrag/
│       └── main.swift     # 全部源码（~200 行）
└── altdrag                # 编译产物（已 gitignore）
```
