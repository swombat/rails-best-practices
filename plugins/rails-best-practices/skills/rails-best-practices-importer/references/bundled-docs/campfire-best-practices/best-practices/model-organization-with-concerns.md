# Model Organization with Concerns

This document is a portable Rails reference. The core pattern is to keep models cohesive by extracting trait-based concerns and a few small collaborators, not by dumping every behavior into one file or one generic service layer.

## Use Concerns for Real Traits

A good concern groups one recognizable responsibility:

- avatar behavior
- bot authentication
- attachment handling
- search indexing
- transfer links

It should answer a clear question: “Why do these methods belong together?”

Bad concerns are “helpers for this model.” Good concerns are named behaviors.

## Keep Concerns Close to the Model Namespace

If `User` has multiple concerns, place them under `app/models/user/`:

- `app/models/user/avatar.rb`
- `app/models/user/bot.rb`
- `app/models/user/transferable.rb`

Do the same for other large models. This keeps the organization discoverable and makes the trait boundary visible in the filesystem.

## Let Concerns Own the Callback When the Callback Belongs to the Trait

If a callback exists solely because of a specific trait, it can live in that concern.

That keeps the callback near the methods it depends on and reduces the “what is causing this side effect?” problem in the main model file.

Examples:

- a searchable concern can own index maintenance callbacks
- an attachment concern can own preprocessing hooks
- a role concern can own role enums

The callback should still stay small and understandable.

## Use Small Collaborators for Multi-Step Operations

Not every extraction should be a concern. When behavior is:

- multi-step
- stateful
- easier to test as an object
- independent from Active Record lifecycle hooks

use a plain Ruby object instead.

Good examples:

- building a push payload
- rendering a complex attachment presentation
- coordinating pagination or formatting on the client

This is not “service objects everywhere.” It is targeted extraction when an object clearly improves readability.

## Keep the Main Model File as the Table of Contents

The main model file should still tell the story:

- associations
- the small number of core callbacks
- the important scopes
- the high-level includes

If a new developer can open the main model and understand the shape of the domain object quickly, the concern split is working.

## Campfire Notes

- `User` is organized around traits: `Avatar`, `Bannable`, `Bot`, `Mentionable`, `Role`, and `Transferable`.
- `Message` is organized the same way with `Attachment`, `Broadcasts`, `Mentionee`, `Pagination`, and `Searchable`.
- Several concerns own logic that clearly belongs to the trait:
  - `User::Role` defines the enum and `can_administer?`
  - `User::Transferable` owns signed transfer links
  - `Message::Searchable` owns full-text index maintenance callbacks
  - `Message::Attachment` owns attachment variants and preprocessing
- Campfire also uses small collaborators where that reads better than a concern:
  - `Room::MessagePusher` for push-delivery orchestration
  - `Messages::AttachmentPresentation` for view rendering
  - `Opengraph::Fetch`, `Opengraph::Document`, and `Opengraph::Metadata` for unfurling
- The pattern is consistent: traits stay in concerns, workflow-heavy or response-shaping logic becomes a dedicated object.
