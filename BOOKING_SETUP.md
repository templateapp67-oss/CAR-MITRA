# CarMitra guided booking

Jaipur-only booking, styled around the ten supplied screenshots in the existing light cream/white and yellow theme.

1. Select Jaipur, car/bike, make and model, or enter another make/model.
2. Choose a package and optional services. Cart selection survives email login. Server pricing is final.
3. Sign in; save registration/fuel and a private vehicle record.
4. Save address: Home/Work/Other, house/street, floor, active locality, PIN, landmark, instructions and contact phone. Optional Leaflet/OpenStreetMap pin, explicit address search and current location. Complete manual addresses remain usable when map/geolocation is unavailable.
5. Select date and a published available slot; review vehicle, address, slot and server quote, and confirm cash-after-service booking.
6. Confirmation and My Bookings use the persisted booking. Cancellation/rescheduling and operational actions remain in the existing portals.

## Packages

The screenshot packages were added as real Supabase catalogue rows, alongside existing services:

- Bucket Wash - Basic: ₹249; exterior wash and tyre polish; 30 minutes.
- Pressure Wash - Premium: ₹499; exterior pressure wash and tyre polish; 60 minutes.
- 360 Deep Cleaning: ₹999; interior vacuum, roof and seat cleaning; 120 minutes.

The durations are configured booking windows and may be adjusted in Admin → Services. Exact totals use the configured vehicle multipliers and any valid coupon. Ratings/customer counts were not copied from the other brand. An add-on already included in the chosen package is disabled.

## Required business setup

- No future active slots currently exist. Admin → Slots must publish genuine dates/windows/capacity before customer confirmation can succeed. No fake capacity was seeded.
- SMS OTP requires a configured Supabase SMS provider. Real send/verify/resend UI is wired; phone sign-in stays disabled while phoneOtpEnabled is false. Email login/signup remains usable.
- Online Razorpay requires its backend/provider configuration. Cash booking is available; online test mode stays disabled until configured.

## Validation

- UI-flow test: guest setup → make/model → packages/cart → email auth → vehicle → full address → slot → server quote → confirmation.
- Supabase transaction test: package total ₹249, new address fields in snapshot, successful cash booking, idempotent request, full-slot rejection; all test records rolled back.
- Existing public/signed-in route, profile, consent, channel and video checks pass.
- Browser visual/map/SMS/payment-provider end-to-end checks were unavailable and are not claimed.

## Current mode: only OTP is a demo

The full booking demonstration and offline preview were removed. Book Now opens the normal Supabase booking flow. Vehicle, address, quotes, slots, booking confirmation and My Bookings use the real backend. Cash is the configured payment method; no simulated Razorpay success is shown.

The Demo OTP tab uses 123456 without sending an SMS. Demo OTP does not establish a Supabase session or verify ownership of a phone number. After testing that screen, users sign in/create their own email account to save bookings. No shared demo password or user is supplied.

Hosting repair uses a supported Sites Worker ESM, with embedded production assets and explicit MIME/cache headers. Identity and the public Site URL remain the same. Source is under src/site; generated client files under build/stage; published Worker under dist/server.
