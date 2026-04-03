# Best Practices Overview

This directory is designed to serve two jobs:

1. portable reference docs that can be dropped into another Rails codebase and still be useful on their own
2. Fizzy-specific notes about how the current application instantiates those patterns

Most of the strongest docs now lead with portable guidance and end with an explicit `Fizzy Notes` section.

When the docs and the code disagree, the code wins. When you are applying the patterns in another repository, prefer the docs marked `Portable reference`.

## Quick Reference

| File | Type | Best Use |
|------|------|----------|
| `authentication-spec.md` | Portable reference + Fizzy notes | Passwordless auth architecture, sessions, tokens, and tenant-aware auth flow |
| `multi-tenant-authentication.md` | Portable reference + Fizzy notes | Identity vs membership split, tenant resolution, and layered authorization |
| `domain-driven-design.md` | Portable reference | Structuring models, controllers, and business logic |
| `restful-resource-design.md` | Portable reference | Designing small resource controllers and routes |
| `hybrid-resource-controllers.md` | Portable reference + Fizzy notes | Serving HTML, Turbo Stream, and JSON from one resource controller |
| `concerns-for-organization.md` | Portable reference | Organizing large models with traits and shared modules |
| `state-modeling-with-records.md` | Portable reference | Modeling optional state with associated records |
| `callbacks-done-right.md` | Portable reference | Deciding when callbacks are the right tool |
| `event-sourcing-and-activity.md` | Portable reference | Events, notifications, activity feeds, and webhooks |
| `turbo-patterns.md` | Portable reference, some Fizzy examples | Turbo Streams, morphing, and real-time updates |
| `active-storage-authorization.md` | Portable reference + Fizzy notes | Record-owned authorization for blobs, variants, and file routes |
| `account-data-transfer.md` | Portable reference + Fizzy notes | Structured export/import with manifests and record sets |
| `platform-aware-rails.md` | Portable reference + Fizzy notes | Request metadata, timezone handling, platform detection, and client config |
| `form-components.md` | Portable reference | Inputs, comboboxes, autosave, and Stimulus form behaviors |
| `user-profiles-and-avatars.md` | Portable reference | Avatars, timezone preferences, theming, and profile boundaries |
| `view-layer-philosophy.md` | Portable reference | Partials, helpers, and the rare presenter object |
| `testing-philosophy.md` | Portable reference + Fizzy notes | Integration-heavy Rails testing, reusable data, and selective system tests |
| `advanced-rails-patterns.md` | Mixed reference, still Fizzy-heavy | Jobs, storage, search, webhooks, UUIDs, and portability helpers |
| `modern-css-architecture.md` | Portable reference | Layered custom CSS architecture for Rails applications |
| `delegated-types-pattern.md` | Portable reference, not used in Fizzy | Delegated types as a broader Rails pattern |

## Best Portable Starting Points

If you want docs that can be copied into another repository with minimal context, start here:

- `domain-driven-design.md`
- `restful-resource-design.md`
- `concerns-for-organization.md`
- `state-modeling-with-records.md`
- `callbacks-done-right.md`
- `event-sourcing-and-activity.md`
- `testing-philosophy.md`
- `authentication-spec.md`
- `multi-tenant-authentication.md`
- `hybrid-resource-controllers.md`
- `active-storage-authorization.md`
- `account-data-transfer.md`
- `platform-aware-rails.md`

## More Implementation-Oriented Docs

These are still useful, but they lean more heavily on current Fizzy choices or concrete stack details:

- `advanced-rails-patterns.md`
- `turbo-patterns.md`

## Notes

- `modern-css-architecture.md` is intentionally included. Fizzy uses layered custom CSS and does not use Tailwind in this repo.
- `delegated-types-pattern.md` is a portable reference doc, not a description of current Fizzy architecture.
- The `Portable reference + Fizzy notes` docs are intended to stand on their own first and then show how Fizzy applies the pattern.
