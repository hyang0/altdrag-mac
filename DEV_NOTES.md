# 开发备注

记录开发过程中的分析结论与待跟进事项。新条目按日期追加。

---

## 2026-10-11 可重入性检查（待跟进）

对事件回调路径做了可重入性分析。背景：CGEventTap（`.defaultTap`）挂在主线程 run loop，回调是 C 函数指针，全部手势状态在模块级全局变量（`leftDragging` / `rightDragPending` / `rightDragging` / `dragStartMouse` / `dragStartOrigin` / `draggedWindow`）。

### 已确认安全（无需处理）

- **回调严格串行**：tap source 只加到主线程 run loop 的 `.commonModes`，事件经单一 mach port 顺序投递，不存在并发进入回调的可能——全局状态不需要锁，加锁反而是错的
- **无同线程递归**：回调内的 AX 调用是 mach_msg 同步阻塞等待，不泵 run loop，等待期间不会有事件源重入回调
- Swift 全局常量的惰性初始化是原子的

### P1 — 手势状态机共享状态无互斥（bug，优先修）

左、右两条拖动路径共用 `dragStartMouse` / `dragStartOrigin` / `draggedWindow`，且两个入口（`leftMouseDown` / `rightMouseDown`）都不检查对方是否进行中。多指点触误按、第二只鼠标均可真实触发交错：

- **场景 A**（⌥左键拖动中按下右键）：`rightMouseDown` 无条件覆写 `dragStartMouse`，下一个 `leftMouseDragged` 以错误基点计算增量 → 窗口瞬间跳变
- **场景 B**（右键拖动中 ⌥+左键按下）：`leftMouseDown` → `startDrag` 覆写 `draggedWindow`，`leftDragging` 与 `rightDragging` 同时为 true，两类 dragged 事件同时移动窗口（双重位移）；`leftMouseUp` 置 `draggedWindow = nil` 后，`rightMouseDragged` 因取不到窗口而全部放行 → 被拖 app 收到幽灵拖动事件（可能触发文本选择、拖放副作用）

**修复方向**（约 6 行，入口互斥）：

- `leftMouseDown`：若 `rightDragging || rightDragPending`，直接放行不接管
- `rightMouseDown`：若 `leftDragging`，不写 `dragStartMouse`（或直接取消右路径 pending）

### P2 — 回调内同步 AX IPC 可能拖死 tap（稳定性）

- `.defaultTap` 模式下事件被扣住直到回调返回，**回调阻塞 = 全系统鼠标事件流阻塞**
- `windowAtPoint` 对每个命中的 app 做 `1 + 2n` 次同步 IPC 往返（窗口列表 + 每窗位置/尺寸）；`moveWindow` 每次拖动事件也是同步 `AXUIElementSetAttributeValue`
- 目标 app 主线程卡死（沙滩球）时，AX 默认消息超时约 6 秒，远超 tap 回调的时间预算
- 超时后 macOS 直接禁用 tap（控制台报 event tap timeout），此后所有事件静默放行、工具**无声失效**，且当前代码无任何检测/自愈机制

**修复方向**：

- 必做（1 行）：`windowAtPoint` 内对每个 `AXUIElementCreateApplication` 结果调 `AXUIElementSetMessagingTimeout(app, 0.25)`，卡死 app 不再拖住 tap
- 可选（约 10 行）：定时器轮询 `CGEvent.tapIsEnabled`，发现被系统禁用后自动 `CGEvent.tapEnable` 重新启用

### 跟进清单

- [ ] P1 手势入口互斥
- [ ] P2 AX messaging timeout 收紧到 0.25s
- [ ] P2b（可选）tap 禁用自愈
