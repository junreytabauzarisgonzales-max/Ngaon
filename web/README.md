# Ngaon public website

A static, responsive product website for Ngaon, Ngaon Rider, and Ngaon Merchant. Built directly inside the existing `web/` folder with Next.js App Router, strict TypeScript, Tailwind CSS, Motion for React, Lucide, and locally served Geist typography.

The website runs independently of the delivery backend. It has no database, authentication, booking endpoint, or runtime API dependency.

## Requirements and local development

- Node.js 20.19+ (Node.js 24 LTS recommended; ESLint requires a supported modern Node release).
- npm; use the included lockfile for repeatable installs.

From the repository's `web/` directory:

```sh
npm ci
npm run dev
```

Open <http://localhost:3000>. Do not run these commands from `go_apps/`.

## Checks and production build

```sh
npm run lint
npm run typecheck
npm run build
```

Run type checking and the production build sequentially: Next.js regenerates `.next/types` during a build.

Next.js uses `output: "export"`, `trailingSlash: true`, and `images.unoptimized: true`. Scripts explicitly use Webpack so development and production builds also work when this Windows environment falls back to WebAssembly SWC bindings. The production website is generated into **`web/out/`**. No `next start` server is required or supported for this export.

To preview the export with Python, from `web/`:

```sh
python -m http.server 3000 --bind 127.0.0.1 --directory out
```

## Static deployment

Deployment has not been performed. When approved, use any host capable of serving HTML, CSS, JavaScript, SVG, and font files over HTTPS.

| Setting | Value |
| --- | --- |
| Project/root directory | `web` |
| Install command | `npm ci` |
| Build command | `npm run build` |
| Publish/output directory | `out` (relative to `web`) |
| Runtime service/database | None |

Upload the **contents** of `out/`, including `_next/` and `brand/`. Serve `index.html` for `/` and use `404.html` for missing pages. Do not use a rewrite that replaces missing JS/CSS assets with homepage HTML. The current asset paths assume deployment at a domain root; subdirectory deployment needs an explicitly configured Next.js `basePath` and rebuilt asset paths.

Set the actual domain at build time to produce canonical metadata and a populated sitemap:

```powershell
$env:NEXT_PUBLIC_SITE_URL = "https://your-approved-domain.example"
npm run build
```

Replace that example with your real approved HTTPS origin. When unset, the site omits canonical URLs and emits an empty sitemap rather than inventing a public domain. `robots.txt` is always generated. No environment variable is required to run or build the site.

## Content and assets

- `src/content/site-content.ts`: navigation, four services, workflow, applications, FAQ, preview metadata, and optional domain.
- `src/components/`: mostly Server Components with small interactive boundaries for navigation, animation, and carousel state. Phone illustrations are rendered on the server and passed into the carousel as children.
- `src/app/globals.css`: Tailwind entry, exact approved six-color palette, responsive layout, illustrations, and reduced-motion styles.
- `public/brand/ngaon-logo-192.png`: authentic customer application launcher icon, the website's primary brand (native 192×192 pixels). Used for the header/footer mark, favicon (`favicon.ico`), `icon-32.png`, and `apple-touch-icon.png`.
- `public/brand/icon-32.png`, `public/brand/apple-touch-icon.png`: generated from the authentic launcher icon.
- `public/social/ngaon-card.png`: 1200×630 Open Graph/twitter card artwork built from the authentic logo, the exact green-and-white palette, and verified copy. Metadata uses it only when a real `NEXT_PUBLIC_SITE_URL` is supplied, to avoid emitting an invented production origin.
- Geist's package supplies local font files and its license; builds do not fetch Google Fonts.
- `docs/website-implementation-plan.md`: saved approved discovery/design plan.
- `docs/phase-3-report.md`: Phase 3 refinement findings, measurements, and limitations.
- `docs/phase-4-report.md`: Phase 4 production-readiness findings and pending items.
- `docs/screenshot-capture-guide.md`: precise mock-mode capture steps for genuine customer/rider/merchant screens.

### Genuine screenshots are still needed

No genuine screenshots were found in the source repository, and this environment has no Flutter SDK or Android emulator available, so captures were not performed here. Current phone previews are explicitly labeled **illustrative previews, not app screenshots**, both visibly and accessibly. They are diagrams of documented concepts, not fabricated captures.

To add approved screenshots:

1. Place optimized PNG/WebP/AVIF images in `public/screenshots/`.
2. Add an `image` field to the matching `appScreens` entry:

```ts
image: {
  src: "/screenshots/customer-home.webp",
  width: 1080,
  height: 2160,
  alt: "Ngaon customer home screen showing Ride, Food, Pabili, and Padala",
}
```

