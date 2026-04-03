# Using Rails Concerns for Organization

This document describes the 37signals approach to using Rails concerns, based on the architecture of Fizzy. This isn't about the traditional debate of "concerns vs. services" but rather about using concerns as a powerful organizational tool for managing complexity in Rails applications.

## Two Distinct Uses for Concerns

Concerns serve two fundamentally different purposes:

1. **Organizing behavior** - Breaking down large domain models into cohesive units
2. **Reusing code** - Sharing behavior across multiple classes

Both are legitimate. Both are useful. Understanding when to use each is key.

## Organizing Large API Surfaces

### The Problem: Central Entities Grow Large

In any non-trivial Rails application, certain models become central to the domain. In Fizzy, these are `Card`, `Board`, and `User`. These models accumulate behavior rapidly:

```ruby
class Card < ApplicationRecord
  include Assignable, Attachments, Broadcastable, Closeable, Colored, Entropic, Eventable,
    Exportable, Golden, Mentions, Multistep, Pinnable, Postponable, Promptable,
    Readable, Searchable, Stallable, Statuses, Storage::Tracked, Taggable, Triageable, Watchable

  belongs_to :account
  belongs_to :board
  belongs_to :creator, class_name: "User"

  has_many :comments, dependent: :destroy
  has_one_attached :image

  # ...and so on
end
```

Without concerns, this would be a 2000+ line file. That's manageable for reading, but organizing becomes difficult.

### The Solution: Concerns as Traits

Each concern represents a distinct trait or capability of the card:

```
app/models/card/
├── triageable.rb      # Everything about triage workflow
├── postponable.rb     # Everything about postponing cards
├── stallable.rb       # Everything about detecting stalled cards
├── closeable.rb       # Everything about closing/reopening
├── entropic.rb        # Everything about auto-postponement
└── ...
```

This isn't just code splitting for the sake of smaller files. It's **semantic organization** - grouping related concepts together.

### Anatomy of a Well-Organized Concern

Let's examine `Card::Triageable` as a model example:

```ruby
module Card::Triageable
  extend ActiveSupport::Concern

  included do
    belongs_to :column, optional: true, touch: true

    scope :awaiting_triage, -> { active.where.missing(:column) }
    scope :triaged, -> { active.joins(:column) }
  end

  def triaged?
    active? && column.present?
  end

  def awaiting_triage?
    active? && !triaged?
  end

  def triage_into(column)
    raise "The column must belong to the card board" unless board == column.board

    transaction do
      resume
      update! column: column
      track_event "triaged", particulars: { column: column.name }
    end
  end

  def send_back_to_triage(skip_event: false)
    transaction do
      resume
      update! column: nil
      track_event "sent_back_to_triage" unless skip_event
    end
  end
end
```

Notice what's grouped together:

- The **association** (`belongs_to :column`)
- The **scopes** for querying triaged/untriaged cards
- The **query methods** (`triaged?`, `awaiting_triage?`)
- The **command methods** (`triage_into`, `send_back_to_triage`)

Everything related to the concept of "triage" lives in one place. When you need to change how triage works, you know exactly where to look.

### Cohesiveness is the Goal

The key principle: **related things should live together**.

Consider this scenario: you need to change what it means for a card to be "triaged". Maybe the logic should consider additional state beyond just having a column.

In a well-organized concern, you can change both the scope and the query method at the same time:

```ruby
scope :triaged, -> { active.joins(:column).where(triaged_manually: true) }

def triaged?
  active? && column.present? && triaged_manually?
end
```

Both the query interface (`Card.triaged`) and the instance check (`card.triaged?`) are right there together. You don't have to hunt through a 2000-line file, jumping between method definitions separated by hundreds of lines.

This is what makes the codebase **easier to understand and maintain**.

### Example: The Closeable Concern

Another clean example is `Card::Closeable`:

```ruby
module Card::Closeable
  extend ActiveSupport::Concern

  included do
    has_one :closure, dependent: :destroy

    scope :closed, -> { joins(:closure) }
    scope :open, -> { where.missing(:closure) }

    scope :recently_closed_first, -> { closed.order(closures: { created_at: :desc }) }
    scope :closed_at_window, ->(window) { closed.where(closures: { created_at: window }) }
    scope :closed_by, ->(users) { closed.where(closures: { user_id: Array(users) }) }
  end

  def closed?
    closure.present?
  end

  def open?
    !closed?
  end

  def closed_by
    closure&.user
  end

  def closed_at
    closure&.created_at
  end

  def close(user: Current.user)
    unless closed?
      transaction do
        create_closure! user: user
        track_event :closed, creator: user
      end
    end
  end

  def reopen(user: Current.user)
    if closed?
      transaction do
        closure&.destroy
        track_event :reopened, creator: user
      end
    end
  end
end
```

