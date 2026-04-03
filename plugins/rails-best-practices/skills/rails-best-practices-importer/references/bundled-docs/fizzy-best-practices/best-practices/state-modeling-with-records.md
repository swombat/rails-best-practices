# State Modeling with Records: Boolean Columns vs. Separate Records

## The Question

When modeling state in Rails applications, you face a common choice: should you use a boolean column on the parent model, or create a separate associated record?

```ruby
# Option 1: Boolean column
class Card < ApplicationRecord
  # closed: boolean
end

card.closed?
card.update(closed: true)

# Option 2: Separate record
class Card < ApplicationRecord
  has_one :closure
end

card.closure.present?
card.create_closure!
```

**The short answer: Both are valid.** A boolean column is totally fine for many cases. But there are compelling reasons to prefer separate records, and understanding these reasons will help you write more maintainable, extensible Rails applications.

## When Boolean Columns Are Fine

Let's be clear: don't overcomplicate things. Boolean columns are perfectly appropriate when:

- You have simple on/off state with no additional context
- You don't need to know *when* the state changed
- You don't need to know *who* changed the state
- The state won't evolve to need additional metadata
- The boolean isn't used in complex filter combinations

If your needs are simple, keep it simple. Use a boolean column and move on.

## Four Compelling Reasons to Use Separate Records

### 1. You Get Timestamps for Free

The most immediate benefit: `created_at` tells you exactly when the state changed. No additional columns needed.

```ruby
class Card::Closeable
  has_one :closure

  def closed_at
    closure&.created_at
  end
end
```

Compare this to the boolean approach, where you'd need to add a separate `closed_at` column. And if you need to track *who* made the change, you get that for free too with a `user_id` on the record:

```ruby
class Closure < ApplicationRecord
  belongs_to :card
  belongs_to :user, optional: true
end

card.closed_by  # closure&.user
card.closed_at  # closure&.created_at
```

This is particularly valuable for audit trails and user-facing features like "Closed 3 days ago by Jorge."

### 2. Extensibility with Additional Information

Records can evolve. What starts as a simple yes/no can grow richer over time.

A closure might need a reason:

```ruby
class Closure < ApplicationRecord
  belongs_to :card
  belongs_to :user, optional: true

  enum reason: {
    duplicate: "duplicate",
    wont_fix: "wont_fix",
    completed: "completed",
    invalid: "invalid"
  }
end

card.create_closure!(user: current_user, reason: :duplicate)
```

Or you might want rich text notes:

```ruby
class Closure < ApplicationRecord
  belongs_to :card
  has_rich_text :notes
end
```

With a boolean column, adding this information requires migrations on the parent table, potentially affecting a large table with millions of rows. With separate records, you're modifying smaller, focused tables. The parent `cards` table stays lean.

### 3. Consistency Across Similar Concepts

In Fizzy, cards have three similar state concepts:

- **Closeable** - Cards can be closed
- **Postponable** - Cards can be postponed ("not now")
- **Golden** - Cards can be marked as golden (important)

All three use the same pattern:

```ruby
# app/models/card/closeable.rb
has_one :closure

# app/models/card/postponable.rb
has_one :not_now, class_name: "Card::NotNow"

# app/models/card/golden.rb
has_one :goldness, class_name: "Card::Goldness"
```

This consistency creates a clear mental model. When you see `has_one :something`, you immediately understand it's representing optional state. When a new developer joins the team, they learn the pattern once and recognize it everywhere.

The alternative—mixing booleans and records—forces developers to remember which states are modeled which way. Was `closed` a boolean or a record? You have to check. Consistency is a gift to your future self and your teammates.

### 4. Filtering Efficiency and Composability

This is the most technical but perhaps most important reason: separate records with foreign key indexes are simpler and more composable than boolean columns with composite indexes.

#### The Problem with Boolean Columns

When you filter by multiple boolean columns, you need composite indexes, and the order matters:

```ruby
# Cards that are closed AND golden
Card.where(closed: true, golden: true)

# You need a composite index
add_index :cards, [:closed, :golden]

# But this doesn't help with
Card.where(closed: true, golden: false)
# Or
Card.where(closed: false, golden: true)
```

You end up needing multiple composite indexes, and it's easy to get the column ordering wrong. The query optimizer has to pick the right index, and performance can be unpredictable.

#### The Solution with Separate Records

With separate records, each association has its own foreign key index, and they compose cleanly:

```ruby
# Closed cards
Card.joins(:closure)

# Golden cards
Card.joins(:goldness)

# Closed AND golden cards
Card.joins(:closure).joins(:goldness)

# Closed but NOT golden cards
Card.joins(:closure).where.missing(:goldness)

# Open cards (not closed)
Card.where.missing(:closure)
```

Each `has_one` relationship gets a simple foreign key index on `card_id`. These indexes compose naturally—you can join on any combination without worrying about index order or creating multiple composite indexes.

This becomes especially valuable as you add more states. With three boolean columns, you might need 6+ composite indexes to cover common queries. With three `has_one` associations, you just need three simple indexes.

## The Pattern in Practice

Here's how this pattern looks in real Fizzy code.

### The State Record

Simple, focused, minimal:

```ruby
class Closure < ApplicationRecord
  belongs_to :account, default: -> { card.account }
  belongs_to :card, touch: true
  belongs_to :user, optional: true
end
```

The migration:

```ruby
create_table :closures, id: :uuid do |t|
  t.belongs_to :account, null: false, type: :uuid
  t.belongs_to :card, null: false, type: :uuid, index: { unique: true }
  t.belongs_to :user, type: :uuid
  t.timestamps
end
```

Note the unique index on `card_id`—a card can only have one closure. This enforces the `has_one` relationship at the database level.

### The Concern

Extract the behavior into a reusable concern:

```ruby
module Card::Closeable
  extend ActiveSupport::Concern

  included do
    has_one :closure, dependent: :destroy

    scope :closed, -> { joins(:closure) }
    scope :open, -> { where.missing(:closure) }
    scope :recently_closed_first, -> { closed.order(closures: { created_at: :desc }) }
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

This concern provides:

- **Scopes** for querying closed/open cards
- **Predicate methods** for checking state
- **Accessor methods** for related data (who closed it, when)
- **Action methods** for changing state

### The Controller

Controllers stay thin, calling intention-revealing domain methods:

```ruby
class Cards::ClosuresController < ApplicationController
  include CardScoped

  def create
    @card.close(user: Current.user)
    redirect_to @card
  end

  def destroy
    @card.reopen(user: Current.user)
    redirect_to @card
  end
end
```

Notice how we model closing/reopening as CRUD operations on the `Closure` resource:

```ruby
# routes.rb
resources :cards do
  resource :closure, only: [:create, :destroy]
end

# URLs
POST   /cards/123/closure    # Close the card
DELETE /cards/123/closure    # Reopen the card
```

This is RESTful thinking at its finest: creating and destroying state records rather than custom actions.

## More Examples from Fizzy

### Goldness (Golden Cards)

```ruby
module Card::Golden
  extend ActiveSupport::Concern

  included do
    has_one :goldness, dependent: :destroy, class_name: "Card::Goldness"
    scope :golden, -> { joins(:goldness) }
  end

  def golden?
    goldness.present?
  end

  def gild
    create_goldness! unless golden?
  end

  def ungild
    goldness&.destroy
  end