Use the image's real dimensions. The hero automatically uses the `customer-home` image when supplied. The showcase preserves screenshot colors/aspect ratio and labels each preview as "App screenshot" or "Illustration". Application selection controls show Customer, Rider, and Merchant so every role can be browsed in the carousel; they replace illustrations only when genuine captures exist for that role.

Requested captures: customer home/menu/checkout/tracking/Pabili confirmation, rider offers/active job/earnings, and merchant order board/menu/sales. See `docs/screenshot-capture-guide.md` for exact mock-mode steps, route names, demo data, and safe-data rules.

### Downloads, release status, and contacts

Public APK/store links, release/beta status, public contact information, and team/company history were not supplied. The site uses factual availability notices and no fake download buttons.

For each entry in `applications`, set `downloadUrl` only to a verified destination and `releaseStatus` only to owner-confirmed text. A real link then replaces the availability notice. Update the FAQ, section-level availability note, and README to match the confirmed release information. Add real contact/legal/social links when approved.

## Accessibility and interaction

- Semantic sections, one primary heading, skip link, visible focus rings, and native FAQ disclosures.
- Mobile menu supports Escape, click-away dismissal, focus return, and anchor navigation.
- Manual carousel supports previous/next, labeled selectors, arrow keys, swipe, and screen-change announcements. It never auto-rotates.
- Motion uses local client wrappers, one-time viewport reveals, and a reduced-motion preference. Content is visible in server-rendered HTML and remains readable without JavaScript.
- Authored colors are only `#052E16`, `#14532D`, `#15803D`, `#DCFCE7`, `#F0FDF4`, `#FFFFFF`, and their transparency levels. Genuine future screenshots are the authentic-color exception.

## Product sources

Content was checked against `../go_apps/README.md`, `../go_apps/API_CONTRACT.md`, `../go_apps/backend/README.md`, shared repository interfaces, and customer/rider/merchant controllers. The website does not assert production payment availability, phone masking, staffed emergency response, merchant partnerships, guaranteed times, or unsupported service areas. The Flutter apps and Go backend are not modified.

## Phase 3 refinement

The existing website has been refined in place: larger reading text, balanced tablet layouts, content-sized cards/captions, 44px navigation/carousel targets, full-width small-phone CTAs, improved menu focus lifecycle, direction-aware phone transitions, correct mobile connector animation, and repaired 404 links.

The exact 320/375/430/768/1024/1440px matrix, desktop/mobile accessibility scans, static export, swipe/keyboard behavior, and reduced-motion/no-JavaScript behavior were checked. See **[docs/phase-3-report.md](docs/phase-3-report.md)** for the findings, measurements, tests, remaining limitations, and exact genuine-screenshot capture list.

## Phase 4 production readiness

Authentic branding was integrated in place: the verified customer launcher icon is the primary brand across the header, footer, favicon, app icon, and touch icon, and a 1200×630 social-preview PNG was generated from it. The app showcase always exposes Customer, Rider, and Merchant roles with phone frames, titles, accurate descriptions, previous/next controls, and touch swipe; it shows labeled illustrations until genuine captures replace them. Metadata (title, description, Open Graph, twitter card, favicon, manifest route, and conditional structured data/canonical URLs) is ready for a real domain via `NEXT_PUBLIC_SITE_URL`. The download section remains link-free with factual availability notices until verified links and release status are supplied.

See **[docs/phase-4-report.md](docs/phase-4-report.md)** for integrated branding assets, the required capture list, showcase improvements, content verification, SEO status, verification results, and remaining production requirements.

## Phase 2 verification (baseline)

- `npm run lint`: passed without lint warnings.
- `npm run typecheck`: passed.
- `npm run build`: passed; homepage, 404, robots, sitemap, scripts, styles, branding, and local fonts exported to `out/`.
- Headless Chrome against a plain local static server: passed at 320, 375, 390, 640, 768, 1024, and 1440px with no horizontal overflow.
- Carousel buttons, screen selectors, keyboard arrows, all three app roles, and mobile touch swipe: passed.
- Mobile navigation opening, Escape/focus return, anchor selection/closing, and FAQ disclosure: passed.
- Reduced-motion emulation: smooth scrolling and the background animation disabled; controls remained functional.
- JavaScript-disabled reload: primary content, feature cards, and availability notices remained visible.
- Automated axe-core WCAG 2/2.1/2.2 A/AA scan of the mobile page: no violations reported. This is an automated check, not a claim of exhaustive accessibility certification.
- Browser runtime/console errors and failed assets: none observed. All website resource requests remained on the local static origin, with no backend/external-font requests.

The browser smoke harness and review screenshots were temporary verification tools outside the repository; no browser-testing dependency was added to the application. Performance target values in the plan have not been represented as measured Lighthouse/Core Web Vitals scores.