Everything about closing and opening cards is here:
- The data model (`has_one :closure`)
- Query scopes for finding closed/open cards
- State checks (`closed?`, `open?`)
- Metadata accessors (`closed_by`, `closed_at`)
- State transitions (`close`, `reopen`)

### Testing Follows the Same Structure

Tests mirror the concern organization:

```
test/models/card/
├── triageable_test.rb
├── postponable_test.rb
├── stallable_test.rb
├── closeable_test.rb
├── entropic_test.rb
└── ...
```

When you're working on triage behavior, you edit `app/models/card/triageable.rb` and test it in `test/models/card/triageable_test.rb`. Everything is organized the same way.

## Concerns Are Lightweight

One of the key advantages of concerns over other organizational patterns (like service objects, decorators, or strategy objects) is that they're **lightweight**.

There's no new hierarchy of objects. No wrapper objects. No delegation overhead. Just a single file injecting behavior directly into the class.

This keeps your mental model simple:

```ruby
card = Card.find(123)
card.triage_into(column)  # Just a method on card, no wrapper needed
```

You're still working with the core domain object. The concerns are simply organizing its interface into manageable chunks.

## Concerns Work WITH Object Composition

Here's a crucial insight: **concerns are not opposed to object-oriented design**. They complement it beautifully.

Concerns can serve as the entry point for behavior that then delegates to a system of well-designed objects.

### Example: Stallable Delegates to a Detector

The `Card::Stallable` concern provides the high-level interface:

```ruby
module Card::Stallable
  extend ActiveSupport::Concern

  STALLED_AFTER_LAST_SPIKE_PERIOD = 14.days

  included do
    has_one :activity_spike, class_name: "Card::ActivitySpike", dependent: :destroy

    scope :with_activity_spikes, -> { joins(:activity_spike) }
    scope :stalled, -> {
      open.active.with_activity_spikes
        .where(card_activity_spikes: { updated_at: ..STALLED_AFTER_LAST_SPIKE_PERIOD.ago })
    }

    before_update :remember_to_detect_activity_spikes
    after_update_commit :detect_activity_spikes_later, if: :should_detect_activity_spikes?
  end

  def stalled?
    if activity_spike.present?
      open? && last_activity_spike_at < STALLED_AFTER_LAST_SPIKE_PERIOD.ago
    end
  end

  def detect_activity_spikes
    Card::ActivitySpike::Detector.new(self).detect
  end

  # ... private methods omitted
end
```

The concern provides the card-level interface. But the complex logic of detecting activity spikes lives in a dedicated object:

```ruby
class Card::ActivitySpike::Detector
  attr_reader :card

  def initialize(card)
    @card = card
  end

  def detect
    if has_activity_spike?
      register_activity_spike
      true
    else
      false
    end
  end

  private
    def has_activity_spike?
      card.entropic? && (
        multiple_people_commented? ||
        card_was_just_assigned? ||
        card_was_just_reopened?
      )
    end

    def multiple_people_commented?(minimum_comments: 3, minimum_participants: 2)
      card.comments
        .where(created_at: recent_period.seconds.ago..)
        .group(:card_id)
        .having("COUNT(*) >= ?", minimum_comments)
        .having("COUNT(DISTINCT creator_id) >= ?", minimum_participants)
        .exists?
    end

    # ... more detection logic
end
```

The concern organizes the Card's API surface. The detector object encapsulates complex detection logic. Both working together.

### Example: Notifiable Delegates to a Hierarchy

The `Notifiable` concern is included by both `Event` and `Mention`:

```ruby
module Notifiable
  extend ActiveSupport::Concern

  included do
    has_many :notifications, as: :source, dependent: :destroy
    after_create_commit :notify_recipients_later
  end

  def notify_recipients
    Notifier.for(self)&.notify
  end

  def notifiable_target
    self
  end

  private
    def notify_recipients_later
      NotifyRecipientsJob.perform_later self
    end
end
```

This simple concern delegates to a hierarchy of `Notifier` classes that use the template method pattern:

```ruby
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

  # ... template methods for subclasses to override
end
```

The concern provides the uniform interface (`notify_recipients`). The notifier hierarchy handles the complexity of different notification types.

## When NOT to Use Concerns for Organization

Not every model needs to be broken into concerns.

