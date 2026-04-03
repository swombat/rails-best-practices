# Callbacks Done Right

Callbacks are one of the most controversial features in Rails. They introduce indirection, can make debugging harder, and when misused, turn your models into a tangled mess of side effects. But the answer isn't "never use callbacks." The answer is to use them thoughtfully, in situations where they're the right tool for the job.

This document captures the 37signals approach to Rails callbacks, based on how we build Fizzy and other applications. We use callbacks extensively—but we use them well.

## The Core Question: Whenever X, Do Y

The litmus test for whether a callback is appropriate is simple: Can you express the behavior as "whenever X happens, do Y"?

If the answer is yes, and you want that behavior to apply **universally** regardless of how the model is modified, then a callback is often the right choice.

### Good Examples

```ruby
# "Whenever a comment is created, track an event"
module Comment::Eventable
  extend ActiveSupport::Concern

  include ::Eventable

  included do
    after_create_commit :track_creation
  end

  private
    def track_creation
      track_event("created", board: card.board, creator: creator)
    end
end
```

```ruby
# "Whenever a card is updated, detect activity spikes"
module Card::Stallable
  extend ActiveSupport::Concern

  included do
    before_update :remember_to_detect_activity_spikes
    after_update_commit :detect_activity_spikes_later, if: :should_detect_activity_spikes?
  end

  private
    def remember_to_detect_activity_spikes
      @should_detect_activity_spikes = published? && last_active_at_changed?
    end

    def should_detect_activity_spikes?
      @should_detect_activity_spikes
    end

    def detect_activity_spikes_later
      Card::ActivitySpike::DetectionJob.perform_later(self)
    end
end
```

```ruby
# "Whenever a notifiable object is created, notify recipients"
module Notifiable
  extend ActiveSupport::Concern

  included do
    has_many :notifications, as: :source, dependent: :destroy

    after_create_commit :notify_recipients_later
  end

  def notify_recipients
    Notifier.for(self)&.notify
  end

  private
    def notify_recipients_later
      NotifyRecipientsJob.perform_later self
    end
end
```

In each of these cases, the callback ensures **consistency**. If you introduce a new way to create a comment, it will still track an event. If you update a card through any code path, it will still detect activity spikes if appropriate. This is good design.

## When NOT to Use Callbacks

Callbacks are not for orchestrating complex business processes. They're not for chaining together multi-step workflows. They're not for scenarios where different code paths need different behavior.

### Bad Example: Orchestrating Complex Flows

```ruby
# DON'T DO THIS
class Order < ApplicationRecord
  after_create :charge_credit_card
  after_create :send_confirmation_email
  after_create :update_inventory
  after_create :notify_shipping_department
  after_create :create_loyalty_points

  # This creates a complex chain that's hard to reason about
  # What if one step fails? What's the order of execution?
  # Can we ever create an order without all these side effects?
end
```

This is a disaster. You've turned a simple model creation into a multi-step process that's hard to debug, hard to test, and impossible to skip when you need to.

### Better: Explicit Orchestration

```ruby
# DO THIS INSTEAD
class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)

    if @order.save
      OrderProcessor.new(@order).process
      redirect_to @order
    else
      render :new
    end
  end
end

class OrderProcessor
  def initialize(order)
    @order = order
  end

  def process
    charge_credit_card
    send_confirmation_email
    update_inventory
    notify_shipping_department
    create_loyalty_points
  end

  # ... implementation
end
```

Now it's explicit. The controller says "create the order, then process it." You can test the order creation separately from the processing. You can process an order at any time. The behavior is clear and controllable.

## The Explicit vs. Implicit Decision

Both approaches exist in the same codebase, and that's fine. The key is being **mindful** about which one you choose.

### When Explicit is Better

Some things are better expressed explicitly in the method that performs the action:

```ruby
module Card::Triageable
  def send_back_to_triage(skip_event: false)
    transaction do
      resume
      update! column: nil
      track_event "sent_back_to_triage" unless skip_event
    end
  end
end
```

Here, tracking the event is part of the explicit method signature. The method says "I'm sending this back to triage, and I'm going to track an event about it (unless you tell me not to)." This is clearer than having a callback that fires on `column` becoming `nil`.

Why? Because:
1. The behavior is specific to this particular operation
2. There's an escape hatch (`skip_event`) for special cases
3. The method name describes a complete business operation, not just a data change

### When Callbacks are Better

Other things are better expressed as callbacks:

```ruby
module Card::Eventable
  included do
    after_save :track_title_change, if: :saved_change_to_title?
  end

  private
    def track_title_change
      if title_before_last_save.present?
        track_event "title_changed", particulars: { old_title: title_before_last_save, new_title: title }
      end
    end
end
```

This is a callback because:
1. It should happen **whenever** the title changes, regardless of how
2. It's not specific to any particular business operation
3. There's no reason to ever skip it (if you change a title, you want to track it)
4. It's a cross-cutting concern that applies universally

## Combine Callbacks with Object Composition

One of our most powerful patterns is using callbacks to trigger simple method calls, then delegating the complexity to dedicated domain objects.

### The Pattern

```ruby
# The callback triggers a simple method
module Notifiable
  included do
    after_create_commit :notify_recipients_later
  end

  private
    def notify_recipients_later
      NotifyRecipientsJob.perform_later self
    end
end

# The job delegates to the model
class NotifyRecipientsJob < ApplicationJob
  def perform(notifiable)
    notifiable.notify_recipients
  end
end

# The model delegates to a dedicated class
module Notifiable
  def notify_recipients
    Notifier.for(self)&.notify
  end
end

# The dedicated class handles the complexity
class Notifier
  class << self
    def for(source)
      case source
      when Event
        "Notifier::#{source.eventable.class}EventNotifier".safe_constantize&.new(source)
      when Mention
        MentionNotifier.new(source)
      end
    end
  end

  def notify
    if should_notify?
      recipients.sort_by(&:id).map do |recipient|
        Notification.create! user: recipient, source: source, creator: creator
      end
    end
  end

  # ... rest of implementation
end
```

