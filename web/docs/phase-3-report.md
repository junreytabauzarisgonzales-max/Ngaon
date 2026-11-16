# Ngaon website — Phase 3 refinement report

## Scope

Refined the existing Phase 2 implementation in `web/` in place. All homepage sections, the three-app showcase, availability notices, FAQs, and static-export architecture are retained. No package additions, framework replacement, mobile/backend changes, or deployment were performed.

## 1. Initial issues discovered

The audit covered every page/component in `src/`, global and responsive styles, animations, navigation, assets, content, metadata routes, and static-export configuration. Headless Chrome measurements and before/after screenshots supplemented source inspection.

| Finding | Initial observation |
| --- | --- |
| Undersized reading text | At 768px, feature and workflow copy were 11px; mobile feature/workflow/FAQ copy was 12px. Screenshot disclaimers were 10px. |
| Small interaction targets | Tablet carousel selectors were 22×44px and arrow controls 40×40px. The mobile menu trigger was 42×42px. Footer links were only 15–16.5px tall. |
| Arbitrary caption whitespace | The fixed 239px caption height left roughly 93px unused on desktop and 105px on tablet for the initial preview. |
| Tablet composition | At 768px, the headline wrapped to three lines, unequal feature columns compressed copy, and four workflow columns required very small text. |
| Rigid feature cards | Fixed heights of 365–390px offered insufficient flexibility for larger copy and future text changes. |
| Small placeholder labels | Website-authored concepts were labeled, but the exterior labels were only 7–8px at several breakpoints. |
| Broken 404 anchors | The inherited skip link pointed to `#main`, which did not exist on the 404 page. The 404 brand pointed to a nonexistent `#top`. |
| Connector direction | Workflow connectors animated `scaleX` even when rendered vertically on mobile. |
| Menu lifecycle | Tabbing away left the mobile disclosure open, and exiting links could remain focusable during the exit animation. |
| Showcase transition | Sequential exit/entry delayed the next phone preview; outgoing slides had no explicit accessibility-hidden state. |
| Client boundary | The carousel imported the entire static illustration component and its icon/diagram branches into the client component graph. |
| Future hero image loading | A genuine hero image, once supplied, would have used default lazy loading despite being above the fold. |

No homepage anchor failures or horizontal overflow were found in the original baseline. The work addresses verified weaknesses rather than claiming those were previously broken.

## 2. Design improvements implemented

- Retained the exact six approved green/white colors and their transparency levels. An automated source check validated the authored CSS hex values and RGB bases.
- Raised feature copy to 14px on tablet/desktop and 15px on phones; workflow and FAQ answer text are at least 14px. About copy is 15px, and the primary hero description is 15–16px.
- Improved readable sizes for supporting features, availability information, footer links, and screenshot labels. Illustration-internal decorative type remains scaled as part of the diagram; the exterior disclaimer is readable independently.
- Adjusted heading line heights/letter spacing and the tablet hero size so the 768px headline fits two lines.
- Reduced desktop section padding from 112px to 96px and tightened the hero/section composition while retaining generous spacing.
- Changed feature cards to intrinsic, minimum-height layouts so text can grow without being clipped by a fixed card height.
- Made ecosystem cards flex columns, keeping their availability links aligned without fixed body-text heights.
- Replaced the showcase's fixed caption-height gap with a CSS grid that reserves the tallest actual caption at the current width. Invisible sizing content is inaccessible to assistive technology and is not focusable.
- Increased menu/carousel controls, slide selectors, desktop navigation links, and footer navigation links to measured touch-friendly targets of at least 44px in both tested dimensions.
- Kept borders and shadows within the original palette and disabled transform-based hover lifts on touch-only devices.

### Measured caption sizing

The former fixed reservation was 239px on tablet/desktop and 190px on phones. The refined content-derived caption slot measured:

| Width | Caption slot height |
| --- | ---: |
| 320px | 174px |
| 375px | 174px |
| 430px | 147px |
| 768px | 167px |
| 1024px | 186px |
| 1440px | 143px |

These heights reflect the current five captions, including the longest caption. They adapt to content and line wrapping rather than being a new set of fixed-height rules. Controls remained stable across all five slides in the browser check.

## 3. Animation enhancements

