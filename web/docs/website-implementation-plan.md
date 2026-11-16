# Ngaon public website — approved Phase 1 implementation plan

Phase 1 discovery completed and approved before Phase 2 implementation. The application is created directly in the existing `web/` directory. All implementation changes are confined to this directory.

## 1. Existing project analysis

The repository contains a Flutter/GetX workspace in `go_apps/`, three Android applications (`apps/customer`, `apps/rider`, `apps/merchant`), a shared `packages/go_core` package, and a Go REST/WebSocket backend with PostgreSQL, Redis, migrations, and optional provider integrations. The shared package includes models, repository interfaces and HTTP/mock implementations, translations, networking, services, themes, and widgets. Existing Flutter and Go tests cover application flows and backend behavior.

Primary sources:

- `../go_apps/README.md` (paths relative to `web/`)
- `../go_apps/API_CONTRACT.md`
- `../go_apps/backend/README.md`
- `../go_apps/packages/go_core/lib/repositories/repositories.dart`
- `../go_apps/packages/go_core/lib/theme/go_theme.dart`
- Customer route definitions and home, checkout, tracking, Pabili, and Padala modules
- Rider signup and active-job controllers
- Merchant session service and order/menu/store modules

The main README contains a stale statement that the backend is not built, although implementation exists. Older internal names use Go; public naming is Ngaon. Mock behavior and version `1.0.0+1` do not establish a public release. Calling is implemented, but the backend does not establish genuine phone masking. SOS is stored/logged, not proof of staffed emergency response. Production payments, push delivery, and launch availability must not be inferred from client support.

## 2. Existing web folder assessment

`web/` was empty at discovery and reinspection. There were no pages, components, package manifests, JavaScript dependencies, Next.js configuration, screenshots, or website assets to overwrite. Initialize exactly one application directly here.

Approved stack: Next.js App Router, strict TypeScript, Tailwind CSS, Motion for React, Lucide React, and Geist typography. Configure `output: "export"`, static-compatible image handling, and a build producing `web/out/`. The website requires no authentication, database, delivery API, or runtime server.

## 3. Verified delivery features

| Service | Verified behavior |
| --- | --- |
| Ride | Motorcycle booking with pickup/drop-off, quote, rider assignment, and tracking |
| Food | Merchant discovery, menus/add-ons, cart, quote, merchant acceptance/preparation, and rider delivery |
| Pabili | Shopping list, item budget, optional store pin, receipt upload and customer confirmation before delivery continues |
| Padala | Parcel pickup/drop-off, recipient information, size/description, optional photo, and delivery proof |

Customer features include OTP login, saved places, fare breakdown, cash/GCash/Maya options, active/past bookings, rider location, chat/calls, trip sharing where allowed, receipt confirmation, ratings, and English/Filipino translations. Online provider availability depends on deployment configuration.

Riders submit vehicle/documents, await approval, go online, receive/accept offers, advance job steps, upload receipts/proof, and view earnings/wallet information. Registered merchants manage incoming/preparing/ready/done orders, preparation times, menus/add-ons/availability, store settings, sales, and payouts.

Avoid unsupported nationwide coverage, guaranteed delivery times, customer numbers, testimonials, merchant endorsements, 24/7 support, and release claims. Seeded merchant data is not evidence of real partnerships.

## 4. Proposed sitemap

A single homepage with anchors: `/`, `#features`, `#how-it-works`, `#showcase`, `#ecosystem`, `#about`, `#download`, and `#faq`. Desktop navigation: Features, How it works, The app, About, Get Ngaon. Mobile uses an accessible expandable menu. Footer repeats relevant navigation. Add contact/legal/social destinations only when supplied and approved.

## 5. Green-and-white design specification

Premium minimalist technology direction: large Geist typography, generous whitespace, rounded cards/buttons, thin green borders, subtle green shadows, and a clear content hierarchy. Exact website palette:

- Deep Green `#052E16`: primary text and deep surfaces
- Dark Green `#14532D`: supporting text
- Primary Green `#15803D`: CTAs, icons, active states
- Light Green `#DCFCE7`: highlights and borders
- Soft Green `#F0FDF4`: section backgrounds
- White `#FFFFFF`: surfaces

Transparency may derive from these colors. Authored UI uses no other hues. Genuine screenshots remain authentic. The existing customer icon uses a location-pin motif; a web SVG adaptation follows the exact approved palette. Rider/merchant source icons are orange/red and are not standalone website UI assets.

Content width approximately 1200px, 44–80px responsive hero typography, 32–48px section headings, 16–18px primary body copy, 20–28px card radii, and at least 44px principal interactive targets. Single-column mobile, tablet grids, desktop split hero/bento cards. Keep screen aspect ratios and prevent horizontal page overflow.

## 6. Detailed homepage layout

