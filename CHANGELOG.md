# Changelog

## v0.6.0

### 新功能

- **快捷键指认**（#39）：托盘 / 菜单栏新增「快捷键」子菜单（默认关闭），提供 `Ctrl+Alt+P`、`Alt+Shift+Space`、`Ctrl+Shift+Space`（macOS 为 `⌘⌥P`、`⌥⇧Space`、`⌘⇧Space`）三个预设以及「自定义…」录制窗口，按下即可从鼠标位置开始指认。关掉晃动后也能单独使用；快捷键被其他程序占用时会在录制窗口或托盘提示中说明。
- **关闭卡片时自动归档会话**（#35、#37、#45，感谢 @ShirazuNagisa）：关闭已答完的卡片或右下角胶囊后，自动归档 Pointy 为该问题新建的 DSH 会话（可在 DSH 中恢复）；「接着」选中的已有会话、通过 ↗ 在 DSH 中打开过的会话以及出错卡片不会归档。运行中的任务在关闭胶囊后会等本轮结束再归档；归档中的会话也不会出现在新卡片的续问列表里。托盘 / 菜单栏新增「关闭卡片时归档会话」开关（默认开启）。

### 改进与修复

- **改进晃动检测**（#30）：改为沿光标移动的主方向统计折返并用相对跨度比过滤，斜向、竖向和弧线晃动都能识别，明显改善 MacBook 触控板上的触发率，同时仍会过滤单向扫动、漂移抖动和画圈。
- **macOS 应用图标**（#36）：改用 Icon Composer 图标（`AppIcon.icon`），修复 macOS 15 及以前启动台图标显示为直角方块的问题，macOS 26 及以上使用原生 asset catalog。
- **macOS 授权重开后重新托管**（#31，感谢 @Nagi-ovo）：授予「屏幕录制」权限后系统自动重开 Pointy 时，插件会自动重新接管其生命周期，退出 DSH 后不再残留，更新时也能正常替换。

---

### New

- **Keyboard shortcut to start picking** (#39): adds a "Keyboard Shortcut" submenu in the tray / menu bar (off by default) with three presets (`Ctrl+Alt+P`, `Alt+Shift+Space`, `Ctrl+Shift+Space`; `⌘⌥P`, `⌥⇧Space`, `⌘⇧Space` on macOS) and a "Custom…" recorder. Works even with shake-to-pick turned off, and warns if a shortcut is taken by another app.
- **Auto-archive sessions when a card closes** (#35, #37, #45, thanks @ShirazuNagisa): closing a finished card or pill archives the DSH session Pointy created for that question (still restorable in DSH). Existing sessions chosen via continue, sessions opened in DSH via ↗, and errored cards are kept. Closing a running pill waits for the turn to finish before archiving, and sessions being archived are excluded from a new card's session list. Toggleable via "Archive the Session When a Card Closes" in the tray / menu bar (on by default).

### Improvements & Fixes

- **Principal-axis shake detection** (#30): counts reversals along the cursor's main movement axis with a cross-span ratio filter instead of horizontal-only reversals and a fixed vertical cap, making diagonal, vertical, and arc shakes on MacBook trackpads reliable while still ignoring sweeps, drifts, and circles.
- **macOS app icon** (#36): switches to an Icon Composer icon (`AppIcon.icon`) so Pointy renders with the standard rounded shape and margin on macOS 15 and earlier, and uses the native asset catalog on macOS 26+.
- **Re-adopt reopened Pointy on macOS** (#31, thanks @Nagi-ovo): when macOS reopens Pointy after granting Screen Recording permission, the plugin re-adopts it as a managed process so it exits with DSH and is replaced on updates.

**Full Changelog**: https://github.com/pointylab/pointy/compare/v0.5.1...v0.6.0
