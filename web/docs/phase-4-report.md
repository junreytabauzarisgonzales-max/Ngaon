# Ngaon website — Phase 4 production-readiness report

## Scope

Refined the existing Phase 3 website in place. All completed functionality, the green-and-white visual system, animations, responsive layouts, and static-export architecture are preserved. No Flutter application source was modified and no deployment was performed.

## 1. Improvements completed

- Integrated the authentic customer application launcher icon as the primary website brand across header, footer, favicon, app icon, and touch icon.
- Generated a 1200×630 social-preview artwork from the authentic logo.
- Expanded the app showcase to always expose Customer, Rider, and Merchant roles with phone frames, titles, accurate descriptions, previous/next controls, and touch swipe.
- Added accurate illustrated screens for customer Food and Padala, rider Active Job and Earnings, and merchant Menu management.
- Updated metadata: page title, description, Open Graph, Twitter card, icons, manifest route, and conditional canonical/structured data.
- Improved download-section messaging with factual availability notices and no fake download actions.
- Created a precise mock-mode screenshot capture guide covering all required customer/rider/merchant screens.
- Verified all public descriptions against `go_apps/` documentation and removed unsupported claims.

## 2. Branding assets integrated

| Asset | Path | Source | Notes |
| --- | --- | --- | --- |
| Primary brand mark | `web/public/brand/ngaon-logo-192.png` | Authentic customer launcher icon (`go_apps/apps/customer/.../mipmap-xxxhdpi/ic_launcher.png`) | Native 192×192; maximum authentic resolution available |
| Favicon | `web/public/brand/favicon.ico` | Generated from authentic launcher icon | PNG-backed ICO container |
| App icon | `web/public/brand/icon-32.png` | Generated from authentic launcher icon | 32×32 |
| Apple touch icon | `web/public/brand/apple-touch-icon.png` | Generated from authentic launcher icon | 180×180 |
| Social preview | `web/public/social/ngaon-card.png` | Generated artwork | 1200×630; exact green-and-white palette; authentic logo |

The prior palette-adapted SVG mark and social SVG were removed to prevent accidental use of non-authentic brand art. The authentic mark has transparent corners; website UI renders it at 38px in the header/footer and 28px in the showcase with no added border radius that would crop it. No vector master or higher-resolution source exists in the repository.

## 3. Genuine screenshots found

None. `go_apps/` contains only Android launcher icons; no customer/rider/merchant screenshots or public APK assets exist in the repository.

## 4. Screenshots successfully captured

None. This environment has no Flutter SDK, Dart, adb, Android SDK, emulator, or connected device available, so no genuine captures could be performed. The website keeps explicitly labeled illustrative previews until approved captures are supplied.

## 5. Screenshots still required

Required captures are documented in `web/docs/screenshot-capture-guide.md`:

Customer: home dashboard, ride booking, food browsing, cart, Pabili request, Padala request, active booking/tracking, Pabili receipt confirmation.
Rider: dashboard, available delivery offers, active delivery job, earnings, wallet.
Merchant: dashboard/order board, incoming orders, order preparation, menu management, sales/payouts.

Capture must use mock mode only (`USE_MOCK_API=true`), never production data, never real personal information, and never modify Flutter source. Files go in `web/public/screenshots/` with real dimensions and alt text, then wired into `appScreens` in `web/src/content/site-content.ts`.

## 6. App showcase improvements

- Role tabs now always render: Customer (5 screens), Rider (3 screens), Merchant (2 screens), and All (10 screens), with counts and accessible labels.
- Each slide shows phone frame, application name, screenshot title, accurate feature description, and an "App screenshot" / "Illustration" tag.
- Previous/next controls and labeled dot selectors work per role; touch swipe and keyboard arrows preserved.
- Transitions remain overlapping and direction-aware; exiting slides are hidden from the accessibility tree.
- Actual screenshots hide the decorative phone camera/home-indicator chrome so genuine captures are not double-framed; `object-fit: contain` preserves aspect ratio.
- The corner label reads "ACTUAL APP SCREEN" for genuine images and "ILLUSTRATIVE APP CONCEPT" otherwise; the disclaimer remains visible while illustrations are shown.
- No empty or broken screenshots can render because all entries have either an illustration or an image slot.