- Kept Motion for React and the existing lightweight `LazyMotion`/`domAnimation` setup.
- Shortened section reveals to 420ms with a maximum 120ms stagger, 12px movement, and less aggressive opacity changes.
- Reduced the hero entrance to 550ms and added a restrained 0.985→1 scale settle specifically for the mockup.
- Shortened the finite background settling animation from four seconds to 1.8 seconds.
- Replaced sequential phone exit/entry with a 240ms overlapping transition, respecting forward/backward direction. Exiting slides are hidden from the accessibility tree and pointer interaction.
- Added a short caption transition while retaining a stable live region and explicit application/slide-position announcements.
- Drove connector progress with a shared Motion value; CSS applies `scaleX` on horizontal layouts and `scaleY` on vertical layouts.
- Refined the mobile menu's 160ms transition. Exiting menu links become inert and accessibility-hidden immediately.
- Preserved native vertical touch scrolling, horizontal swipe recognition, pointer cancellation, and keyboard controls. Non-primary pointers cannot start a competing swipe.
- Reduced-motion mode sets final opacity/transform/progress states with zero duration, disables smooth scrolling and decorative CSS animation, and preserves all controls.

Server HTML remains visible before animation initialization and with JavaScript disabled. There is no continuous animation or automatic carousel rotation.

## 4. Mobile responsiveness fixes

The complete exported page was checked at the exact requested CSS viewport widths: **320, 375, 430, 768, 1024, and 1440px**.

- No document-level horizontal overflow at any requested width, measured against the document client width, including desktop scrollbar space.
- No clipped feature, ecosystem, or download card content.
- At 320px, hero CTAs stack at full width. Larger phone widths use two equal-width CTA columns.
- Tablet feature cards use two balanced columns; tablet workflow steps use a readable 2×2 arrangement. Single-column phone steps retain vertical connectors.
- Carousel selectors retain 44px targets instead of shrinking to fit. Narrow layouts use a second selector row and a swipe hint.
- Phone previews retain their established scaling, borders, and aspect ratio. No real screenshot is stretched or recolored.
- The mobile disclosure has viewport-relative maximum height, internal scrolling, and overscroll containment for short screens.
- Mobile navigation now closes when focus leaves it, as well as on Escape, click-away, anchor selection, or a desktop-width resize. Escape returns focus to the trigger; section selection focuses the destination.
- Exterior illustration labels now remain legible on small screens instead of shrinking to 7px.

## 5. Asset and screenshot status

### Inspection result

The `go_apps/` image search found only the existing Android launcher icons at multiple densities. No genuine customer/rider/merchant screenshots or public APK assets were found. Existing web illustration assets are not represented as actual app captures.

Reviewed source references include:

- Customer home/checkout/tracking/Pabili/Padala modules and the shared theme/repository interfaces.
- Rider active-job handling, receipt collection, and proof-of-delivery behavior.
- Merchant order board, including its phone tabs and tablet columns.
- `go_apps/README.md`, `go_apps/API_CONTRACT.md`, and the backend README.

The customer location-pin motif remains the reference for the existing web mark. Original orange/red rider/merchant launcher icons were not introduced into green-and-white website UI. Mobile assets were not altered.

### Required captures

Supply these five authentic captures to replace the current five showcase concepts:

| App | Capture | What should be visible | Suggested filename |
| --- | --- | --- | --- |
| Customer | Home | Ride, Food, Pabili, Padala service selection and actual navigation | `customer-home.webp` |
| Customer | Active booking | Status/timeline, assigned rider, and map/location display | `customer-tracking.webp` |
| Customer | Pabili confirmation | Uploaded receipt, actual item total, and customer confirmation action | `customer-pabili-confirmation.webp` |
| Rider | Active job | Real pickup/drop-off information and the current rider job step | `rider-active-job.webp` |
| Merchant | Order board | Real New/Preparing/Ready/Done views in the phone layout | `merchant-order-board.webp` |

Additional captures needed to show the remaining documented UI in depth: customer merchant menu/add-ons and checkout/fare breakdown; rider offer and earnings/wallet views; merchant order details, menu management, sales/payouts, and tablet order board.

Use demonstration data and remove personal information. Preserve authentic colors and aspect ratios. Keep original captures; create optimized local WebP/AVIF copies for the website (approximately 2× the rendered phone width where appropriate). Add real dimensions, accurate alt text, and captions to `appScreens` in `src/content/site-content.ts`. Role selection controls remain conditional on genuine screenshots for multiple roles.

Hero images now support eager/high-priority loading when a genuine image is supplied; below-the-fold showcase images retain lazy loading. The export continues to use local preoptimized files rather than a runtime image optimizer.

## 6. Content corrections

Verified the four services and all three applications against the documentation and source code. The existing broad descriptions were accurate; refinements clarify important details:

- **Pabili:** “budget” is now explicitly an **item budget**. The action is approval of the **receipt total**, not merely confirmation that a receipt exists.
- The Pabili FAQ now states that the store name is supplied while a map pin is optional, the initial quote covers fees, and the actual receipt total is added to the job's fare when submitted by the rider.
- **Food:** the workflow note now mentions merchant **acceptance and preparation**.
- Retained the documented proof-of-delivery distinction for Food, Pabili, and Padala.
- Added a real whitespace character across the hero heading's line break for coherent text extraction/accessibility.

