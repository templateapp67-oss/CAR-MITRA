# CarMitra — Smart Vehicle 360° Care

Jaipur-only doorstep vehicle-care marketplace, a Nexora company. Supabase project: CAR-MITRA (`gsahfgwhhpjwtpmhozkm`). Site: https://carmitra-jaipur.templateapp67.chatgpt.site.

## Implemented
- Supplied original logo and cover, cinematic campaign images, responsive cream/yellow public site.
- Email sign-up/login, password recovery, persistent profile, vehicle garage, Jaipur addresses with optional GPS and mandatory contact phone. Phone sign-in is visibly disabled until an SMS provider is configured.
- Multi-service booking, authoritative prices, configurable vehicle multipliers, coupons, duration checks, actual published capacity, slot locking and idempotency. Prices are locked while booking, and memberships retain their purchased price snapshot. Cash remains due until collected after service; no invented slots.
- Customer booking history/status, reschedule, cancellation charge/refund request summary, job-start code, completion signature, before/after photo access, verified reviews, 7-day warranty claims, printable booking receipts (not GST tax invoices).
- Independent partner application with private identity/photo/police documents, admin approval, agreement signing, job accept/reject, start code, before/after photos, completion, 90% earnings and payout requests. Cash earnings stay with the partner; platform dues are recorded separately to avoid double payouts.
- Zone/City/Kit channel models, pending applications, area/3 km zone lead visibility, approved-partner lead routing and nominations. Optional 2% override is future-only; no 5% referral promise remains.
- Role-protected admin: applications, assignment, nearest available partner (requires real GPS), services, slots, areas, multipliers, contacts, coupons, content, reviews, warranty, kits, memberships, manually verified settlements, operational audit.
- ₹499 / 4-basic-wash membership requests, admin activation after a verified payment reference, washes-left and redemption. Kit sales/rental quote requests. No automatic purchase or payment success is claimed.
- Public content reads from Supabase, hidden unset contacts, actual WhatsApp number supplied in the cover, real reviews only, PWA manifest and asset-only service-worker caching.

## Current launch dependencies
1. An existing confirmed customer account must be specified for admin access. No account is auto-promoted. Grant only that verified user's ID in `carmitra_user_roles` through an authorized database action.
2. Admin must publish genuinely staffed service slots, verify partners and sign/approve agreements. The database currently has no live service slots or fabricated partners.
3. Supabase email auth is enabled; email confirmation is enabled. Confirm the project Site URL / redirect allowlist points to the published site and configure email delivery. Actual email delivery/login browser QA has not been exercised.
4. Phone auth is disabled; configure an SMS provider before setting `phoneOtpEnabled=true` in `dist/backend-config.js`.
5. Razorpay TEST server implementation is prepared, but connector Edge Function deployment failed twice with an internal/unavailable error. No payment function has been confirmed live. `razorpayTestEnabled=false` and database `online_test_enabled=false` remain intentional gates. Set Razorpay test secrets and deploy/verify the function before enabling checkout. Never commit secrets or send them in chat.
6. Refunds and UPI/bank settlements are operational records pending provider/manual confirmation. No automated live refunds, banking transfers or live Razorpay collection are enabled.
7. Set the legal entity, approved agreement/policies, staffed zone centre coordinates and actual kit prices before public commercial launch. Zone boundaries are real 3 km checks when GPS is present; missing pins require manual admin assignment.

## Verification completed
- Node syntax checks for all browser/service-worker/payment sources; 17 page routes checked in public and signed-in DOM-mock variants.
- Payment tests: HMAC, capture status, amount, currency/order matching, caller ownership, auth and signed-webhook gates.
- Live Postgres transaction tests: server prices, customer isolation, admin access, capacity, idempotency, reviews eligibility, partner acceptance, job OTP, private photo ownership, signature, 90/10 cash commission, cancellation charges, reschedule, warranty, coupon limits, membership idempotency, nearest assignment, cash settlement, 3 km zone routing and payment write restrictions. Fixtures were rolled back; zero test accounts remain.
- Public REST catalogue/settings reads verified against the connected project.
- Supabase security advisor returns no findings. No browser-control capability was available, so responsive appearance, actual forms in a browser, email/SMS delivery and payment-provider end-to-end QA remain unverified.

