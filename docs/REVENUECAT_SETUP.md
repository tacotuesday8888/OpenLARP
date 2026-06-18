# RevenueCat Subscription Setup

OpenLARP has a RevenueCat-ready subscription model, but it does not include the RevenueCat SDK, live products, private API keys, or App Store product IDs yet.

## Current iOS Foundation

- `OpenLARPSubscriptionConfiguration` centralizes entitlement, offering, and product identifiers.
- `OpenLARPSubscriptionState` models:
  - active RevenueCat entitlement
  - local 14-day free sprint
  - expired access
  - offline cached entitlement
  - restore in progress
  - restore failed
- `RevenueCatCustomerInfoSnapshot` and offering/product snapshots keep the app code SDK-independent until the real adapter is added.
- `OpenLARPSubscriptionServicing` defines the service boundary for refresh and restore.
- `MockOpenLARPSubscriptionService` supports local tests and future UI wiring.
- `OpenLARPStore` now injects `OpenLARPSubscriptionServicing`, refreshes subscription state, restores purchases, records paywall exposure, and records the first local free sprint start.
- Beta exports include access status and payment event counts, but intentionally omit product IDs, customer identifiers, and billing URLs.

## Product Policy

The product roadmap calls for a first free 14-day sprint, then subscription conversion. The local model starts that free sprint when a real career goal is created or when older persisted state is migrated.

## Next RevenueCat Steps

1. Create the App Store Connect subscription group and products.
2. Create the RevenueCat project and entitlement.
3. Replace placeholder IDs in app configuration from a safe runtime source, not hardcoded private values.
4. Add the RevenueCat iOS SDK through Swift Package Manager.
5. Implement a real adapter behind `OpenLARPSubscriptionServicing`.
6. Add restore-purchases UI and paywall UI after the service adapter is verified.
7. Validate sandbox purchases before TestFlight.

Do not commit RevenueCat API keys, App Store shared secrets, `.env` files, or private product-management notes.