Use concerns for organizing when:
- The model is a **central domain entity** with lots of behavior
- You can identify **distinct traits** or capabilities that group naturally
- The main class file is becoming **difficult to navigate** (500+ lines as a rough guideline)

Keep it simple when:
- The model is straightforward and behavior fits comfortably in one file
- Breaking it apart would make it **harder** to understand, not easier
- You're just splitting for the sake of splitting

Example: A `Card::Closure` model is just this:

```ruby
class Card::Closure < ApplicationRecord
  belongs_to :account, default: -> { card.account }
  belongs_to :card, touch: true
  belongs_to :user
end
```

No need for concerns here. It's a simple join model. Keep it simple.

## Concerns for Code Reuse

The second major use case for concerns is sharing behavior across multiple classes.

### Controller Example: CardScoped

Many controllers in Fizzy need to load a card and its board. Rather than repeating this setup, it's extracted to a concern:

```ruby
module CardScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_card, :set_board
  end

  private
    def set_card
      @card = Current.user.accessible_cards.find_by!(number: params[:card_id])
    end

    def set_board
      @board = @card.board
    end

    def render_card_replacement
      render turbo_stream: turbo_stream.replace(
        [@card, :card_container],
        partial: "cards/container",
        method: :morph,
        locals: { card: @card.reload }
      )
    end
end
```

This concern is included by 19 different controllers:

```ruby
class Cards::CommentsController < ApplicationController
  include CardScoped

  def create
    @comment = @card.comments.create!(comment_params)
    # @card and @board are already set
  end
end
```

This is straightforward code reuse. Nothing wrong with it. The concern provides a clean way to share setup logic.

### Model Example: BoardScoped

Similarly for boards:

```ruby
module BoardScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_board
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id])
    end

    def ensure_permission_to_admin_board
      unless Current.user.can_administer_board?(@board)
        head :forbidden
      end
    end
end
```

Used by multiple board-related controllers to share the same loading and authorization logic.

### Model-Level Reuse: Notifiable

The `Notifiable` concern we saw earlier is included by both `Event` and `Mention` - two different models that both need to notify users:

```ruby
class Event < ApplicationRecord
  include Notifiable
  # ...
end

class Mention < ApplicationRecord
  include Notifiable
  # ...
end
```

Both get the same notification behavior through the shared concern.

## Naming Conventions

Concerns typically use the `-able` suffix when they represent a trait or capability:

- `Triageable` - can be triaged
- `Postponable` - can be postponed
- `Closeable` - can be closed
- `Stallable` - can become stalled
- `Notifiable` - can send notifications
- `Searchable` - can be searched

This makes it clear that these are traits being mixed into the model.

For more specific concerns, use descriptive names that indicate their purpose:

- `CardScoped` - sets up card context
- `BoardScoped` - sets up board context
- `CurrentRequest` - tracks current request info

## File Organization

### Models

Concerns for a specific model go in a subdirectory:

```
app/models/
├── card.rb
└── card/
    ├── triageable.rb
    ├── postponable.rb
    ├── stallable.rb
    └── ...
```

Shared concerns go in the root concerns directory:

```
app/models/concerns/
├── eventable.rb
├── notifiable.rb
├── searchable.rb
└── ...
```

### Controllers

Controller concerns all go in one directory since they're typically shared:

```
app/controllers/concerns/
├── authentication.rb
├── authorization.rb
├── card_scoped.rb
├── board_scoped.rb
└── ...
```

## Summary: Principles for Using Concerns

1. **Concerns organize large domain models into cohesive units** - When a central model like `Card` has many capabilities, split them by trait (triageable, closeable, etc.)

2. **Cohesiveness is the goal** - Group related associations, scopes, query methods, and commands together. When you need to change a concept, everything should be in one place.

3. **Concerns are lightweight** - No new object hierarchies, no wrappers, no delegation overhead. Just organized methods on the main class.

4. **Concerns complement object composition** - Use concerns to organize the entry point, then delegate to well-designed object hierarchies for complex logic.

5. **Not everything needs concerns** - Simple models should stay simple. Only break into concerns when it genuinely makes the code easier to understand.

6. **Concerns enable reuse** - Share common controller setup, shared model capabilities, or cross-cutting functionality without duplication.

7. **Tests follow the same structure** - Organize tests to match concerns, making it easy to find and maintain related tests.

The 37signals approach to concerns isn't dogmatic. It's practical. Use them when they make your code clearer and more maintainable. Skip them when they don't. The goal is always the same: code that's a pleasure to read and easy to change.
