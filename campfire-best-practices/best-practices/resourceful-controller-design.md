# Resourceful Controller Design

This document is a portable Rails reference. The central idea is that controllers stay small when routes are modeled as resources instead of ad hoc verbs.

## Favor Nouns Over Custom Actions

When an endpoint feels like “do something to a record,” stop and ask what resource actually changed.

Examples:

- a subscription exists or does not exist
- a closure exists or does not exist
- a membership preference changes
- an avatar exists or does not exist

That usually points to a resource, not a custom member action.

Instead of:

```ruby
resources :projects do
  post :archive, on: :member
end
```

prefer:

```ruby
resources :projects do
  resource :archive, only: %i[create destroy]
end
```

That gives you a controller focused on one concern.

## Use Singular Resources for Singleton State

A singular nested resource is a strong fit when a parent has one of something:

- one profile
- one logo
- one join code
- one notification preference per user-room pair
- one current session

This keeps routes honest and controllers compact.

## Namespace by Domain Boundary, Not by HTTP Format

Namespaces work well when they mirror the domain:

- `Accounts::UsersController`
- `Rooms::ClosedsController`
- `Messages::BoostsController`

That is better than building giant top-level controllers with dozens of methods for unrelated subdomains.

## Share Parent Lookup Through Concerns

When several controllers need the same scoped parent lookup, extract the lookup and nothing more.

Representative example:

```ruby
module RoomScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_room
  end

  private
    def set_room
      @membership = Current.user.memberships.find_by!(room_id: params[:room_id])
      @room = @membership.room
    end
end
```

That is a good concern:

- it is narrow
- it is obviously reusable
- it preserves controller readability

## Keep Controllers Close to HTTP and Push Domain Behavior Down

A controller should mainly:

- load records
- authorize
- call a meaningful domain method
- choose the response

It should not own the business workflow.

If the interesting line is buried under 40 lines of branching, callbacks, and side-effect orchestration, the domain logic is in the wrong layer.

## Variant Controllers Are Better Than Variant Branches

When the product has a few meaningful variants of the same concept, separate controllers often read better than a single controller full of branches.

Examples:

- open vs private workspaces
- direct vs shared conversations
- human vs bot message creation

The controller inheritance can stay shallow. The goal is not cleverness; it is a smaller decision surface per endpoint.

## Campfire Notes

- `config/routes.rb` uses resource-oriented routing throughout: `resource :session`, `resource :account`, `resource :join_code`, `resource :logo`, `resource :involvement`, `resource :avatar`, and more.
- Room variants are split into `Rooms::OpensController`, `Rooms::ClosedsController`, and `Rooms::DirectsController` instead of one large `RoomsController`.
- Message variants are split too: `MessagesController` for human-created messages and `Messages::ByBotsController` for bot ingestion.
- `RoomScoped` encapsulates the parent room lookup through the current user’s membership instead of letting each controller fetch `Room.find(params[:room_id])`.
- `Rooms::InvolvementsController` is a good example of a singular nested resource. It manages one user’s involvement setting for one room.
- `Users::ProfilesController`, `Users::AvatarsController`, `Accounts::CustomStylesController`, and `Accounts::LogosController` show the same pattern for singleton state.