## Source layout
`dist/`: static web application and assets. `supabase/sql/`: schema/action scripts, content and transactional verification. `supabase/functions/carmitra-payments/`: server-only test payment implementation. `scripts/test-payments.mjs`: payment security tests.

Sites hosting publishes `dist` using `.openai/hosting.json`. Source is synced to the Site repository. Public connection config contains only a publishable key; private server secrets belong in the Supabase function runtime. SQL migration history on the hosted project is authoritative; do not rerun initial schema scripts against this populated project.

## Business precedence
The newly supplied `full informetion.txt` supplies the independent marketplace model, 90/10 split, micro-franchise tiers, future optional 2% override, police verification, blue/black dress code and cancellation rules. Existing light design remains. Uploaded yellow-uniform campaign images are preserved as supplied/previously requested artwork; they are not proof of employee identity or current partner counts.

Homepage sections: six service cards, Why Choose CarMitra with the 90/10 marketplace model, service/channel partner CTAs and contact/legal footer. About expands onboarding verification and service evidence. Screenshot-supplied prices/contact are applied by `supabase/sql/screenshot_catalogue_update.sql`; booking prices remain server-calculated. Waterless and tyre-polish durations are initial 30/15-minute estimates editable by admin. Monthly partner potential is illustrative, not recorded earnings.

Home now presents hero, video stories, booking steps, trust and partner opportunities. Service packages live only on Services. Admin → Videos supports YouTube watch/Shorts links and direct MP4/WebM uploads with optional thumbnails, sort order and publishing. Marketing assets are publicly accessible; metadata for unpublished videos is admin-only. Uploads are limited to 50 MB (videos) and 5 MB (posters), subject to the Supabase project upload limit. New storage and policies: `supabase/sql/homepage_videos.sql`. No sample videos or fake testimonials are seeded.

About Us now contains the customer/service-partner/channel-partner choices, marketplace shares, six vehicle-care benefits, mandatory blue/black uniform and photo ID, and the Before we come over FAQ. Home no longer includes FAQ; footer links use `/?page=about#faq`. The About rating uses published verified service reviews; the 1,00,000+ owner target is a stated ambition and the optional 2% channel override remains a future option.

Placement correction: screenshot overview, 90/10 shares, six advantages, uniform/photo ID and the illustrated mission section are on Home. Marketing sections and footer use the original cream/white theme with yellow accents. About retains the company introduction and Before we come over FAQ.

Homepage conversion flow: hero → core service/package highlights → four booking steps → trust, verification, uniform/photo ID and warranty → videos → verified reviews → service/channel partner opportunities and mission. Primary hero content is preserved; all marketing sections retain the cream/white and yellow theme. The complete catalogue remains on Services and FAQ remains on About.

Partner page includes supplied English/Hindi terms, partner benefits, private document onboarding, equipment/transportation and required consent. `supabase/sql/bilingual_partner_consent.sql` patches the portal after the earlier live-routines snapshot: new submissions require current agreement consent and save server timestamp/version/text; approved-partner signing also stores the text. The updated dress code allows Black/Yellow/Blue. Screenshot income numbers are illustrative; dashboard is mobile friendly and the 24–48h review window is a stated target.

Partner page hero uses an original cinematic Jaipur service-partner image (`dist/assets/partner-hero-cinematic.webp`), the supplied CarMitra logo, cream/white background, yellow Apply as Partner CTA and partner dashboard link. Applying scrolls signed-in users to intake and returns guests to Partner after login. Image generated with built-in ImageGen: Indian woman professional in yellow CarMitra uniform and photo ID beside a silver car and care kit, warm Jaipur driveway, wide cinematic golden-hour scene with left-side copy space.

Channel Partner page: original cinematic workshop hero, Zone/City/Equipment Kit detail images and decorative application photo, with a functional application form. Model selection, email, Jaipur city/locality, experience, motivation and budget are saved through the protected portal RPC. Investment thresholds are indicative; final terms require admin review. The 2% override is still a future option. The form preserves guest input in memory across login.
