# Provider capacity and draft release — 2026-09-09

This check established the actual provider plans, rather than inferring paid
capacity from successful test requests. New public sales remain disabled.

## Owner clarification and revised email decision

The owner subsequently confirmed that support forwarding already reaches the
existing Tuta inbox and that the account can send mail. This is owner-reported
operational evidence; a Porkbun browser login is no longer a release requirement
just to inspect the forwarding list. Preserve the existing support mail route.

The owner added a card for Resend and questioned the $20/month upgrade. A fresh
Vercel configuration read still reports the Free plan. Keep Resend Free for
initial automatic licence and recovery emails; no paid email subscription was
activated by this work. Making an upgrade a prerequisite for the first customer
was premature. The known 100/day and 3,000/month quotas still require capacity
planning before approaching them; this decision does not assert capacity for
500,000 emails on Free.

Tuta supports the existing human support workflow. Its
[support documentation](https://tuta.com/de/support/howto) states that it does
not support third-party clients or IMAP/POP3/SMTP, so the mailbox is not a
drop-in SMTP sender for the deployed purchase Worker. Retain the already-tested
Resend API integration for automatic fulfilment. Reconsider a paid tier or
another supported transactional sender when measured volume warrants it.

The account-step page in Downloads now reflects this clarification. The
provider observations below describe the earlier billing review.

## Transactional email

Vercel's installed Resend configuration and the Resend usage dashboard both
confirm the Free plan: 100 emails per day and 3,000 per month. The resource is
`presstalk-receipts`. The installed product's billing-plan endpoint offers Pro
at $20/month with 50,000 emails/month and no daily limit. Only this email
integration uses Vercel; the purchase service runs on Cloudflare.

The official Resend SSO opened successfully. Its Upgrade in Vercel button led
to the installed integration's billing form. Pro was selected, but continuing
requires adding a payment method. Stripe Link requests owner verification to
use the saved card. No paid-plan activation or charge has been confirmed.
The payment form is open in the owner's Brave browser, and the owner was asked
to complete verification there without sending credentials in chat.

[Resend's quota documentation](https://resend.com/docs/knowledge-base/account-quotas-and-limits)
states that paid plans allow overages up to five times the monthly quota by
default. Pro therefore does not establish capacity for 500,000 receipt emails
in one month. Growing beyond the plan requires a higher tier or an agreed
provider limit. The existing durable retry queue protects outstanding delivery
jobs; it does not remove the provider's limits.

## Purchase service

Wrangler's existing scoped login works. The Workers account-settings endpoint
returns `default_usage_model: standard`; that field does not establish a paid
subscription. The account-subscriptions API denies these credentials, and the
Cloudflare MCP call also returned an authentication error. No extra OAuth
scopes were requested or granted.

The existing browser session opened the correct Cloudflare account. Billing
shows **Workers Free**, active, with no payment method on file. Its upgrade is
$5/month plus usage. [Cloudflare's published pricing](https://developers.cloudflare.com/workers/platform/pricing/)
lists 100,000 requests/day and 10 ms CPU/invocation on Free. Paid includes
10 million requests/month with usage overages and higher CPU limits; D1 also
moves from daily row limits to monthly allowances with overages. Paid capacity
has not been activated. The local 500,000-order query test is storage evidence,
not a provider-plan or concurrent-customer guarantee.

The Workers Paid checkout is open in a separate Brave window. It requires the
owner's payment method verification. The owner was asked to complete it there.
`~/Downloads/Finish PressTalk Release.html` collects the two billing links and
the Porkbun login in one local page; it contains no credentials or SSO tokens.

## Earlier support-forwarding inspection

Porkbun requires a browser login before its Current Forwards list can be
inspected. DNS API access works, but the retrieved published API specification
does not expose a forwarding-list operation. MX records alone do not prove
that `help@presstalk.app` forwards to an attended inbox. The login window is
open and the owner was asked to sign in. This inspection was superseded by the
owner's operational confirmation above; no agent-run forwarding test is claimed.

## Prepared release and website check

GitHub now holds a **draft** v0.1.23 release targeting reviewed commit
`14592ed4fbf4307c6540449f46c32f7a638adc50`. The ZIP contains the already-installed
notarized build 23.4. The extracted-archive distribution/notarization audit
passes, and GitHub's returned digests match both uploaded files:

- `PressTalk-0.1.23-macos-arm64.zip`, 4,731,044 bytes, SHA-256
  `4e810986242f962dbd7ddfeaa71163d409cd091194a2f8fa1db926dc393c490b`.
- The matching `.sha256` file, 99 bytes.

The draft's notes explicitly retain the unresolved AirPods transition issue.
It is not a public release. Native capture code was reviewed without weakening
the timestamp guard; no new live AirPods recording or causal diagnosis was
obtained in this pass.

The Pages workflow now triggers when any of its seven gate entrypoints change,
including the checkout/offer checks and their mutation checks. An entrypoint
inventory verifies every invoked gate exists and appears in the path filter;
`git diff --check` passes. No application behavior changed in this pass.

Private evidence is under `.local/commerce/`: `vercel-resend-configuration.json`,
`vercel-resend-plans.json`, `cloudflare-plan-status.json`, `provider-ui/`, and
`release-0.1.23-draft/`. SSO URLs and account credentials are not public evidence.