### Why This Works

1. **The callback is simple**: It just enqueues a job. No complex logic.
2. **The job is simple**: It just calls a method. No complex logic.
3. **The model method is simple**: It just delegates to a domain object.
4. **The domain object handles complexity**: This is where the real logic lives.

This keeps each layer clean and focused. The callback mechanism itself remains simple and predictable, while the actual business logic is in a testable, composable domain object.

## Callback Patterns We Use

### Pattern: _later and _now

When a callback enqueues a job that calls back into the model, we use consistent naming:

```ruby
module Event::Relaying
  extend ActiveSupport::Concern

  included do
    after_create_commit :relay_later
  end

  def relay_later
    Event::RelayJob.perform_later(self)
  end

  def relay_now
    # ... actual relay logic
  end
end

class Event::RelayJob < ApplicationJob
  def perform(event)
    event.relay_now
  end
end
```

The `_later` suffix means "enqueue a job." The `_now` suffix means "do it synchronously." This makes the control flow obvious.

### Pattern: Conditional Callbacks

Use `:if` and `:unless` liberally to make callbacks precise:

```ruby
included do
  after_save :track_title_change, if: :saved_change_to_title?
  after_update_commit :detect_activity_spikes_later, if: :should_detect_activity_spikes?
end
```

Don't put complex conditionals in the callback itself. Extract them to well-named predicate methods.

### Pattern: Callbacks That Call One Method

A callback should generally call a single method, not inline a bunch of logic:

```ruby
# GOOD
included do
  after_create_commit :track_creation
end

private
  def track_creation
    track_event("created", board: card.board, creator: creator)
  end

# BAD
included do
  after_create_commit do
    board.events.create!(
      action: "comment_created",
      creator: creator,
      eventable: self,
      # ... lots of inline logic
    )
  end
end
```

The method name documents what the callback does. The method body can be tested independently. The callback block syntax should be reserved for truly trivial cases.

### Pattern: event_was_created Hook

We use a hook pattern for models to respond to events being created about them:

```ruby
class Event < ApplicationRecord
  after_create -> { eventable.event_was_created(self) }
end

module Card::Eventable
  def event_was_created(event)
    transaction do
      create_system_comment_for(event)
      touch_last_active_at unless was_just_published?
    end
  end
end
```

This inverts the dependency: instead of the Event model knowing about all the things that might care about events, each eventable model implements the hook if it cares.

## Testing Callbacks

### Test the Behavior, Not the Callback

Don't test that the callback is registered. Test that the behavior happens:

```ruby
# DON'T DO THIS
test "has after_create_commit callback for notify_recipients_later" do
  assert Comment.new.respond_to?(:notify_recipients_later)
end

# DO THIS
test "notifies recipients when created" do
  assert_difference -> { Notification.count }, 1 do
    comments(:one).card.comments.create!(
      body: "Hello",
      creator: users(:david)
    )
  end
end
```

The second test verifies that the actual business requirement (notifications are sent) works, regardless of whether it's implemented with a callback or not.

### Test the Delegated Logic in Isolation

If your callback delegates to a domain object, test that object thoroughly:

```ruby
class Notifier::CommentEventNotifierTest < ActiveSupport::TestCase
  test "notifies card watchers" do
    event = events(:david_commented)
    notifier = Notifier::CommentEventNotifier.new(event)

    assert_difference -> { Notification.count }, 2 do
      notifier.notify
    end
  end
end
```

This tests the notifier logic without needing to trigger callbacks, create records, or deal with timing issues.

## Common Pitfalls

### Pitfall: Callbacks That Depend on Each Other

```ruby
# DON'T DO THIS
class Card < ApplicationRecord
  after_save :update_board_cache
  after_save :notify_watchers  # depends on board_cache being updated!
end
```

If you find yourself depending on callback execution order, you're doing it wrong. Either:
1. Combine them into one callback that does things in the right order
2. Make the dependency explicit in the code
3. Reconsider whether these should be callbacks at all

### Pitfall: Conditional Creation Without Callbacks

```ruby
# DON'T DO THIS
def create_comment
  @comment = Comment.new(comment_params)
  @comment.skip_callbacks = true  # No!
  @comment.save!
  # manually do the things the callback would have done
end
```

If you're skipping callbacks, you're fighting the framework. Either:
1. Add conditional logic to the callback (`:if`, `:unless`)
2. Add an option to the callback method (`skip_event: true`)
3. Reconsider whether the callback is appropriate

### Pitfall: Callbacks That Create Records

```ruby
# BE CAREFUL WITH THIS
class User < ApplicationRecord
  after_create :create_default_settings

  def create_default_settings
    Setting.create!(user: self, ...)  # This can cause issues
  end
end
```

Callbacks that create additional records are risky because:
1. They can trigger more callbacks (callback chains)
2. They can cause transaction issues
3. They make testing harder (more records to clean up)

Consider using `after_commit` and being very explicit about what's happening.

## The Bottom Line

Callbacks are a tool. Like any tool, they can be used well or poorly.

Use them when you want to say "whenever X happens, do Y" and you want that behavior to apply universally. Use them for cross-cutting concerns that should always happen.

Don't use them to orchestrate complex workflows or chain together multi-step processes. For that, be explicit.

Keep callbacks simple. Delegate complexity to domain objects. Test behavior, not implementation.

And above all, be **mindful**. Think about whether a callback is the right tool for the job. Sometimes it is. Sometimes it isn't. Both are fine—as long as you're making the choice consciously.
