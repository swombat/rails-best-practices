# Rich Content and Attachments

This document is a portable Rails reference for applications that accept rich user-authored content. The main idea is to keep one canonical content model, derive plain-text projections when needed, and put safety checks around everything that touches untrusted input.

## Use One Canonical Rich Body

If the product needs:

- mentions
- formatting
- pasted links
- embedded media
- attachments mixed with text

Action Text is a strong default because it gives you one canonical body representation with Rails-native rendering.

The main discipline is to avoid storing the same content in multiple competing forms. Keep one rich body and derive projections from it.

## Derive Plain Text for Search, Notifications, and Integrations

Rich text is great for rendering. It is usually not the right shape for:

- search indexes
- push notifications
- webhook payloads
- plain-text exports

Project the content into plain text for those uses. That projection should live near the domain model so every caller gets consistent behavior.

## Treat Attachments as First-Class Model Behavior

If a record can include a file, the model should describe:

- whether the attachment exists
- what variants or previews matter
- when analysis or processing should happen

Do not scatter attachment-processing calls across controllers.

A small attachment concern is often enough.

## Build a Filter Pipeline for Presentation

Rich content usually needs presentation cleanup:

- remove duplicate unfurled URL text
- sanitize unexpected tags
- tweak embed markup

This is easier to maintain as a composed filter pipeline than as ad hoc `gsub` and DOM rewrites in helpers.

The view should ask for “presented content,” not know every cleanup rule itself.

## Be Aggressive About Untrusted URL Safety

If you unfurl links or fetch remote metadata, treat every URL as hostile.

Baseline protections:

- reject private and loopback IPs
- limit redirects
- restrict allowed content types
- cap response sizes
- sanitize extracted fields

Without these protections, link unfurling becomes an SSRF feature.

## Plan for Signed Content References to Expire

If mentions or embeds rely on signed identifiers, consider what happens when keys rotate or links age out.

Sometimes the right answer is to let old content break. Sometimes it is better to allow a narrow fallback for specific safe attachable types. Decide that explicitly.

## Campfire Notes

- `Message` uses `has_rich_text :body` as the canonical content source.
- `Message#plain_text_body` is the plain-text projection used for search, sounds, notifications, and webhook payloads.
- `Message::Attachment` owns attachment variants, analysis, and thumbnail/preview processing.
- `Message::Searchable` keeps a SQLite FTS index in sync from the plain-text projection.
- `ContentFilters::TextMessagePresentationFilters` composes Action Text presentation filters instead of mixing cleanup rules into every view.
- Link unfurling is guarded by `RestrictedHTTP::PrivateNetworkGuard`, redirect limits, response size limits, content-type checks, and sanitization in `Opengraph::Metadata`.
- Campfire extends Action Text attachables to tolerate expired signatures for a narrow set of safe attachables, specifically to preserve old `@mention` content after key rotation.
