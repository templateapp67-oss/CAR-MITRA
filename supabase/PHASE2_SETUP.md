# Connected CarMitra backend

The customer and marketplace schema is now applied to the dedicated `CAR-MITRA` project: https://gsahfgwhhpjwtpmhozkm.supabase.co. The salon project is unused.

Follow current launch dependencies in the repository README. Do not rerun initial SQL setup against this populated project. Public frontend connection values are already set. Email auth is enabled; phone auth and Razorpay checkout are currently disabled pending providers and verified deployment.

Payment server secrets (Supabase function runtime only): SITE_ORIGIN=https://carmitra-jaipur.templateapp67.chatgpt.site, SUPABASE_ANON_KEY, RAZORPAY_KEY_ID (rzp_test_...), RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET. Supabase supplies server-only SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. No private key belongs in chat or browser code.

Webhook endpoint after successful function deployment: /functions/v1/carmitra-payments?webhook=1, event payment.captured, matching HMAC secret. The handler manually validates customer JWTs through Supabase Auth and signed webhook payloads. Gateway verify_jwt is intentionally false to support the signed provider webhook.

After test checkout, capture and signature verification succeed, enable both runtime online_test_enabled and frontend razorpayTestEnabled. This is TEST mode only; server rejects live Razorpay keys.
