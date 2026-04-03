# Multi-Tenant Authentication and Authorization

This document is a portable reference for Rails applications where one authenticated person can belong to multiple tenants. It focuses on architecture and request flow. For credential types such as magic links, passkeys, and access tokens, see `authentication-spec.md`.

If you are transplanting this pattern into another repository, read the generic sections first and treat the `Fizzy Notes` section as one concrete implementation.

## The Core Problem

Multi-tenant apps often have two competing truths:

- a person is the same human across the whole product
- their permissions, profile details, and settings vary by account

If you flatten those concerns into one table, the model usually becomes confused. Global authentication data and tenant-local behavior start fighting each other.

The cleanest fix is to split them.

## The Core Split: Identity vs Membership

Use one global record for authentication and one tenant-scoped record for authorization.

Typical naming:

- `Identity` or `Person` for the global record
- `Membership`, `AccountUser`, or `User` for the tenant-scoped record

Representative shape:

```ruby
class Identity < ApplicationRecord
  has_many :memberships
  has_many :accounts, through: :memberships
end

class Membership < ApplicationRecord
  belongs_to :identity
  belongs_to :account

  enum :role, %i[owner admin member]
end
```

Why this helps:

- one login can reach many accounts
- per-account roles stay local
- profile fields can live where they actually vary
- authorization can be expressed through tenant-scoped queries instead of global conditionals

## Choose One Tenant Selection Strategy

Every request needs to resolve its tenant before application code starts making authorization decisions.

Common strategies:

### Path Prefix

```text
/1234567/projects/42
```

Good when:

- you want local development to stay simple
- you do not want subdomain routing complexity
- you want URLs that can be copied without DNS assumptions

### Subdomain

```text
https://acme.example.com/projects/42
```

Good when:

- tenant identity should be visible in the host
- custom domains matter
- the product is heavily workspace-branded

### Header or Token

Good for:

- internal APIs
- service-to-service traffic
- native clients with explicit tenant selection

The important rule is not which strategy you choose. It is that tenant selection should happen once, early, and consistently.

## Resolve Tenant Before Authorization

Most multi-tenant request pipelines should look like this:

1. resolve tenant
2. resume or authenticate the global identity
3. derive the tenant-scoped membership
4. authorize access to the tenant
5. load resources through tenant-scoped queries

If you skip step 1, later code often ends up checking tenant access too late.

## Keep Tenant Context in Request Scope

In Rails, `Current` is a good place to hold the working tenant and membership:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :account, :identity, :membership, :session
end
```

Useful derived behavior:

- assigning `session` can derive `identity`
- assigning `identity` can derive `membership` from `identity + account`

That makes controllers, jobs, and policies much simpler because they can ask one shared request object for the current tenant state.

## Authorization Should Happen in Layers

### Layer 1: Tenant Entry

First ask: does this identity have an active membership in the current tenant?

That check should cover:

- membership existence
- membership active or suspended state
- tenant active or archived state

### Layer 2: Tenant-Local Resource Access

After tenant entry, ask the narrower question:

- can this membership access this board, project, document, or card?

Representative controller style:

```ruby
class ProjectsController < ApplicationController
  def show
    @project = Current.membership.projects.find(params[:id])
  end
end
```

This is usually better than:

```ruby
@project = Project.find(params[:id])
authorize! @project
```

The query itself encodes the tenant boundary.

## Keep Tenant-Specific Data Off the Global Identity

A good rule:

- authentication belongs to the global record
- tenant-local behavior belongs to the tenant-local record

Typical tenant-local fields:

- role
- avatar
- display name, if it differs by account
- notification settings
- pins, favorites, and local preferences
- timezone override, if it can vary by account

This matters because account-scoped profile changes should not accidentally mutate data that is shared across all tenants.

## Background Jobs and Real-Time Connections Need Tenant Context Too

Multi-tenancy is not only a controller concern.

If jobs, mailers, websockets, or exports rely on tenant state, they should carry tenant context explicitly.

Typical examples:

- Active Job serializes tenant ID and restores it inside `perform`
- Action Cable resolves the tenant during connection setup
- long-running exports wrap work in a `Current.with_account(account)` style helper

Without this, background work often becomes the place where tenant leaks appear.

## Testing Guidance

Useful tests for multi-tenant auth systems:

- a valid identity can enter a tenant where it has an active membership
- the same identity is rejected from tenants where it has no membership
- suspended memberships cannot access the tenant
- resource queries never escape the current tenant
- jobs and websocket connections restore the correct tenant context

The most important regression to protect against is cross-tenant data access.

## When Not to Use This Shape

This architecture is probably too much when:

- the app is single-tenant
- every authenticated person belongs to exactly one account
- there is no meaningful tenant-local role or settings layer

In those cases, one `User` record may be enough.

## Adaptation Checklist

- Decide what the global record is called.
- Decide what the tenant-scoped record is called.
- Decide where tenant selection happens.
- Resolve tenant before deriving the tenant-scoped membership.
- Load records through tenant-scoped associations whenever possible.
- Carry tenant context into jobs, websockets, and exports.
- Keep shared identity data and account-local profile data separate.

## Fizzy Notes

Fizzy currently applies this pattern in a path-based multi-tenant app:

- the global auth record is `Identity`
- the tenant-scoped authorization record is `User`
- middleware extracts the account slug from the URL and sets `Current.account`
- `Current.user` is derived from `Current.identity + Current.account`
- board-level access is modeled separately from account membership
- Active Job and Action Cable both restore tenant context explicitly
