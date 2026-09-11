# Grok zero-usage response policy

Policy version: **1**

Decision date: 2026-08-28

Scope: private Developer ID collector only; App Store provider policy is unchanged.

## Observed account-switch response

A read-only diagnostic against Grok CLI 1.0.5 after a successful account switch
confirmed all of the following without retaining or printing credentials or a
raw provider response:

- the selected OIDC credential was present, mode 600, and unexpired;
- the principal was an individual `User` with a `SuperGrok` settings tier;
- `grok agent stdio` initialized but `x.ai/billing` returned method-not-found;
- the documented CLI billing proxy returned HTTP 200;
- the response had a valid current period and reset, `isUnifiedBillingUser=true`,
  explicit zero `onDemandCap`, `onDemandUsed`, and `prepaidBalance`, no
  `creditUsagePercent`, and no `productUsage` entries.

The previous parser treated any current period without a percentage as unknown,
so Usage displayed no Grok number even though the account switch and billing
request succeeded.

Primary contract reference:
<https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-shell/src/extensions/billing.rs>

## Policy v1 mapping order

`GrokBillingProxyResponse` applies these rules in order:

1. A finite reported `creditUsagePercent` is authoritative and bounded to
   0...100 percent used.
2. A legacy positive `onDemandCap` with finite `onDemandUsed` maps to
   `used / cap * 100`, bounded to 0...100.
3. Missing percent maps to exactly 0 percent used only when every zero-state
   predicate below is true:
   - `isUnifiedBillingUser == true`;
   - `currentPeriod.start` and `.end` are valid ISO-8601 values and end is later;
   - `onDemandCap.val == 0`;
   - `onDemandUsed.val == 0`;
   - `prepaidBalance.val == 0`;
   - `productUsage` is absent or empty.
4. Any missing predicate, malformed date, non-finite number, nonzero ambiguous
   amount, or oversized response remains unavailable. The collector never
   invents 100 percent remaining for a generic missing field.

The resulting 0 percent used is projected through the existing
`ProviderUsage.grokCredits` mapping as 100 percent remaining with the provider's
real reset timestamp.

## Durable implementation and reproduction

- Parser/policy: `Sources/UsageCore/GrokBillingProxyResponse.swift`
- Collector wiring: `Sources/UsageApp/LiveUsageCollector.swift`
- Sanitized fixtures: `Tests/UsageCoreTests/GrokBillingProxyResponseTests.swift`

Run the focused regression without launching Usage:

```bash
xcodegen generate
xcodebuild \
  -project Usage.xcodeproj \
  -scheme Usage \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:UsageCoreTests/GrokBillingProxyResponseTests \
  test
```

The fixture contains only the response schema and zero-state values. It does
not contain an email, user/team identifier, token, cookie, or raw diagnostic.