No launch/beta status, statistics, reviews, partnerships, support contacts, download URLs, coverage guarantees, payment-provider readiness, or company history were invented. Availability notices continue to state that public links/status have not been supplied.

## 7. Tests executed and results

| Check | Result |
| --- | --- |
| `npm run lint` | Passed without lint warnings/errors |
| `npm run typecheck` | Passed after production type generation |
| `npm run build` | Passed with all routes prerendered/static |
| Static output | Homepage, 404, robots, sitemap, JS/CSS, fonts, and branding present under `web/out/` |
| Static HTTP browser check | Passed against a plain local file server; no Next.js runtime or delivery backend |
| Responsive matrix | Passed at 320/375/430/768/1024/1440px; no horizontal overflow or clipped cards |
| Touch-target measurements | Menu trigger, carousel arrows/selectors, desktop and footer navigation targets met the tested 44px dimensions |
| Carousel | Next/previous, direct selectors, keyboard arrows, all five previews/three roles, and touch swipe passed |
| Caption stability | Control position varied by less than 2px across all five slides |
| Mobile menu | Open/close, Escape/focus restoration, anchor focus/closing, and tab-away closing passed |
| FAQ | Native disclosure opening passed |
| Homepage links | All fragment destinations resolved |
| 404 | Brand points to `/`, skip target exists, all fragments resolve, and noindex metadata is present |
| Automated accessibility | axe-core WCAG 2/2.1/2.2 A/AA scans reported zero violations on desktop and mobile |
| Reduced motion | Smooth scrolling/background animation disabled; navigation and carousel remained functional |
| JavaScript disabled | Primary text, feature content, and availability notices remained visible |
| Browser errors/assets | No observed runtime/console errors or failed asset requests |
| Backend/external requests | All website resource requests remained on the local static origin; no backend or external-font calls |
| Palette | CSS uses only the six approved colors/RGB bases and their transparency levels |

The existing Windows native SWC binding warning persists. The already-configured Webpack/WebAssembly fallback builds successfully. One build exceeded the command execution window; a rerun with a longer timeout completed successfully. No application error was suppressed to obtain the build.

Browser automation used the installed Chrome through a temporary native DevTools harness outside the repository. axe-core was already present in development dependencies transitively; no new test/browser dependency was installed. Before/after review screenshots are temporary QA artifacts, not app screenshots.

### Performance inspection

- Static phone/diagram markup is now rendered by Server Components and passed into the client carousel as React children, rather than importing all diagram/icon branches into the carousel's client component graph.
- Existing local-font delivery, static SVG illustrations, static metadata, and backend-independent rendering were retained.
- Browser inspection of the uncompressed local export observed 8 JavaScript resources totaling **618,223 decoded bytes**, **44,914 decoded CSS bytes**, one **69,488-byte WOFF2 font**, and a **140,077-byte HTML document**. These are raw decoded resource sizes, not production compressed transfer sizes.
- No comparable Phase 2 bundle-size measurement was taken, so no percentage bundle reduction is claimed. No Lighthouse score or field Core Web Vitals result is claimed.

## 8. Remaining limitations

- Genuine screenshots and owner-approved high-resolution/vector brand masters remain unavailable.
- Verified APK/store links, public release status, contact information, legal documents, and production origin remain unsupplied.
- Canonical URLs and a populated sitemap remain conditional on a real `NEXT_PUBLIC_SITE_URL`; no public domain was invented. Static robots/sitemap export itself is verified.
- The social SVG is an artwork source, not a published raster social-preview image.
- Browser QA used Chrome viewport emulation. Physical iOS/Android devices, Safari, assistive-technology sessions, and real-network/CPU performance still need launch-stage validation.
- Automated accessibility scans are useful checks, not exhaustive accessibility certification.
- Next.js/React/Motion JavaScript remains a meaningful part of resource cost; production hosting compression and realistic performance measurement are still needed. Future screenshots must be optimized locally for static export.

## 9. Recommended next steps

1. Provide the five replacement screenshots above, then the additional UI captures as available.
2. Confirm public release status and verified app download destinations.
3. Supply the real domain, contacts, approved legal content, and brand source files.
4. Before approved deployment, enable host-side Brotli/gzip, appropriate immutable caching for hashed `_next/static` assets, and a real 404 response using `404.html`.
5. Run a throttled mobile Lighthouse/Web Vitals review with final screenshots and host compression, plus physical-device/Safari and screen-reader spot checks.
6. Deploy only after explicit approval. **No deployment was performed in Phase 3.**
