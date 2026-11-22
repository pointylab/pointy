# Privacy Policy — Pointy Browser Extension

**Last updated:** November 22, 2026

Pointy Browser Extension ("the extension") is an open-source companion extension for the Pointy desktop plugin (`@pointylab/dsh`) for DeepSeek Harness (DSH). It enables you to point at specific page elements or use the right-click context menu to send selected webpage content to the Pointy desktop application running on your own computer.

## 1. Data Collection & Developer Servers

- **No developer servers:** The extension does not operate any remote servers, cloud services, analytics, telemetry, crash reporting, or advertising trackers.
- **No accounts:** The extension does not require user accounts, logins, or personal profile information.

## 2. How the Extension Communicates

- The extension connects **only** to the local Pointy desktop application over WebSocket at `ws://127.0.0.1:<port>` (default port `47321`).
- Pairing requires your explicit approval in a prompt shown by the local Pointy desktop application, which issues a locally generated pairing ID and HMAC-SHA256 secret token.

## 3. Data Accessed and When

The extension does **not** run background content scripts on page load and does **not** continuously monitor your browsing history. It reads webpage information **only on demand** when you explicitly invoke it:

1. **When you trigger a pick from Pointy (mouse shake or configured desktop shortcut):**
   - Injects the picker script into the active HTTP/HTTPS/file tab to let you highlight and click an element (or captures the currently selected text).
   - Reads the targeted element's text, links, image URLs, structured page metadata (such as repository/issue or video fields on supported sites), and the current tab's URL and page title.
   - If the picked element is visual (an image, video, canvas, or a visual block with minimal text), captures a cropped screenshot of that element from the visible tab in memory (JPEG) and sends it directly to `127.0.0.1`.
2. **When you click the right-click context menu ("Ask Pointy" / "问 Pointy"):**
   - Reads the current text selection (and immediate surrounding context in the page) along with the current tab's URL and title, and sends it to `127.0.0.1`.
3. **When you click "Open in DSH" (↗) in Pointy while using DSH Web:**
   - Queries open browser tab URLs solely to match and focus your existing local DSH web tab (`origin`), without reading tab content or recording browsing history.

## 4. Sensitive Content Protections

- The extension refuses to extract text or selections from password fields (`<input type="password">`).
- The local Pointy desktop app also blocks selections originating from windows/pages whose titles indicate login, banking, or payment pages.

## 5. Third-Party Data Sharing

- The extension transfers picked content **only** to the Pointy desktop app running on `127.0.0.1`, which forwards your prompt to your local DeepSeek Harness (DSH) instance.
- DSH then sends your prompt and attached context to whichever AI model provider you have configured in DSH, subject to that provider's own privacy policy. The extension developer never receives or sees any of this data.

## 6. Local Storage, Retention & Deletion

- The extension uses `chrome.storage.local` solely to store:
  - `id`: local pairing identifier
  - `token`: local HMAC-SHA256 shared secret
  - `port` (optional): custom local WebSocket port (defaults to `47321`)
- No picked page content or screenshots are persisted by the extension after delivery to `127.0.0.1`.
- You can clear the stored pairing credentials at any time by clicking **"取消配对"** (Unpair) in the extension popup, or remove all extension storage by uninstalling the extension.

## 7. Open Source & Contact

Source code is publicly available at [https://github.com/pointylab/pointy](https://github.com/pointylab/pointy).  
For privacy questions or issues, please open an issue at [https://github.com/pointylab/pointy/issues](https://github.com/pointylab/pointy/issues).

---

# 隐私政策 — Pointy 浏览器扩展

**更新日期：** 2026 年 11 月 22 日

Pointy 浏览器扩展是 DeepSeek Harness（DSH）插件 `@pointylab/dsh` 的开源配套扩展，用于在网页中指认具体段落、评论、图片，或通过右键菜单将选中内容交给本机运行的 Pointy 桌面端。

## 1. 数据收集与开发者服务器

- **无开发者服务器：** 本扩展不架设任何远端服务器，不包含任何数据统计、遥测、崩溃上报或广告追踪代码。
- **无需账号：** 无需注册或登录任何账号。

## 2. 通信方式

- 本扩展**仅**通过本机回环地址 `ws://127.0.0.1:<port>`（默认端口 `47321`）与你电脑上运行的 Pointy 桌面端通信。
- 初次连接需要你在 Pointy 桌面端弹窗中手动点击「允许」，双方在本地生成配对 ID 与 HMAC-SHA256 认证密钥。

## 3. 访问哪些数据、何时访问

本扩展**不在网页加载时自动注入脚本**，也**不记录你的浏览历史**。仅在你主动触发以下操作时按需读取：

1. **通过 Pointy 发起网页指认（晃动鼠标或按下设置的快捷键）：**
   - 向当前活动标签页（`http:` / `https:` / `file:`）临时注入指认脚本，或读取当前已选中的文字。
   - 确认指认后，读取目标元素的文本、链接、图片地址、站点结构化字段（如 GitHub / B 站页面的仓库、编号、作者等），以及当前标签页的网址和标题。
   - 若指认目标是图片、视频、画布等视觉元素，会在内存中裁剪该区域的可见画面截图（JPEG）随数据一并发往本机 `127.0.0.1`。
2. **使用右键菜单（「问 Pointy」）：**
   - 读取当前选中的文字（及邻近段落上下文）和当前标签页的网址与标题，发往本机 `127.0.0.1`。
3. **在 Pointy 卡片中点击「↗」切回 Web 版 DSH：**
   - 仅查询已打开标签页的 URL 前缀以定位并激活已打开的本机 DSH 标签页，不读取其他页面内容，也不保存任何标签页列表。

## 4. 敏感内容保护

- 自动拒绝读取密码输入框（`<input type="password">`）中的内容。
- 本机 Pointy 桌面端也会拦截标题为登录、密码、网银、支付页面的抓取请求。

## 5. 第三方数据流向

- 本扩展抓取的内容**仅**交给本机 `127.0.0.1` 的 Pointy 桌面端，再由本机 DSH 发送给用户在 DSH 中自行配置的模型服务商。扩展开发者不会接触、收集或存储任何用户内容。

## 6. 本地存储与删除

- 扩展仅在浏览器 `chrome.storage.local` 中保存本地配对所需的 `id`、`token` 以及可选的自定义端口 `port`，不在扩展内留存任何网页内容或截图。
- 随时可在扩展弹出面板中点击「取消配对」清除本地凭证，或直接卸载扩展清除全部本地数据。

## 7. 开源与联系方式

- 项目源代码：[https://github.com/pointylab/pointy](https://github.com/pointylab/pointy)
- 问题反馈：[https://github.com/pointylab/pointy/issues](https://github.com/pointylab/pointy/issues)
