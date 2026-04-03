# Passwordless Authentication Architecture

This document is a portable Rails reference for building passwordless authentication with tenant-aware authorization. Use the pattern, not the exact class names. Your app might call the tenant-scoped record `Membership`, `AccountUser`, or `User`.

If you are working in a different repository, start with the generic sections below. The final section lists how Fizzy currently instantiates the pattern.

## The Core Split: Identity vs Membership

Separate global authentication from tenant-scoped authorization.

- `Identity` answers: who is this person across the whole product?
- `Membership` answers: who is this person inside this tenant?

That split solves a common SaaS problem: one person can belong to many accounts without duplicating credentials or sessions.

Representative shape:

```ruby
class Identity < ApplicationRecord
  has_many :memberships
  has_many :sessions
  has_many :magic_links
  has_many :access_tokens
  has_many :passkeys
end

class Membership < ApplicationRecord
  belongs_to :identity
  belongs_to :account

  enum :role, %i[owner admin member]
end
```

If your product is single-tenant or every authenticated person belongs to exactly one tenant, this split may be unnecessary.

## Keep Request Context in One Place

Most apps with tenant-aware auth need one request-scoped object that carries:

- tenant
- session
- identity
- membership
- useful request metadata such as request ID, IP address, and user agent

In Rails, `Current` is the natural home for this:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :account, :session, :identity, :membership

  def session=(session)
    super
    self.identity = session&.identity
  end

  def identity=(identity)
    super
    self.membership = identity&.memberships&.find_by(account: account)
  end
end
```

The important rule is not the exact callback chain. It is the invariant: the authenticated person is global, but the working membership depends on the current tenant.

## Sessions Should Stay Thin

Browser sessions are usually just durable credentials that point back to the global identity.

Typical shape:

```ruby
class Session < ApplicationRecord
  belongs_to :identity
end
```

Useful metadata to capture at session creation time:

- user agent
- IP address
- last-used timestamp

Typical cookie properties:

- signed
- `httponly`
- `same_site: :lax`
- long-lived or permanent, unless your product has stricter security requirements

Keep workflow logic in the auth layer rather than bloating the session model.

## Magic Links Work Best as Single-Use, Short-Lived Codes

Passwordless email login works well when the login code is:

- short-lived
- single-use
- purpose-bound, such as `sign_in` or `sign_up`
- tied back to the identity that started the flow

Representative model:

```ruby
class MagicLink < ApplicationRecord
  belongs_to :identity

  enum :purpose, %i[sign_in sign_up]

  CODE_LENGTH = 6
  EXPIRATION_TIME = 15.minutes
end
```

The important safety rule is this: do not trust the code alone.

A good browser flow also binds the completion step to the person who started it. One common pattern is:

1. user submits an email address
2. app stores that email address in a signed, short-lived pending-auth cookie
3. app emails a code or link
4. completion step verifies both the code and the pending-auth cookie

That prevents a code from one identity being replayed against another in the same browser session.

## Passkeys Should End in the Same Session Model

Passkeys are not a separate identity system. They are another way to prove control of the same global identity.

That means the passkey flow should usually:

1. authenticate the WebAuthn credential
2. resolve the owning identity
3. create the same normal browser session you would create after magic-link login

This keeps the rest of the app simple. Controllers, policies, and audit trails should not need to care whether the session came from email or WebAuthn.

## API Tokens Are Not Browser Sessions

If you support bearer tokens, model them separately from browser sessions.

Representative shape:

```ruby
class AccessToken < ApplicationRecord
  belongs_to :identity

  enum :permission, %i[read write]

  def allows?(method)
    return true if write?
    method.in?(%w[GET HEAD])
  end
end
```

Useful rule:

- allow bearer tokens for API-style requests
- do not silently accept them for HTML navigation

That avoids mixing browser and API trust boundaries.

## Default to Tenant-Scoped Controllers

In multi-tenant apps, most authenticated requests should follow this order:

1. resolve tenant
2. resume or authenticate identity
3. derive the tenant-scoped membership
4. ensure that membership can access the tenant

Only opt out for true pre-auth or public flows:

- login
- signup
- passwordless completion steps
- public pages or public file endpoints

This is the part many apps get wrong. If you authenticate before you know the tenant, you usually end up scattering tenant checks across controllers.

## A Good Browser Login Flow

### Step 1: Start Authentication

Accept an email address on an untenanted or public route.

Typical behavior:

1. look up the identity
2. if it exists, send a sign-in code or link
3. if it does not exist, either create a pending signup flow or respond in a way that does not leak account existence

### Step 2: Create Pending State

Store a signed, short-lived pending-authentication token in a cookie or signed payload.

That payload should usually include:

- email address
- expiration
- optional purpose such as `sign_in` or `sign_up`

### Step 3: Consume the Credential

On the completion step:

1. verify the code or passkey assertion
2. verify the pending-auth state if the flow uses it
3. create the normal session
4. clear the pending-auth state
5. redirect or return JSON

## Use Separate Signed Tokens for One-Off Workflows

Do not overload the session cookie for unrelated workflows.

Useful separate token types include:

- session transfer tokens
- email-change confirmation tokens
- invitation acceptance tokens
- destructive-action confirmation tokens

Those tokens should be:

- purpose-bound
- short-lived
- signed
- modeled around the workflow they protect

For example, changing an email address in a tenant-aware app is often not just `update!(email_address: ...)`. It may require:

1. confirming ownership of the new address
2. updating the global identity
3. re-evaluating memberships
4. rotating or re-issuing the current session

That deserves its own token and controller flow.

## Authorization Should Stay Layered

Keep these layers distinct:

1. authentication: who is this person?
2. tenant access: can they enter this account or workspace at all?
3. resource access: can they see or mutate this board, project, document, or card?

Good controller code usually loads resources through the current membership:

```ruby
class ProjectsController < ApplicationController
  def show
    @project = Current.membership.projects.find(params[:id])
  end
end
```

That is usually safer than loading globally and then checking permissions afterward.

## When to Use This Architecture

This shape is a good fit when:

- one person can belong to multiple tenants
- you want passwordless login
- browser and API authentication should coexist
- account-specific roles and settings differ from global identity data

It may be overkill when:

- the app is single-tenant
- every user has exactly one account
- you only need a single browser session model and no API tokens

## Adaptation Checklist

- Pick your names first: `Identity` plus `Membership`, or `User` plus `AccountUser`, or equivalent.
- Decide where tenant selection happens: path prefix, subdomain, header, or explicit account picker.
- Keep sessions thin and global.
- Keep tenant-specific role and settings data off the global identity.
- Make passwordless flows short-lived and purpose-bound.
- Make bearer tokens separate from browser sessions.
- Add explicit signed tokens for one-off flows instead of stretching the session cookie.

## Fizzy Notes

Fizzy currently instantiates this pattern as follows:

- the global auth record is `Identity`
- the tenant-scoped authorization record is `User`
- `Current` carries `account`, `session`, `identity`, and `user`
- passwordless auth supports both magic links and passkeys
- bearer tokens are allowed for JSON requests, not browser navigation
- email changes and session transfer use separate signed-token flows
