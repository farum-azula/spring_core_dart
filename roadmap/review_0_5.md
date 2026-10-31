# The review before 0.5.0 (review done October 2026; fixes next)

After the security release (0.4.3: SSO, the Flutter security package,
DPoP), a full review like the October 2026 ones, then the minor release.
Order:

1. **0.4.3**, the security patch (released by hand: the new packages'
   first versions from the owner's machine).
2. **This review** of every package, the new ones first.
3. **0.5.0**, the minor release, once the review finds nothing left to
   fix.
4. **0.5.x**, a patch with the edge starter (Supabase Edge Functions and
   the other fetch platforms: [serverless.md](serverless.md)).

## 1. Bugs and differences from Spring

As the reviews recorded in [fix_plan.md](fix_plan.md): every package
against Spring Framework 7, Spring Boot 4, Spring Security 7, Spring
Cloud OpenFeign 5 and Jackson 3, bugs confirmed with probe programs,
differences either fixed or documented in the package's "Differences
from Spring".

- New since the last review: `spring_boot_starter_oauth2_client`
  (against `spring-security-oauth2-client` and Boot's
  `OAuth2ClientAutoConfiguration`), `oauth2Login()` and DPoP in the
  security starter, `spring_boot_starter_flutter_security` (no Spring
  counterpart: reviewed against its own docs and the RFCs it cites),
  the `web_dev_config.yaml` builder, `FetchCredentials`.
- The differential tests against Spring Security (`tool/security_reference`)
  extended where the review finds behaviour they do not cover.
- The comparison table [docs/security-spring-comparison.md](../docs/security-spring-comparison.md)
  brought up to date.

## 2. Security and vulnerabilities

- A security review of the whole diff since 0.4.2 (the SSO, DPoP, the
  app login on every platform, the secret stores, the native code in
  Swift and Kotlin, the web modes): an independent reviewer pass
  (`/security-review`), findings fixed or recorded with a reason.
- Known vulnerabilities of every dependency, the Flutter packages and the
  native ones (Gradle's `androidx.browser`, the CocoaPods / Swift Package
  Manager side): `tool/check_vulnerabilities.dart`, OSV, and Gradle's /
  Xcode's own checks.
- The threat model of [docs/security.md](../docs/security.md) and the
  ASVS checklist ([docs/security-asvs.md](../docs/security-asvs.md))
  extended to the new features (OAuth 2.0 / OpenID Connect, DPoP, token
  storage on devices, the browser modes).
- The OWASP ZAP baseline scan of the example server in CI (open in
  [security_verification.md](security_verification.md)), with the
  `sso` profile too.
- Mutation testing and coverage of the new code kept at their scores
  ([docs/security-mutation.md](../docs/security-mutation.md)).
- What only devices can show, done by hand before 0.5.0 if possible:
  Sign in with Google and Apple with real accounts, App Links /
  Universal Links with a real domain, cancelling on iOS, a StrongBox
  phone.

## Result (October 2026)

The review ran (six reviewers, scans, ZAP): the findings are in
[fix_plan.md](fix_plan.md), "Before 0.5.0" — 3 High, 18 Medium, many
Low, and the docs that state false things. All fixed on branch
`review-0.5` (see there); next: the second review, to find nothing left.

## 3. Then 0.5.0

Released when the review finds nothing left to fix (the rule of
[fix_plan.md](fix_plan.md)): the open items fixed, the deliberate
differences documented, the checks above green.
