# Campfire Best Practices Overview

This directory is meant to do two jobs:

1. portable reference docs that can be copied into another Rails repository and still make sense
2. Campfire-specific notes that show how this application applies those patterns

Most of the strongest docs lead with portable guidance and end with an explicit `Campfire Notes` section.

When these docs and the code disagree, the code wins. When you import these docs into another project, prefer the docs marked `Portable reference` and treat the Campfire sections as examples, not requirements.

## Quick Reference

| File | Type | Best Use |
|------|------|----------|
| `authentication-and-current.md` | Portable reference + Campfire notes | Cookie-backed sessions, request-scoped context, signed links |
| `single-account-bootstrap.md` | Portable reference + Campfire notes | Bootstrapping a single-account app with a first-run flow |
| `resourceful-controller-design.md` | Portable reference + Campfire notes | Designing small controllers and routes around resources |
| `memberships-and-room-architecture.md` | Portable reference + Campfire notes | Modeling access, per-user state, and collaboration boundaries |
| `model-organization-with-concerns.md` | Portable reference + Campfire notes | Organizing large models with traits and small collaborators |
| `realtime-with-hotwire-and-action-cable.md` | Portable reference + Campfire notes | Turbo Streams, Action Cable, presence, and unread state |
| `rich-content-and-attachments.md` | Portable reference + Campfire notes | Action Text, attachments, search projections, and safe unfurling |
| `background-jobs-and-integrations.md` | Portable reference + Campfire notes | Thin jobs, webhooks, push notifications, and integration boundaries |
| `view-layer-and-css.md` | Portable reference + Campfire notes | ERB partials, helpers, Stimulus wiring, and custom CSS architecture |
| `testing-philosophy.md` | Portable reference + Campfire notes | Integration-heavy Rails testing with selective browser coverage |

## Best Portable Starting Points

If you only want the docs that transfer cleanly into a new Rails app, start here:

- `authentication-and-current.md`
- `resourceful-controller-design.md`
- `model-organization-with-concerns.md`
- `realtime-with-hotwire-and-action-cable.md`
- `rich-content-and-attachments.md`
- `view-layer-and-css.md`
- `testing-philosophy.md`

## More Context-Specific Docs

These are still useful, but they assume you are building a collaboration-heavy or single-account application:

- `single-account-bootstrap.md`
- `memberships-and-room-architecture.md`
- `background-jobs-and-integrations.md`

## Notes

- Campfire is intentionally single-tenant. `single-account-bootstrap.md` reflects that constraint on purpose.
- Several docs describe collaboration-app patterns because Campfire is a chat product. Those patterns still transfer well to task apps, inbox apps, CRMs, and other systems with membership, unread state, or live updates.
- Campfire stays close to Rails primitives: Active Record, Action Text, Active Storage, Turbo, Action Cable, Importmap, Stimulus, and Minitest. The docs assume that bias.