## 7. Content corrections

- Ride: "Motorcycle ride booking with pickup, drop-off, fare quotes, and tracking" (verified).
- Food: added "merchant preparation" to the workflow and showcase; browse, add-ons, merchant preparation, and rider delivery.
- Pabili: "shopping list, item budget, store name, optional store pin, receipt upload, and customer approval of the rider’s receipt total before delivery continues."
- Padala: "parcel pickup and drop-off with recipient and package details, plus proof of delivery."
- Rider: offers, active-job steps, proof of delivery, earnings/wallet; no dollar figures or job counts invented.
- Merchant: incoming orders, preparation time, ready-for-pickup, menu items/add-ons, availability; no sales figures invented.
- Availability notices remain factual: no public APK/store links, release/beta status, contacts, or domain have been confirmed.

## 8. SEO improvements

- Title: "Ngaon — Ride, Food, Pabili & Padala in Bongao, Tawi-Tawi."
- Description covers the four services and local focus.
- Open Graph and Twitter card ready with the 1200×630 social card; image metadata is emitted only when `NEXT_PUBLIC_SITE_URL` is supplied, so no production domain is invented.
- Favicon, app icon, and apple touch icon use the authentic logo.
- New static `/manifest.webmanifest` route with name, description, start URL, scope, standalone display, and authentic icons.
- Conditional JSON-LD WebSite/Organization when a real domain is configured.
- Canonical URL and `metadataBase` conditional on `NEXT_PUBLIC_SITE_URL`.
- Robots and sitemap remain static-export compatible and domain-gated.
- Heading hierarchy, alt text, skip link, visible focus rings, and `lang="en"` retained.
- No keywords, statistics, testimonials, or unverified claims were added.

## 9. Verification results

| Check | Result |
| --- | --- |
| `npm run lint` | Passed without warnings |
| `npm run typecheck` | Passed |
| `npm run build` | Passed; `/`, `/404`, `/robots.txt`, `/sitemap.xml`, `/manifest.webmanifest` prerendered |
| Static output | `web/out/` contains HTML, JS/CSS, fonts, brand PNGs/ICO, social card, robots, sitemap, manifest |
| Responsive matrix | Passed at 320/375/430/768/1024/1440px; no horizontal overflow; no clipped cards |
| Touch targets | Menu trigger, carousel arrows/dots, desktop/footer navigation ≥ 44px tested |
| Carousel | Next/previous, keyboard arrows, all 10 slides across three roles, touch swipe, dot selectors, control stability (<2px) |
| Mobile menu | Open/Escape/focus return/anchor focus/tab-out close passed |
| FAQ | Native disclosure opening passed |
| 404 | Brand → `/`, skip target `#main` exists, fragments resolve, noindex present |
| Automated accessibility | Desktop and mobile axe-core WCAG 2/2.1/2.2 A/AA: zero violations |
| Reduced motion | Smooth scroll and gradient animation disabled; controls functional |
| JavaScript disabled | Primary content, features, availability notices visible |
| Browser errors/assets | Zero console errors; zero failed asset requests; all requests local |
| Palette | Authored CSS uses only the six approved colors/RGB bases and transparency levels |

The Windows native SWC binding warning persists; the configured Webpack/WebAssembly fallback builds successfully. No application error was suppressed. No Lighthouse score or Core Web Vitals result is claimed.

## 10. Remaining production requirements

1. Supply genuine screenshots per `docs/screenshot-capture-guide.md` and wire them into `appScreens`.
2. Confirm public release/beta status and verified APK or app-store download links for Customer, Rider, and Merchant.
3. Supply the real production HTTPS domain, then set `NEXT_PUBLIC_SITE_URL` at build time to enable canonical URLs, sitemap entries, Open Graph image URLs, Twitter card images, and structured data.
4. Supply contacts, legal pages, and social links when approved; add them only to footer/navigation.
5. Before deployment: enable host-side Brotli/gzip, immutable caching for hashed `_next/static` assets, serve `404.html` for missing pages, and run throttled mobile Lighthouse/Web Vitals plus physical-device/Safari and screen-reader spot checks.
6. Deploy only after explicit approval. **No deployment was performed in Phase 4.**