end
```

The vocabulary is delightful. `card.gild` reads like English. The domain model speaks the language of the business.

### Not Now (Postponed Cards)

```ruby
module Card::Postponable
  extend ActiveSupport::Concern

  included do
    has_one :not_now, dependent: :destroy, class_name: "Card::NotNow"

    scope :postponed, -> { open.published.joins(:not_now) }
    scope :active, -> { open.published.where.missing(:not_now) }
  end

  def postponed?
    open? && published? && not_now.present?
  end

  def postponed_at
    not_now&.created_at
  end

  def postponed_by
    not_now&.user
  end

  def postpone(user: Current.user, event_name: :postponed)
    transaction do
      send_back_to_triage(skip_event: true)
      reopen
      activity_spike&.destroy
      create_not_now!(user: user) unless postponed?
      track_event event_name, creator: user
    end
  end

  def resume
    transaction do
      reopen
      activity_spike&.destroy
      not_now&.destroy
    end
  end
end
```

Notice how postponing involves coordinating multiple state changes in a transaction. Having separate records for each state makes this orchestration clear and explicit.

## Querying Patterns

### Basic Queries

```ruby
# All closed cards
Card.closed

# All open cards
Card.open

# Closed in the last week
Card.closed_at_window(1.week.ago..)

# Closed by specific users
Card.closed_by([user1, user2])
```

### Combining States

```ruby
# Closed and golden
Card.closed.golden

# Postponed but not golden
Card.postponed.where.missing(:goldness)

# Active (open, published, not postponed)
Card.active

# Recently closed golden cards
Card.golden.recently_closed_first
```

### Complex Filters

This is where the pattern really shines. You can compose filters without worrying about index optimization:

```ruby
# All golden cards that are either closed or postponed
Card.golden.where("closures.id IS NOT NULL OR card_not_nows.id IS NOT NULL")
  .left_joins(:closure, :not_now)

# Active cards (open, not postponed) that are golden
Card.active.golden

# Cards closed by a specific user that are also golden
Card.closed_by(user).golden
```

The database has simple indexes on `closures.card_id`, `card_goldnesses.card_id`, and `card_not_nows.card_id`. These compose efficiently without additional composite indexes.

## Migration Path

If you have existing boolean columns and want to migrate:

```ruby
class ConvertClosedToClosures < ActiveRecord::Migration[7.1]
  def up
    create_table :closures, id: :uuid do |t|
      t.belongs_to :account, null: false, type: :uuid
      t.belongs_to :card, null: false, type: :uuid, index: { unique: true }
      t.belongs_to :user, type: :uuid
      t.timestamps
    end

    # Migrate existing data
    Card.where(closed: true).find_each do |card|
      Closure.create!(
        card: card,
        account: card.account,
        created_at: card.closed_at || card.updated_at
      )
    end

    # Remove old column (after verifying migration)
    # remove_column :cards, :closed
    # remove_column :cards, :closed_at
  end
end
```

Run this migration carefully with a backup. Test thoroughly before removing the old columns.

## Guidelines for Choosing

Use a **boolean column** when:

- Simple on/off state
- No timestamp needed
- No additional metadata
- Not used in complex filter combinations
- Unlikely to evolve

Use a **separate record** when:

- You need to know when the state changed
- You need to know who made the change
- The state might need additional attributes later
- You're building a family of related state concepts
- You'll be combining multiple state filters in queries

When in doubt, start simple with a boolean. You can always refactor to records later if needs evolve. But if you're building something that feels like it might grow, or if you already have similar patterns in your codebase, reach for the separate record pattern from the start.

## Conclusion

State modeling with separate records isn't about being clever or following dogma. It's about creating code that:

- **Reveals intention** through consistent patterns
- **Accommodates change** without table rewrites
- **Composes cleanly** in queries
- **Tells its own story** through timestamps and associations

In Fizzy, when you see `has_one :closure`, `has_one :goldness`, `has_one :not_now`, you immediately understand the pattern. The code reads like the product it implements. That's the goal.

Choose the approach that makes your code clearer and more maintainable. Sometimes that's a boolean column. Often, it's a separate record. Let the needs of your application guide you, but understand the tradeoffs you're making.

Write code you'll be proud to read in six months.
