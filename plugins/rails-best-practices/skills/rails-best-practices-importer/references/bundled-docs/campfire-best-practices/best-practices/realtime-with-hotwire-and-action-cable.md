# Realtime with Hotwire and Action Cable

This document is a portable Rails reference for live, collaboration-heavy interfaces. The key pattern is to separate persisted HTML updates from ephemeral live signals.

## Use Turbo Streams for Persisted UI Changes

If a change should exist for future page loads, Turbo Streams are usually the right transport:

- a new message appears
- a record is updated
- a list item is removed
- a sidebar entry changes

That lets the server keep ownership of HTML and keeps the client simpler.

A good model method often looks like:

```ruby
def broadcast_create
  broadcast_append_to room, :messages, target: [room, :messages]
end
```

This keeps the controller focused on persistence while the model owns the broadcast shape.

## Use Action Cable Channels for Ephemeral Signals

Some live data should not be modeled as Turbo HTML:

- “Alice is typing”
- “Bob is present in this room”
- “this room was marked read”

These are event streams, not HTML fragments.

Action Cable channels are a good fit because they carry small payloads and do not force you to invent DOM-shaped responses for everything.

## Persist the State That Matters

Ephemeral events are fine, but the meaningful state should still live in the database when the product depends on it.

For collaboration apps, that often means:

- unread state
- membership visibility
- last-seen markers
- current participation preferences

The live event can announce the change. The database should still own the truth.

## Keep Client Controllers Small and Event-Driven

A Hotwire client works best when Stimulus controllers do a few narrow jobs:

- subscribe to a channel
- dispatch local events
- toggle a small UI state
- manage pagination or scroll position

Avoid turning the browser into a second application server with duplicated business rules.

## Design for Catch-Up, Not Just the Happy Path

Realtime UIs need a way to recover when the client misses data:

- the user scrolls away from the latest page
- a websocket briefly disconnects
- a page loads with only a partial timeline

That means the live path should be compatible with normal HTTP fetching and pagination. Live events improve freshness; they should not be the only way to reach consistency.

## Campfire Notes

- `Message#broadcast_create` appends new message HTML via Turbo Streams and separately broadcasts a lightweight `"unread_rooms"` event.
- `Message#broadcast_remove` uses Turbo removal for persisted UI changes.
- `PresenceChannel`, `TypingNotificationsChannel`, `UnreadRoomsChannel`, and `ReadRoomsChannel` carry small live payloads that are not modeled as HTML.
- Presence updates persist on `Membership` through `Membership::Connectable`, so “connected” is not just a transient browser flag.
- The client uses narrow Stimulus controllers:
  - `messages_controller.js` handles stream insertion, optimistic UI, and pagination coordination
  - `presence_controller.js` manages visibility-driven presence pings
  - `typing_notifications_controller.js` handles typing state
  - `read_rooms_controller.js` listens for read events
- `MessagePaginator` shows a strong recovery pattern: normal HTTP pagination remains the source of truth, and live updates only extend the latest page.
