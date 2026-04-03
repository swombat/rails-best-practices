# Memberships and Room Architecture

This document is a portable reference for collaboration-heavy Rails apps. The main pattern is to model access through a first-class join record and keep per-user state there instead of smearing it across unrelated tables.

## Make the Join Table Part of the Domain

In many apps, a join table is not just glue. It is the place where important user-specific state lives.

Good examples:

- role within a project
- notification level within a room
- unread markers
- presence state
- mute or archive preferences

When that is true, the join model deserves real methods, scopes, validations, and tests.

## Put Per-User State on the Membership, Not on the Parent

If one room has many users and each user can be unread, muted, invisible, or connected independently, those attributes belong on the membership record.

This avoids impossible parent-level columns like:

- `room.unread_for_user_id`
- `room.visibility`
- `room.connected_at`

Per-user state should be modeled per user.

## Use Association Extensions for Bulk Grant/Revoke Logic

Bulk membership changes tend to repeat:

- add these users
- remove these users
- revise membership based on a new selection

Association extensions are a clean place for that behavior because they keep the API close to the relationship itself.

Representative example:

```ruby
has_many :memberships do
  def grant_to(users)
    # ...
  end

  def revoke_from(users)
    # ...
  end
end
```

This reads better than scattering `Membership.insert_all` and `destroy_by` calls across controllers and jobs.

## Use Type Variants Only When the Data Model Is Mostly Shared

Single-table inheritance or another typed-parent approach works well when:

- the variants share one table
- most associations are common
- only a few methods or callbacks differ

It is a poor fit when the variants need mostly different data or workflows.

The rule is not “never use STI.” The rule is “use it only when the variants truly are one thing with a few behavioral differences.”

## Treat Direct Conversations as a Membership Set

If two or more users should share one canonical direct thread, the uniqueness rule is not a foreign key. It is the unordered participant set.

That usually means one of two approaches:

1. persist a canonical digest of sorted participant IDs
2. perform a lookup that compares the existing membership set

The digest scales better. The explicit set comparison is acceptable when the data volume is small and the code needs to stay simple.

## Campfire Notes

- `Membership` is a real domain model. It stores `involvement`, `unread_at`, `connected_at`, and `connections`.
- The unread and presence logic lives on memberships, not on rooms or users.
- `Membership::Connectable` encapsulates presence TTLs, connect/disconnect updates, and connected/disconnected scopes.
- `Room` owns the relationship API through association extensions: `grant_to`, `revoke_from`, and `revise`.
- `Room` uses STI with `Rooms::Open`, `Rooms::Closed`, and `Rooms::Direct`. That works here because the variants share the same table and most behavior.
- `Rooms::Open` auto-grants memberships to all active users.
- `Rooms::Direct` changes default involvement and implements `find_or_create_for(users)` to ensure one direct room per participant set.
- Campfire’s direct-room lookup currently scans existing rooms and compares `Set.new(room.user_ids)`. For a new app with high volume, prefer a persisted participant digest instead.
