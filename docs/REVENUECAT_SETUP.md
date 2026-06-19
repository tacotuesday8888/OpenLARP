# RevenueCat Subscription Setup

OpenLARP has a RevenueCat-ready subscription model and the RevenueCat iOS SDK dependency is installed. It does not include live products, private dashboard credentials, or App Store product IDs in source control.

## Current iOS Foundation

- `OpenLARPSubscriptionConfiguration` centralizes entitlement, offering, and product identifiers.
- `OpenLARPSubscriptionState` models:
  - active RevenueCat entitlement
  - local 14-day free sprint
  - expired access
  - offline cached entitlement
  - restore in progress
  - restore failed
- `RevenueCatCustomerInfoSnapshot` and offering/product snapshots keep the app code SDK-independent outside the RevenueCat adapter.
- `OpenLARPSubscriptionServicing` defines the service boundary for identity sync, sign-out reset, offering load, configured-package purchase, refresh, and restore.
- `OpenLARPRevenueCatSubscriptionService` reads an ignored local `RevenueCat-Info.plist`, configures the SDK only when a valid public iOS SDK key is present, maps CustomerInfo into OpenLARP state, logs in RevenueCat with the stable Firebase owner UID after confirmed auth, logs out/reset on account sign-out, fetches the configured RevenueCat offering ID, purchases only packages whose product IDs match configured OpenLARP product IDs, and treats restore/purchase as successful only when the configured entitlement is active.
- `MockOpenLARPSubscriptionService` supports local tests and future UI wiring.
- `OpenLARPStore` now injects `OpenLARPSubscriptionServicing`, syncs subscriber identity after restored/interactive Firebase auth, clears RevenueCat customer info and cached offerings on sign-out/account deletion, refreshes subscription state, loads offerings, starts package purchases, restores purchases, records paywall exposure, and records the first local free sprint start.
- Beta exports include access status and payment event counts, but intentionally omit product IDs, customer identifiers, and billing URLs.

## Product Policy

The product roadmap calls for a first free 14-day sprint, then subscription conversion. The local model starts that free sprint when a real career goal is created or when older persisted state is migrated.

## Local Runtime Configuration

Create `OpenLARP/RevenueCat-Info.plist` locally when the RevenueCat dashboard, Test Store setup, or App Store products exist. The file is ignored by Git and copied into the app bundle only for local builds.

Expected keys:

- `REVENUECAT_IOS_API_KEY` (`appl_...` for iOS apps, or `test_...` for RevenueCat Test Store development)
- `REVENUECAT_ENTITLEMENT_ID`
- `REVENUECAT_OFFERING_ID`
- `REVENUECAT_MONTHLY_PRODUCT_ID`
- `REVENUECAT_STUDENT_MONTHLY_PRODUCT_ID`

Without that file, the app keeps working in local/mock mode and reports subscription connection status as not configured.

## Identity Rules

- RevenueCat `appUserID` must be the backend owner UID from `BackendUserSession.ownerUserID`, not an email address, phone number, or display name.
- RevenueCat login runs only after Firebase/Auth returns an authenticated session.
- If RevenueCat cannot be configured or login fails during identity sync, OpenLARP clears cached RevenueCat customer info instead of showing paid access that might belong to a previous account. The local free sprint record is preserved.
- Sign-out and cloud account deletion clear the in-memory offering cache and reset RevenueCat customer info. This prevents a signed-out user from seeing stale paid entitlement from the previous account on the same device.

## Next RevenueCat Steps

1. Create the App Store Connect subscription group and products.
2. Create the RevenueCat project and entitlement.
3. Replace placeholder IDs in app configuration from a safe runtime source, not hardcoded private values.
4. Add the ignored local `OpenLARP/RevenueCat-Info.plist` with the public iOS SDK key and product identifiers.
5. Replace the compact profile purchase CTA with the designer-led paywall once final UI is ready.
6. Validate purchase, cancel, restore, expiration, and sandbox/Test Store flows before TestFlight.

Do not commit RevenueCat keys, App Store shared secrets, `.env` files, or private product-management notes. The RevenueCat iOS SDK key is public by design, but OpenLARP still keeps it out of source so public repo builds stay generic and product IDs do not leak before launch.
