# Authentication and Current Context

This document is a portable Rails reference. The core idea is simple: keep authentication state explicit, keep request context narrow, and store only durable session identifiers in cookies.

## Use `Current` Sparingly and Intentionally

`ActiveSupport::CurrentAttributes` is useful when it carries request-scoped facts that many layers need:

- the authenticated session
- the authenticated user
- the current request
- a tenant or account resolved for the request

It should not become a second global container for arbitrary business state.

Good `Current` objects are boring. They expose a few high-value attributes and maybe a couple of derived readers.

Representative example:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :request

  def session=(value)
    super
    self.user = value&.user
  end
end
```

That keeps the rest of the application simple without hiding too much.

## Persist Sessions in the Database, Not in the Cookie

The cookie should hold an opaque token, not a serialized user record and not the application session itself.

Why:

- sessions can be revoked centrally
- IP address and user agent can be recorded for security and debugging
- multiple active sessions per user are easy
- you can expire or rotate sessions without changing the cookie format

Typical pattern:

1. create a `Session` record that belongs to a user
2. generate a secure token on the record
3. write only that token to a signed, `httponly` cookie
4. restore the session on each request by looking up the token

The database record becomes the source of truth.

## Put Authentication Flow in a Controller Concern

Controllers should not all open-code session lookup, redirects, and cookie handling.

A dedicated concern keeps the behavior consistent:

- `before_action :require_authentication`
- a class method to allow anonymous access for selected actions
- helpers for starting, restoring, and terminating sessions
- one place to define what “authenticated” means for the app

This is also the right place for narrow variants such as API tokens, magic links, or bot keys. The concern can expose opt-outs like `allow_api_access` or `allow_bot_access` without forcing every controller to duplicate branching logic.

## Refresh Session Activity Lazily

Do not update session metadata on every request if you do not need per-request precision.

Refreshing once per hour, once per 15 minutes, or on other coarse intervals is usually enough for:

- “last active” displays
- suspicious-session reviews
- remote disconnect logic

That avoids a write on every request while keeping the metadata useful.

## Use Signed IDs for Narrow, Purpose-Built Links

Rails signed IDs are a strong default for links that should expose a record without exposing raw primary keys or building a separate token table.

Good use cases:

- temporary session transfer links
- public avatar URLs
- email verification links
- password reset flows

Give each signed ID a purpose and, when appropriate, an expiration.

Representative example:

```ruby
class User < ApplicationRecord
  def transfer_id
    signed_id(purpose: :transfer, expires_in: 4.hours)
  end
end
```

This is often cleaner than inventing a separate token model for every narrow use case.

## Separate Human Authentication from Automation Authentication

If the application supports automation, keep the mechanism explicit.

Good patterns:

- session cookies for humans
- API keys or bot keys for automation
- narrow controller opt-ins for automated access

That avoids blurring browser behavior, CSRF expectations, and auditing.

## Campfire Notes

- `Current` carries `session`, `user`, and `request`, and derives `user` from `session`.
- `Current.account` returns `Account.first`, which is a deliberate single-account shortcut for this app.
- `Authentication` is a controller concern that restores sessions from `cookies.signed[:session_token]`, starts sessions, terminates sessions, and offers `allow_unauthenticated_access`, `require_unauthenticated_access`, and `allow_bot_access`.
- Session cookies are `signed`, `permanent`, `httponly`, and `same_site: :lax`.
- `Session` stores `user_agent`, `ip_address`, `last_active_at`, and refreshes activity only if the last refresh was more than an hour ago.
- Bot access is intentionally separate from human access. `Messages::ByBotsController` opts in with `allow_bot_access`.
- Session transfer links use `User#transfer_id` and `User.find_by_transfer_id`.
- Public avatar routes use signed IDs through `User#avatar_token` instead of exposing raw user IDs.