1. **Navigation:** Sticky white header, Ngaon brand, section links, Get Ngaon CTA, accessible mobile disclosure.
2. **Hero:** “Your everyday, delivered.” Description: “Rides, food, shopping errands, and parcel delivery—together in Ngaon, built for Bongao, Tawi-Tawi.” Explore Ngaon / See the App links, four service labels, phone preview, subtle green gradient. Use genuine customer capture if available; otherwise explicitly identify illustration.
3. **Features:** “One app. Four ways to get things moving.” Ride, Food, Pabili, Padala bento cards with icons, documented descriptions, and restrained hover/reveal motion. Supporting tracking, fare breakdown, and chat features.
4. **How it works:** “From your first tap to the final stop.” Choose service → Enter details → Review and confirm → Follow progress. Explain food preparation, Pabili receipt confirmation, and applicable proof-of-delivery differences.
5. **Showcase:** “Take a closer look.” Phone-shaped manual carousel, previous/next controls, named slide selectors, keyboard arrows, touch swipe, screen description, stable dimensions. Support customer/rider/merchant previews. Display role-selection controls when genuine screenshots for multiple roles exist. Do not rotate automatically.
6. **Ecosystem:** “Connected from order to doorstep.” Three cards explain actual customer/rider/merchant responsibilities.
7. **About:** “Built around everyday life in Bongao.” Ground copy in the documented location and four-service shared ecosystem. Do not invent company history, founding date, or team biographies.
8. **Download:** “Find your Ngaon app.” Three Android app cards. Verified download links and confirmed status only. Until supplied, clearly state that public links are not available here; render no fake download actions.
9. **FAQ:** Native accessible disclosures explaining Ngaon, services, Pabili, tracking, three app roles, and access.
10. **Footer:** Brand, section links, Bongao/Tawi-Tawi reference, verified contact links only when supplied.

## 7. Animation plan

Motion for React provides hero fade-up (450–800ms), phone entrance, one-time section reveals, 50–80ms feature stagger, workflow connector reveals, 200–350ms screenshot transitions, and a short mobile menu transition. CSS handles button/icon hover microinteractions and one finite gradient settling effect. Use transforms/opacity, viewport-once reveals, and small client boundaries. No continuous decorative animation or auto-rotating carousel.

Honor `prefers-reduced-motion` centrally and in individual motion components; suppress drift, translation, scale, connectors, and smooth scrolling. Content must be visible in server HTML and readable without JavaScript. Controls remain keyboard/screen-reader accessible.

## 8. Reusable component architecture

- Server-rendered layout, hero content, features, workflow, ecosystem, About, downloads, FAQs, and footer.
- Shared brand, buttons, section headings, icon treatments, and layout classes.
- Small client islands: Motion provider/reveals, mobile navigation, screenshot carousel.
- Typed content module for navigation, services, workflows, app roles, screenshots, FAQs, release links/status.
- Phone frame and clearly marked illustration components, replaced by local genuine images when available.

Use static metadata and export-compatible robots/sitemap handling. Supply the real domain at build time; never invent a production origin. Optimize approved image files locally; no runtime image optimizer. Self-host font files through the Geist font package.

## 9. Required files

Create beneath `web/`: package manifest and lockfile; Next/TypeScript/PostCSS/ESLint configuration; `.gitignore`; this planning document; README; App Router layout, page, CSS, not-found, robots, sitemap; reusable UI/navigation/motion/phone/showcase/section components; typed content; local brand and social assets. Framework-generated files remain managed by Next.js. No changes to `go_apps/`.

## 10. Missing documentation/assets

- Genuine screenshots (none found): customer home, menu, checkout, tracking, Pabili confirmation; rider home/active job/earnings; merchant board/menu/sales.
- Vector/high-resolution source brand files; only Android raster launcher icons were found.
- Public APK/store links and owner-confirmed public release/beta status.
- Verified contact/social URLs, production domain and static hosting target.
- Approved extended company/mission/team copy and legal documents.

Do not use mock `picsum.photos` placeholders as marketing assets. Capture demonstration screens without personal information; preserve authentic UI colors. Label any interim diagram “illustrative preview”, never “actual screenshot”.

## 11. Implementation roadmap and acceptance

1. Approve design/content and gather available publishing inputs (approval received for Phase 2).
2. Initialize the single Next.js app inside existing `web/`; configure strict TypeScript/static export.
3. Build palette/typography/responsive foundation, shared components, navigation and footer.
4. Implement all documented homepage sections with typed, verified copy.
5. Add authentic assets or labeled illustrations; implement accessible manual showcase.
6. Add restrained motion and reduced-motion handling.
7. Run lint, typecheck, and production build; fix issues.
8. Serve `out/` as static files and verify asset/anchor availability without the backend. Check mobile layouts, keyboard/menu/carousel/FAQ behavior, reduced motion, no-JS readability, console errors, and layout stability with available tooling.
9. Document local development, static deployment, asset replacement and release-link updates.

Target LCP <2.5s, CLS <0.1, INP <200ms where measurable; these are targets, not preclaimed results. Completion requires successful static export, accurate product claims, approved colors, accessible lightweight interactions, responsive layouts, and backend-independent operation. Deployment requires separate approval.
