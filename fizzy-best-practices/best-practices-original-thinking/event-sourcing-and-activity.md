# Event Sourcing and Activity Tracking

This document describes patterns for implementing an event system that powers activity feeds, notifications, webhooks, and audit logs. The approach uses a single Event model with polymorphic associations and JSON metadata, providing flexibility without schema complexity.

## The Event Model

### Core Structure

```ruby
class Event < ApplicationRecord
  belongs_to :account
  belongs_to :board  # Primary organizational unit
  belongs_to :creator, class_name: "User"
  belongs_to :eventable, polymorphic: true

  # JSON column for action-specific data
  store_accessor :particulars, :assignee_ids
end
```

**Schema:**
```ruby
create_table :events do |t|
  t.references :account, null: false
  t.references :board, null: false
  t.references :creator, null: false
  t.string :eventable_type, null: false
  t.uuid :eventable_id, null: false
  t.string :action, null: false
  t.json :particulars
  t.timestamps
end

add_index :events, [:board_id, :action, :created_at]
add_index :events, [:eventable_type, :eventable_id]
```

### Key Design Decisions

1. **String actions, not enums** - Actions like `"card_published"` are stored as strings. This avoids migrations when adding new event types.

2. **JSON particulars** - Action-specific data (old values, new values, related IDs) lives in a JSON column, avoiding wide tables with mostly-null columns.

3. **Board-centric** - Events belong to a board, the primary organizational unit. This simplifies access control and querying.

4. **Polymorphic eventable** - The thing the event is about (Card, Comment, etc.) uses Rails polymorphic associations.

## The Eventable Concern

### Basic Pattern

```ruby
module Eventable
  extend ActiveSupport::Concern

  included do
    has_many :events, as: :eventable, dependent: :destroy
  end

  def track_event(action, creator: Current.user, board: self.board, **particulars)
    if should_track_event?
      event = board.events.create!(
        action: "#{eventable_prefix}_#{action}",
        creator: creator,
        eventable: self,
        particulars: particulars
      )
      event_was_created(event)
      event
    end
  end

  # Hook for subclasses to add behavior after event creation
  def event_was_created(event)
  end

  private
    def should_track_event?
      true
    end

    def eventable_prefix
      self.class.name.demodulize.underscore
    end
end
```

**Key features:**

1. **Automatic action prefixing** - `track_event :published` becomes `"card_published"` for Card.

2. **Current user default** - Creator defaults to `Current.user`, keeping call sites clean.

3. **Hook methods** - `should_track_event?` and `event_was_created` allow customization without overriding core logic.

4. **Keyword particulars** - Extra data passed as keyword arguments flows into the JSON column.

### Model-Specific Customization

```ruby
module Card::Eventable
  include ::Eventable

  included do
    after_save :track_title_change, if: :saved_change_to_title?
  end

  def event_was_created(event)
    create_system_comment_for(event)
    touch_last_active_at
  end

  private
    def should_track_event?
      published?  # Only track for published cards, not drafts
    end

    def track_title_change
      return unless title_before_last_save.present?
      track_event :title_changed,
        old_title: title_before_last_save,
        new_title: title
    end
end
```

## When to Create Events

### Explicit Calls in Domain Methods

Most events are created explicitly within rich model methods:

```ruby
module Card::Closeable
  def close(user: Current.user)
    transaction do
      update!(closed_at: Time.current, closed_by: user)
      track_event :closed, creator: user
    end
  end

  def reopen(user: Current.user)
    transaction do
      update!(closed_at: nil, closed_by: nil)
      track_event :reopened, creator: user
    end
  end
end
```

### Callbacks for Automatic Tracking

Some events are better as callbacks:

```ruby
module Card::Statuses
  included do
    after_create -> { track_event :published }
  end
end

module Card::Eventable
  included do
    after_save :track_title_change, if: :saved_change_to_title?
  end
end
```

**When to use callbacks:**
- The event should always fire for this lifecycle change
- No conditional logic about whether to track
- The "whenever X, do Y" pattern applies

**When to use explicit calls:**
- The event is part of a specific business action
- Conditional logic determines whether to track
- The actor needs to be explicitly passed

## Storing Action-Specific Data

### The Particulars Pattern

```ruby
# When creating
track_event :assigned, assignee_ids: [user.id]
track_event :title_changed, old_title: "...", new_title: "..."
track_event :triaged, column: column.name

# Accessing
event.particulars["old_title"]
event.assignee_ids  # via store_accessor
```

### Store Accessors for Common Fields

```ruby
module Event::Particulars
  extend ActiveSupport::Concern

  included do
    store_accessor :particulars, :assignee_ids, :old_title, :new_title
  end

  def assignees
    @assignees ||= User.where(id: assignee_ids)
  end
end
```

## Consuming Events

### Activity Feeds

Build timeline views by querying events:

```ruby
class User::DayTimeline
  TIMELINEABLE_ACTIONS = %w[
    card_published card_closed card_reopened
    card_assigned card_unassigned
    card_triaged card_postponed
    comment_created
  ]

  def initialize(user:, day:, filter:)
    @user = user
    @day = day
    @filter = filter
  end

  def events
    base_scope
      .where(created_at: @day.all_day)
      .order(created_at: :desc)
  end

  def added_column
    events.where(action: %w[card_published card_reopened])
  end

  def updated_column
    events.where.not(action: %w[card_published card_closed card_reopened])
  end

  def closed_column
    events.where(action: "card_closed")
  end

  private
    def base_scope
      Event
        .where(board: accessible_boards)
        .where(action: TIMELINEABLE_ACTIONS)
        .includes(:creator, :eventable)
    end

    def accessible_boards
      @filter.boards.presence || @user.boards
    end
end
```

