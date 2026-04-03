# Single-Account Bootstrap

This document is a portable reference for Rails applications that are installed once per customer or run as a single shared account. The central pattern is to model that constraint explicitly instead of pretending the app is multi-tenant when it is not.

## Treat Single-Tenancy as a Real Architectural Choice

Some products do not need accounts, subdomains, or tenant switching. They need one installation, one top-level account, and many users inside it.

When that is the product shape:

- say so in the data model
- say so in the routing
- say so in the bootstrap flow

Do not build a fake multi-tenant shell if every deployment is meant to represent one customer.

## Model the Singleton at the Database Level

If the application is supposed to have exactly one top-level account record, enforce that in the database.

Good options:

- a unique guard column with a fixed value
- a fixed primary key inserted once
- a separate settings table with a known singleton row

The important part is that the database should prevent accidental creation of a second record.

Application-level checks like `redirect if Account.any?` are useful, but they are not sufficient on their own.

## Use a First-Run Service Object or Command

Bootstrapping a new installation usually creates more than one record:

- the singleton account
- the first administrator
- the first project, room, or workspace
- any default settings or seeded permissions

Put that in one object and one transaction.

Representative example:

```ruby
class FirstRun
  def self.create!(user_params)
    ApplicationRecord.transaction do
      account = Account.create!(name: "My App")
      workspace = Workspace.create!(name: "General")
      admin = User.create!(user_params.merge(role: :administrator))

      workspace.memberships.create!(user: admin)
      admin
    end
  end
end
```

This makes the bootstrap flow testable and keeps controllers small.

## Gate the App with an Explicit First-Run Flow

A single-account app usually has two early states:

1. not initialized yet
2. initialized and ready for sign-in

Make those states explicit.

Typical pattern:

- if the singleton does not exist, redirect to `first_run`
- once the singleton exists, block repeated access to the first-run endpoint

This is simpler and more reliable than scattering `if Account.none?` checks across unrelated controllers.

## Keep Invitations Simple

Single-account apps often do not need elaborate organization management on day one.

A join code, invitation URL, or admin-created user flow is often enough.

The main requirement is that invitation logic should respect the single-account model:

- users join the existing installation
- they do not create their own account container
- the account-level policies remain centralized

## Campfire Notes

- Campfire is explicitly single-tenant. `Current.account` returns the first account record.
- The database enforces the singleton with `accounts.singleton_guard` and a unique index.
- `FirstRun.create!` creates the `Account`, the first open room, and the first administrator, then grants that user membership in the room.
- `FirstRunsController` blocks repeated first-run access by redirecting to the root once an account exists.
- `SessionsController#new` sends users to `first_run` when there are no users yet.
- New users join the existing account via a join code, not by creating a second tenant.
- Room-creation permissions are account settings, not per-tenant logic, because there is only one account in the deployment.
