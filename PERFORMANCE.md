# CarMitra loading optimization

Baseline: v19 source f7f39d00ac16485c0580074849924b7b03e8f507. Measurements are uncompressed file bytes, not Lighthouse scores or measured user loading times.

| Asset | Before | After | Reduction |
|---|---:|---:|---:|
| Initial JavaScript | 154867 B | 78525 B | 49.3% |
| hero-cinematic, 800px candidate | 223784 B | 31620 B | 85.9% |
| services-hero-cinematic, 800px candidate | 213250 B | 43690 B | 79.5% |
| partner-hero-cinematic, 800px candidate | 197794 B | 43202 B | 78.2% |
| jaipur-launch-campaign, 800px candidate | 390772 B | 82234 B | 79.0% |

## Implemented

- WebP photo candidates at 480/800/1200/1600px where applicable; smaller logo sizes, srcset/sizes, lazy below-fold loading, dimensions and async decoding. High-priority heroes remain eager.
- Minified, content-hashed JS/CSS. Portal forms/dashboards and bilingual agreement load with dynamic imports; videos load near the Home feed or on user action.
- Self-hosted Inter variable WOFF2, font-display swap; no Google Fonts stylesheet or network request. Font license in src/INTER-LICENSE.txt.
- Public requests share in-flight promises and 60-second memory caching. Home ratings and reviews use one request, rather than repeated RPC calls. FAQs and areas are fetched when needed. Videos are limited to 30 records and no longer fetch all private video URLs up front.
- Cache-first service worker for content-hashed static files only, with immutable cache headers on cached responses, old-version cleanup and registration after load. No precaching of dashboard files or third-party fonts. Auth, booking slots, payments and personal data bypass this cache.

## Hosting limitation

The Sites static host returns Cache-Control: public, max-age=0, must-revalidate at the HTTP edge. This supported static deployment does not expose custom HTTP header configuration. Content-hashed URLs and browser service-worker caching remove repeat network requests after the worker activates; the first HTTP response still has the platform header.

## Validation

Source-flow tests, compiled lazy-loader tests, request-count checks, Instagram/upload tests and asset-reference checks pass. No browser/Lighthouse runtime was available, so LCP, CLS and playback timing remain unmeasured.

Rebuild with npm run build. Regenerate image variants with python scripts/optimize-images.py before rebuilding if source images change.

Booking update: guided booking/map modules remain lazy. Static publication now uses dist/client and excludes readable source files and duplicate image copies.

Hosting update: the supported Worker ESM serves all assets with explicit content types, ETag/304 and long immutable caching for content-hashed files. HTML and the service worker revalidate. This replaces static-host HTTP header limitations. Source remains online with Supabase; only the OTP UI is a demo.
