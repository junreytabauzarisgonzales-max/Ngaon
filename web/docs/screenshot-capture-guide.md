# Ngaon website — authentic screenshot capture guide

This guide tells an engineer how to capture genuine customer/rider/merchant app screens for the website, without modifying Flutter application functionality and without touching production data.

## Status

- **No Flutter SDK, Dart, adb, or Android emulator/device was found in this environment**, so captures could not be performed here.
- Customer captures supplied separately are now used by the website; rider and merchant captures are still not present.
- The website keeps labeled **illustrative previews** for roles and screens without genuine captures.

## Prerequisites

1. Flutter 3.47+ / Dart 3.13+ and the Android SDK (compile SDK 37, min SDK 23, JDK 17–21).
2. An Android emulator (recommended Pixel 6, API 34+, portrait) or a physical Android device with USB debugging enabled.
3. Clone/inspect this repo: `go_apps/` is the Flutter/GetX monorepo. Do **not** modify application source code.

## Recommended test environment

- Device: Pixel 6, API 34+, 1080×2400 (≈ 411×914 dp), portrait, English, light theme, text scale 1.0.
- Clean status bar for marketing screenshots (optional but recommended):

```powershell
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged true
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e fully true
```

- Exit demo mode after capturing:

```powershell
adb shell am broadcast -a com.android.systemui.demo -e command exit
```

- Capture command (connected emulator/device):

```powershell
adb exec-out screencap -p > customer-home.png
```

or use Flutter's screenshot tooling where supported.

## Safety rules

- Run in **mock mode only**: `flutter run --dart-define=USE_MOCK_API=true` (default). No backend, no production data.
- Never use real customer, rider, or merchant personal information. Use the seeded demo flows below; fixture names such as `Aisha` and `Jamal H.` are demonstration data.
- Do not alter Flutter source, routes, controllers, repositories, or assets.
- Do not present illustrations as actual screenshots. Any website preview without an `image` field must remain labeled `ILLUSTRATIVE PREVIEW · NOT AN APP SCREENSHOT`.

## App run commands

From each app directory:

```powershell
cd go_apps/apps/customer   && flutter run --dart-define=USE_MOCK_API=true
cd go_apps/apps/rider      && flutter run --dart-define=USE_MOCK_API=true
cd go_apps/apps/merchant   && flutter run --dart-define=USE_MOCK_API=true
```

Mock mode is preconfigured in `env/mock.json`. The backend is not required and should not be run for captures unless owner approval exists.

## Demo data and login values

From `go_apps/README.md`:

| Value | Purpose |
| --- | --- |
| OTP code | always `123456` |
| New customer/rider | any number ending in `1111`, e.g. `9171231111` |
| Merchant "not registered" | any number ending in `0000` |
| Seeded merchant owner | `9193334444` (Kusina Bongao), `...4445` Pantay Grill, `...4446` Sitti Bakeshop, `...4447` Tiula Halo-Halo, `...4448` Bud Bongao Coffee |

Customer mock flow: a new job walks statuses every few seconds with a moving rider marker; Food waits ~5 s for the simulated merchant; Pabili stops at items purchased until you confirm the receipt; GCash/Maya auto-confirm after ~6 s.

Rider mock flow: go online → offer after ~5 s, cycling ride → food → pabili → padala; Food becomes ready ~12 s after accept; Pabili auto-confirms 5 s after receipt; rider approved ~8 s after document submission.

Merchant mock flow: `order.new` arrives ~8 s after opening, then every ~45 s; after accept, rider assigned ~8 s; after Mark ready, rider pickup ~6 s; unaccepted orders auto-cancel at the 3-minute deadline.

## Required website screenshots and capture flows

Use mock data. Remove personal information before supply.

| File | App | Route | Capture flow / notes |
| --- | --- | --- | --- |
| `customer-home.webp` | Customer | `/home` | Log in with a number ending `1111`, OTP `123456`. Home dashboard with Ride, Food, Pabili, Padala entry points. |
| `customer-ride.webp` | Customer | `/ride` | Ride booking: pickup/drop-off entry and fare quote screen. |
| `customer-food.webp` | Customer | `/food`, then `/food/merchant` | Merchant browsing with menus/add-ons. Do not invent merchant partnerships; use seeded demo merchants only. |
| `customer-cart.webp` | Customer | `/food/cart` | Cart and checkout preview. |
| `customer-pabili.webp` | Customer | `/pabili` | Shopping list, item budget, optional store name/pin entry. |
| `customer-padala.webp` | Customer | `/padala` | Parcel pickup/drop-off details and recipient information. |
| `customer-tracking.webp` | Customer | `/tracking` | During an active job: status updates and assigned rider location (schematic map is genuine app UI without a Google Maps key). |
| `customer-pabili-confirm.webp` | Customer | `/tracking` during Pabili | Receipt upload and customer confirmation screen before delivery continues. |
| `rider-dashboard.webp` | Rider | `/home` | Rider home with online/offline control and offer status. Complete signup/document flow first if needed; approval occurs ~8 s in mock. |
| `rider-offers.webp` | Rider | `/offer` | An available delivery offer (ride → food → pabili → padala cycle). |
| `rider-active-job.webp` | Rider | `/job` | Active delivery job steps: pickup → drop-off → proof of delivery. |
| `rider-earnings.webp` | Rider | earnings shell tab | Earnings summary and wallet information. |
| `rider-wallet.webp` | Rider | wallet shell tab | Wallet balance/top-ups. |
| `merchant-dashboard.webp` | Merchant | `/home` | Order board with incoming orders. Log in as seeded owner `9193334444`, OTP `123456`. |
| `merchant-orders.webp` | Merchant | `/order` | Order detail with preparation time and mark-ready action. |
| `merchant-menu.webp` | Merchant | menu shell tab | Menu items, add-ons, and availability controls. |
| `merchant-sales.webp` | Merchant | sales shell tab | Sales report / payouts UI (no invented figures; demo figures shown are fine if unlabeled as examples). |

Suggested naming matches `public/screenshots/<file>`. Add real dimensions and accurate alt text to `appScreens` in `web/src/content/site-content.ts`, then update the `image` field on each entry.

## Post-capture processing for the website

1. Keep original lossless captures; do not upscale.
2. Export optimized local WebP/AVIF copies at approximately 2× the rendered phone width (phone frames render near 300 px at desktop scale, so ≤ 640 px wide is usually sufficient).
3. Add entries to `appScreens` with `width`/`height` equal to the exported image's real dimensions.
4. Place exported files in `web/public/screenshots/`.
5. Run `npm run lint`, `npm run typecheck`, and `npm run build` from `web/` after adding images.
6. Verify screenshots render without stretching or recoloring; genuine screenshots retain authentic app colors and are exempt from the six-color website palette.

## What must not be done

- Do not fabricate download links, APK URLs, store links, release/beta dates, user statistics, ratings, testimonials, or delivery guarantees.
- Do not invent a production domain, contact information, or legal text.
- Do not modify `go_apps/` source code, routes, mock data, or branding.
- Do not use production customer/rider/merchant data or real phone numbers.
