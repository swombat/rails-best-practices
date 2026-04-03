# Background Jobs and Integrations

This document is a portable Rails reference for external integrations and asynchronous work. The central pattern is to keep jobs thin, keep payload logic near the domain, and make failure behavior explicit.

## Jobs Should Be Tiny Entry Points

A good job mostly identifies the domain objects and calls the real behavior.

Representative examples:

```ruby
class Room::PushMessageJob < ApplicationJob
  def perform(room, message)
    Room::MessagePusher.new(room:, message:).push
  end
end
```

```ruby
class Bot::WebhookJob < ApplicationJob
  def perform(bot, message)
    bot.deliver_webhook(message)
  end
end
```

That keeps retry behavior, serialization, and domain logic from collapsing into one unreadable class.

## Put Integration Semantics Near the Integrating Model

If a webhook belongs to a bot, or a push subscription belongs to a user, the model is usually the right place for:

- request payload construction
- response interpretation
- delivery-specific configuration

This keeps the meaning of the integration close to the data it depends on.

## Build Small Collaborators for Recipient Selection and Payload Shaping

When delivery depends on several domain rules, use a small object instead of stuffing that logic into the job or controller.

Good responsibilities for such an object:

- which users should receive a notification
- which channels or subscriptions are eligible
- what the title, body, and path should be

This object often becomes the real integration policy layer.

## Handle External Failure Modes Deliberately

Integrations fail in predictable ways:

- timeouts
- invalid subscriptions
- bad response bodies
- unexpected content types

Decide which failures should:

- retry
- be ignored
- create a visible in-product fallback
- disable the broken endpoint

The wrong move is letting every failure collapse into a generic exception without any policy.

## Keep Automation Auth Separate but Domain-Aligned

Bots, webhooks, and machine clients should reuse the domain model where possible while keeping authentication narrow.

That means:

- a bot can create a message using the normal message model
- the controller can still require a bot key instead of a browser session
- outgoing webhook payloads can point back to the same canonical URLs humans use

## Campfire Notes

- Jobs are intentionally thin: `Bot::WebhookJob` and `Room::PushMessageJob` do almost no work themselves.
- `Webhook` owns request construction, timeout configuration, response parsing, and bot reply creation.
- `Room::MessagePusher` owns recipient selection and payload shaping for web push delivery.
- `Push::Subscription` is a real model and is responsible for building a `WebPush::Notification` with the right endpoint keys and badge count.
- Bot auth is separate from human auth, but bot-created messages still flow through the normal `Message` domain model via `Messages::ByBotsController`.
- Campfire converts successful webhook responses back into messages, including attachments, which is a clean example of keeping the integration mapped onto the core domain instead of inventing a parallel “bot response” subsystem.