### Grouping by Time

```ruby
def events_by_hour
  events.group_by { |e| e.created_at.hour }
end
```

### Efficient Preloading

```ruby
scope :preloaded, -> {
  includes(:creator, :board, eventable: [:rich_text_body, :rich_text_description])
}
```

## Notifications

### After-Commit Dispatch

```ruby
module Event::Notifiable
  extend ActiveSupport::Concern

  included do
    after_create_commit :notify_recipients_later
  end

  private
    def notify_recipients_later
      NotifyRecipientsJob.perform_later(self)
    end
end
```

Using `after_create_commit` ensures notifications only dispatch after the transaction commits successfully.

### The Notifier Pattern

A factory determines the right notifier for each event:

```ruby
class Notifier
  def self.for(event)
    notifier_class = "Notifier::#{event.eventable_type}EventNotifier".safe_constantize
    notifier_class&.new(event)
  end

  def initialize(event)
    @event = event
  end

  def notify
    return if @event.creator.system?
    recipients.each do |recipient|
      Notification.create!(user: recipient, event: @event)
    end
  end

  private
    def recipients
      raise NotImplementedError
    end
end
```

### Per-Model Notification Logic

```ruby
class Notifier::CardEventNotifier < Notifier
  private
    def recipients
      case @event.action
      when "card_assigned"
        # Only notify the assignees
        @event.assignees.excluding(@event.creator)
      when "card_published"
        # Notify watchers except creator and mentioned users
        board.watchers
          .without(@event.creator, *card.mentionees)
          .including(*card.assignees)
      when "comment_created"
        # Notify card watchers except creator and mentioned
        card.watchers.without(@event.creator, *comment.mentionees)
      else
        # Default: notify board watchers
        board.watchers.without(@event.creator)
      end
    end
end
```

## Webhooks

### Dispatch Pattern

```ruby
module Event::WebhookDispatch
  extend ActiveSupport::Concern

  included do
    after_create_commit :dispatch_webhooks_later
  end

  private
    def dispatch_webhooks_later
      WebhookDispatchJob.perform_later(self)
    end
end
```

### Finding Matching Webhooks

```ruby
class Webhook < ApplicationRecord
  scope :triggered_by, ->(event) {
    where(board: event.board)
      .where("subscribed_actions @> ?", [event.action].to_json)
  }

  def trigger(event)
    deliveries.create!(event: event)
  end
end
```

### Payload Rendering

```ruby
# webhooks/event.json.jbuilder
json.event do
  json.id @event.id
  json.action @event.action
  json.created_at @event.created_at.utc.iso8601

  json.eventable do
    json.partial! @event.eventable
  end

  json.board do
    json.partial! @event.board
  end

  json.creator do
    json.partial! @event.creator
  end
end
```

## System Comments (Activity on Cards)

Events can generate visible activity entries:

```ruby
class Card::SystemCommenter
  def initialize(event)
    @event = event
  end

  def comment
    return unless body.present?
    card.comments.create!(
      creator: account.system_user,
      body: body,
      created_at: @event.created_at
    )
  end

  private
    def body
      case @event.action
      when "card_assigned"
        "#{creator_name} assigned this to #{assignee_names}."
      when "card_closed"
        "Moved to Done by #{creator_name}"
      when "card_board_changed"
        "Moved from #{old_board} to #{new_board}"
      end
    end
end
```

This creates human-readable activity in the card's comment stream using a system user.

## Action Inquiry

Rails' StringInquirer provides convenient query methods:

```ruby
event.action  # => "card_published"
event.action.inquiry.card_published?  # => true
event.action.inquiry.comment_created?  # => false
```

Define an accessor for cleaner code:

```ruby
class Event < ApplicationRecord
  def action_inquiry
    action.inquiry
  end
end

# Usage
event.action_inquiry.card_published?
```

## Audit Log Considerations

This event system naturally supports audit logging:

1. **Who**: `event.creator` records the actor
2. **What**: `event.action` describes the action
3. **When**: `event.created_at` timestamps it
4. **Where**: `event.board` and `event.account` provide context
5. **Details**: `event.particulars` stores before/after values

For compliance requirements, consider:
- Making events immutable (no updates or deletes)
- Adding IP address and user agent tracking
- Separate long-term archive storage

## Summary

**Core principles:**

1. **Single Event model** - One table handles all event types via polymorphism and JSON.

2. **Eventable concern** - Provides consistent `track_event` interface with hooks for customization.

3. **Explicit over implicit** - Most events created in domain methods, not callbacks.

4. **Particulars for flexibility** - JSON column stores action-specific data without schema changes.

5. **After-commit for side effects** - Notifications and webhooks only fire after transaction commits.

6. **Factory for notification routing** - Different event types have different notification logic.

7. **Board-centric organization** - Events belong to boards, simplifying access control and queries.

This architecture scales from simple activity feeds to full audit logging, with the same Event records powering notifications, webhooks, and compliance reporting.
