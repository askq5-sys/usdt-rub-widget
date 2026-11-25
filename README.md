# USDT/RUB Widget (Rapira)

**English** | [Русский](README.ru.md)

A lightweight **USDT/RUB** exchange rate widget for Windows 11, powered by the [Rapira](https://rapira.net) exchange. It runs on built-in Windows PowerShell, so there is nothing to install.

- 🔄 Rate refreshes every **5 seconds** (public API `api.rapira.net/open/market/rates`)
- 🪟 Windows 11-style desktop card: rate, 24h change, bid/ask
- 📌 Pinnable taskbar button with an up/down trend badge
- 🔢 Tray icon showing the whole-ruble rate, with the full rate in its tooltip
- 🚀 Optional autostart with Windows

## Installation

1. Download `UsdtRubWidget-vX.Y.Z.zip` from the [latest release](https://github.com/askq5-sys/usdt-rub-widget/releases/latest).
2. Right-click the archive → **Properties** → tick **Unblock** → OK.
3. Extract it to a permanent folder, e.g. `C:\Tools\UsdtRubWidget`.
4. Double-click `Start-Widget.vbs`.

## Pinning to the taskbar

While the widget is running, right-click its taskbar button → **Pin to taskbar**.
Or: **Start** → "USDT RUB (Rapira)" → right-click → **Pin to taskbar**.

## Controls

| Action | How |
|---|---|
| Move the card | drag with the left mouse button |
| Refresh now | double-click the card |
| Menu (always on top, autostart, hide, close) | right-click the card or the tray icon |
| Show / hide the card | left-click the tray icon |

If the tray icon is hidden under the "^" arrow, drag it onto the taskbar.

## Settings

At the top of `UsdtRubWidget.ps1`:

```powershell
$RefreshSeconds = 5        # refresh interval
$Symbol         = 'USDT/RUB'
```

Window position and other preferences are stored in `%APPDATA%\UsdtRubWidget\config.json`.

## Requirements

Windows 10/11 with Windows PowerShell 5.1 (included with the OS).

## Disclaimer

Rates are provided by Rapira's public API and shown for information only. They are not financial advice.
