# LogiMouse

LogiMouse is a free, open-source macOS menu bar utility that makes third-party and Logitech mice work better on the Mac: button remapping, gestures, smooth scrolling, panning, per-app rules and Logitech HID++ device control. It has no account, no license key and no subscription.

LogiMouse 是一個免費、開放原始碼的 macOS 選單列工具，讓第三方與羅技滑鼠在 Mac 上更好用：按鍵重新對應、手勢、平滑捲動、拖曳捲動、個別 App 規則，以及羅技 HID++ 裝置控制。不需要帳號、序號，也沒有任何訂閱或付費功能。

> LogiMouse is an independent implementation. It contains no code, artwork or resources from BetterMouse or Logitech Options+.
>
> LogiMouse 為獨立開發的實作，不包含 BetterMouse 或 Logitech Options+ 的任何程式碼、圖像或資源。

## 功能 Features

| 分頁 | 功能 |
| --- | --- |
| **按鍵 Buttons** | 綁定任何非左鍵的滑鼠按鍵（可搭配 fn ⌃ ⌥ ⇧ ⌘ 組合）：點擊、長按（可連發）、上下左右拖曳手勢（可連發）、按住 + 滾輪、按住 + 點擊另一鍵（和弦）。可設定全域或個別 App 專屬綁定。拖曳捲動（Pan）支援慣性、反向與速度。 |
| **滑鼠 Mouse** | 游標速度、加速度或完全關閉加速度；手勢時固定游標。羅技裝置：電量、DPI、SmartShift／段落／無段滾輪模式與靈敏度，並可把手勢鍵等按鍵「轉交」給 LogiMouse 綁定。 |
| **捲動 Scroll** | 平滑捲動（每格距離、持續時間、加速度、更加平滑）、垂直／水平滾輪各自反向（不影響觸控式軌跡板）、水平速度、修飾鍵 + 滾輪 = 水平捲動／縮放／快速捲動。 |
| **鍵盤 Keyboard** | 將按鍵或組合鍵對應到另一個快速鍵或任何動作。 |
| **例外 Exceptions** | 針對個別 App 停用全部功能、平滑捲動、全域綁定或按鍵對應，或設定專屬按鍵綁定。 |
| **設定 Settings** | 登入時啟動、隱藏選單列圖像、縮小選單列圖像間距、語言（English／繁體中文）、匯出／匯入／清除設定。 |

Available actions include clicks (single, double, triple, modifier-clicks, back/forward), Mission Control, App Exposé, Show Desktop, Launchpad, switching Spaces, back/forward, Look Up, zoom, scrolling, volume, media keys, brightness, keyboard backlight, microphone mute, app switching, input source switching, window fullscreen/zoom/minimize/close, hiding or quitting the app, lock screen, sleep, display off, log out, screenshot, custom keyboard shortcuts, opening URLs and files, launching apps and running Shortcuts.

## 系統需求 Requirements

- macOS 12 Monterey or later, Apple silicon or Intel.
- The **Accessibility** permission (System Settings → Privacy & Security → Accessibility), which the event tap needs.

## 安裝 Install

Download `LogiMouse.zip` from the latest successful run of the **Build** workflow (Actions tab), unzip it, and move `LogiMouse.app` to `/Applications`.

The CI build is ad-hoc signed, so the first time you open it, right-click the app and choose **Open**. On recent macOS versions you might instead need to allow it under System Settings → Privacy & Security.

由 GitHub Actions 的 **Build** 工作流程下載 `LogiMouse.zip`，解壓縮後把 `LogiMouse.app` 移到「應用程式」資料夾。第一次打開時請按右鍵 →「打開」，然後在「系統設定 → 隱私權與安全性 → 輔助使用」允許 LogiMouse。

## 從原始碼建置 Build from source

Building needs Xcode 16 or later (or its Command Line Tools):

```bash
./scripts/build-app.sh
```

The script writes `build/LogiMouse.app` and `build/LogiMouse.zip`. To sign with your own certificate:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" VERSION=1.0.0 ./scripts/build-app.sh
```

For a quick debug run:

```bash
swift run
```

Each ad-hoc-signed build has a new signature. If the mouse stops responding after you rebuild, remove LogiMouse from the Accessibility list and add it again.

## 運作方式 How it works

- **Event tap** (`Core/EventTap.swift`): a session-level `CGEventTap` intercepts mouse buttons, movement, wheel and key events. Every event LogiMouse posts is tagged, so the tap never processes its own output.
- **Buttons** (`Core/ButtonEngine.swift`): when a pressed button has bindings, its press is held back. The engine then decides between click, long press, drag gesture, chord, button + scroll and pan. If nothing matches, the original click is replayed.
- **Scrolling** (`Core/ScrollEngine.swift`): physical wheel ticks are turned into pixel-based continuous scroll events, animated at 120 Hz with exponential easing and speed-based acceleration. Trackpad and Magic Mouse events (already continuous) pass through untouched.
- **Cursor** (`Core/CursorController.swift`): sets `HIDPointerResolution` and the mouse acceleration property on mouse services through `IOHIDEventSystemClient`.
- **Logitech HID++ 2.0** (`HIDPP/`): talks to receivers (Unifying, Bolt, Lightspeed) and to Bluetooth and USB devices over the vendor HID collection. It uses the features `0x0005` (name), `0x1000`/`0x1004` (battery), `0x1B04` (button diversion), `0x1D4B` (reconnect), `0x2110`/`0x2111` (SmartShift) and `0x2201` (DPI). Settings are reapplied whenever a device reconnects, and diverted buttons are handed back to the firmware when LogiMouse quits.

## 限制 Known limitations

- Back/forward and Space switching are sent as keyboard shortcuts (⌘[ / ⌘], ⌃← / ⌃→). Apps or setups that changed those shortcuts will not respond.
- Zooming sends ⌘+ / ⌘−. It is not a real pinch gesture.
- The thumb wheel (HID++ `0x2150`), haptics, onboard profiles and report rate are not implemented yet.
- Logitech keyboards' non-standard keys and click-through for inactive windows are not implemented yet.

## License

MIT, see [LICENSE](LICENSE).
