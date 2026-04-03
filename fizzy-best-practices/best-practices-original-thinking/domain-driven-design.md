# Domain-Driven Design: The 37signals/DHH Approach

## Overview

The architecture of Rails applications at 37signals centers on one core principle from Eric Evans' seminal book *Domain-Driven Design*: **make the domain model the central part of your application**. This isn't radical or revolutionary. It's about placing your effort where it matters most: making your code evoke the problem you're trying to solve.

When you read the code, it should reflect the behaviors and nouns you use when discussing the product. In a kanban tool, you should see `card.gild`, `card.send_back_to_triage`, `board.revise_accesses`. The domain model speaks the language of the business.

## The Central Principle: Rich Domain Models

Your domain model should contain the behavior, not just the data. This is the opposite of the "anemic domain model" anti-pattern that Martin Fowler identified in 2003. An anemic model is just a bag of getters and setters with all the interesting behavior scattered across service objects.

### What This Looks Like in Practice

```ruby
# Good: Rich domain model
class Card < ApplicationRecord
  def gild
    create_goldness!
  end

  def ungild
    goldness&.destroy
  end

  def send_back_to_triage
    transaction do
      resume
      update! column: nil
      track_event "sent_back_to_triage"
    end
  end

  def triage_into(column)
    raise "The column must belong to the card board" unless board == column.board

    transaction do
      resume
      update! column: column
      track_event "triaged", particulars: { column: column.name }
    end
  end
end
```

Notice how the methods read like product requirements. You can understand what the application does by reading the domain model. The behavior lives where it belongs: with the entity it concerns.

## Thin Controllers Exercising the Domain Model

Controllers connect the external world (web requests) to your domain model. They should be thin, orchestrating at a very high level.

### Controller Examples

Most controllers in a well-architected Rails application are one-liners:

```ruby
class Cards::GoldnessesController < ApplicationController
  include CardScoped

  def create
    @card.gild

    respond_to do |format|
      format.turbo_stream { render_card_replacement }
      format.json { head :no_content }
    end
  end

  def destroy
    @card.ungild

    respond_to do |format|
      format.turbo_stream { render_card_replacement }
      format.json { head :no_content }
    end
  end
end
```

```ruby
class Cards::TriagesController < ApplicationController
  include CardScoped

  def create
    column = @card.board.columns.find(params[:column_id])
    @card.triage_into(column)

    respond_to do |format|
      format.html { redirect_to @card }
      format.json { head :no_content }
    end
  end

  def destroy
    @card.send_back_to_triage

    respond_to do |format|
      format.html { redirect_to @card }
      format.json { head :no_content }
    end
  end
end
```

The controller's job is clear: extract parameters from the request, invoke domain logic, return a response. Nothing more.

### Simple CRUD Operations

For straightforward CRUD operations, vanilla Active Record is perfectly fine:

```ruby
class Cards::CommentsController < ApplicationController
  include CardScoped

  def create
    @comment = @card.comments.create!(comment_params)
    # respond...
  end

  def update
    @comment.update!(comment_params)
    # respond...
  end
end
```

Don't reach for complexity when simplicity suffices. If you're just storing a record in the database, Active Record's `create!` or `update!` does the job beautifully.

## The Service Objects Debate

Domain-Driven Design proposed service objects before Rails existed. The original proposal was for service objects to do exactly what Rails controllers already do: orchestrate domain entities at a high level and handle infrastructure concerns like persistence.

### The Right Way: Service Objects as Orchestrators

If you use service objects in the way DDD originally intended, they should be thin orchestrators:

```ruby
# This is acceptable (though redundant with Rails controllers)
class SendCardBackToTriage
  def initialize(card)
    @card = card
  end

  def call
    @card.send_back_to_triage
  end
end
```

But look at this code. You've replaced a one-liner with a whole class that... invokes the one-liner. This is why controllers already do this job. The service object adds boilerplate without meaningful benefit.

### The Wrong Way: Service Objects Implementing Domain Logic

The real problem with service objects is when people use them to implement business logic instead of orchestrating it:

```ruby
# BAD: Anemic domain model anti-pattern
class SendCardBackToTriage
  def initialize(card)
    @card = card
  end

  def call
    @card.resume  # Wait, now we need another service object for resume
    @card.update! column: nil
    @card.track_event "sent_back_to_triage"
  end
end
```

This creates an anemic domain model. Your `Card` class becomes a dumb data holder. All the interesting behavior scatters across service objects. You end up with a flat, long list of small operations that either don't reuse code or create tight coupling between service objects.

Eric Evans identified this problem in the original DDD book. Martin Fowler wrote about it in his famous 2003 article on anemic domain models. This isn't new wisdom. Yet developers keep falling into this trap.

### The Cognitive Disconnect

Here's the irony: developers reach for service objects to keep their models from violating the Single Responsibility Principle. But then they implement domain logic in the service layer, which violates the core principle of domain-driven design: putting behavior with data.

You end up with:
- Models that are just data bags
- Service objects tightly coupled to those models
- Scattered logic that's hard to find and reuse
- A maintenance nightmare

Don't do this.

## When Plain Ruby Objects Are Appropriate

Not all domain operations fit naturally on an entity. Sometimes you need a plain Ruby object to represent a domain operation. That's fine. But don't call it `XxxService` and don't use a generic `call` method.

### Domain Services: Plain Objects with Semantic Names

```ruby
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  attr_accessor :full_name, :email_address, :identity
  attr_reader :account, :user

  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, on: :identity_creation
  validates :full_name, :identity, presence: true, on: :completion

  def create_identity
    @identity = Identity.find_or_create_by!(email_address: email_address)
    @identity.send_magic_link for: :sign_up
  end

  def complete
    if valid?(:completion)
      @account = create_account
      @user = @account.users.find_by!(role: :owner)
      true
    else
      false
    end
  end

  private
    def create_account
      Account.create_with_owner(
        account: { name: generate_account_name },
        owner: { name: full_name, identity: identity }
      )
    end
end
```

Then use it with intention-revealing method names:

```ruby
# Good: Semantic, clear
Signup.new(email_address: email_address).create_identity

# Bad: Generic, unclear
SignupService.new(email_address: email_address).call
```

The difference matters. `Signup.new(...).create_identity` reads like English. You know what it does. `SignupService.new(...).call` is opaque. You have to look inside to understand it.

These are domain services in DDD terminology. They represent domain operations that don't belong to a single entity. Use them when appropriate. Just don't confuse them with application services (orchestrators) or use them as an excuse to hollow out your domain model.

## Background Jobs as Thin Orchestrators

Jobs are system boundaries, just like controllers. They should be thin, exercising the domain model asynchronously.

### Job Structure

```ruby
# Good: Thin job invoking domain logic
class Event::RelayJob < ApplicationJob
  def perform(event)
    event.relay_now
  end
end
```

The job's responsibility is clear: take a domain object, invoke its behavior. The actual relay logic lives in the `Event` model where it belongs.

### Enqueuing Pattern

Use a naming convention that makes the synchronous/asynchronous boundary clear:

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
    # Actual relay implementation
    webhooks.each do |webhook|
      deliver_to_webhook(webhook)
    end
  end
end
```

The `_later` suffix flags "this enqueues a job." The `_now` suffix flags "this is the synchronous version." The pattern is consistent and readable.

## Organizing Complex Domain Models with Concerns

As your domain models grow, they can become large. Use concerns to organize behavior into cohesive modules. This addresses the Single Responsibility Principle without scattering your domain logic.

### Concerns for Composing Traits

```ruby
# app/models/card.rb
class Card < ApplicationRecord
  include Triageable
  include Postponable
  include Closable
  include Goldable
  include Watchable
  # ... other traits
end
```

```ruby
# app/models/card/triageable.rb
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

### The Benefits of Concerns

**Cohesion**: Related code lives together. The `triaged?` query method, the `:triaged` scope, and the `triage_into` action are all in the same file. If you need to change the definition of "triaged," everything you need is right there.

**Organization**: Instead of a 2000-line `Card` class, you have 10 well-organized 200-line concerns. Each one has a clear purpose.

**Lightweight**: No new object hierarchies, no decorators, no wrappers. Just modules included into your class.

**Discoverability**: When you open `Card`, you immediately see what traits it has: `Triageable`, `Postponable`, `Closable`. The model's capabilities are self-documenting.

### Concerns for Code Reuse

You can also use concerns the traditional Ruby way: sharing code across classes.

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

Now both `Event` and `Mention` can include `Notifiable` and get notification behavior for free.

### When to Use Concerns

Don't use concerns everywhere reflexively. For models with moderate complexity, having a main class file is totally fine. Use concerns when:

1. The model is central to your domain (like `Card` or `Board`) and has substantial behavior
2. You have a trait with multiple related methods, scopes, and associations
3. You need to share behavior across multiple unrelated models
4. The concern improves cohesion by grouping related methods

### Concerns and Object Composition

Concerns don't replace object-oriented design. They work beautifully with it.

```ruby
module Notifiable
  # ... concern setup ...

  def notify_recipients
    Notifier.for(self)&.notify  # Delegates to a system of objects
  end
end
```

The concern provides a high-level interface. Behind that interface, you can use traditional OO patterns: template methods, strategy objects, factories, whatever fits. The concern organizes the external API. Object composition implements it.

## Callbacks: When They're the Right Tool

Callbacks are controversial because they can create hard-to-debug indirection. Used poorly, they create maintenance nightmares. Used well, they're elegant and powerful.

### Use Callbacks When They Match Human Reasoning

If you find yourself thinking "whenever a card changes, I want to detect activity spikes," that's a perfect callback:

```ruby
module Card::Stallable
  extend ActiveSupport::Concern

  included do
    after_update_commit :detect_activity_spikes_later
  end

  def detect_activity_spikes
    ActivitySpikeDetector.new(self).detect
  end

  private
    def detect_activity_spikes_later
      Card::DetectActivitySpikesJob.perform_later(self)
    end
end
```

This is good design. If you introduce a new way to update a card, activity spike detection keeps working. The behavior is coupled to the event (card updates), not to specific code paths.

### Use Callbacks for Cross-Cutting Concerns

```ruby
module Notifiable
  extend ActiveSupport::Concern

  included do
    after_create_commit :notify_recipients_later
  end

  # ...
end
```

Notifications are a cross-cutting concern. They should fire whenever a notifiable object is created, regardless of how. A callback ensures this happens consistently.

### Don't Use Callbacks for Complex Orchestration

Callbacks introduce indirection. If you chain multiple callbacks that trigger other callbacks, you'll lose track of the flow. Use explicit method calls for complex multi-step processes:

```ruby
# Good: Explicit orchestration
def send_back_to_triage(skip_event: false)
  transaction do
    resume
    update! column: nil
    track_event "sent_back_to_triage" unless skip_event
  end
end

# Bad: Hidden orchestration via cascading callbacks
# (Don't do this for multi-step business processes)
```

### The Rule: Callbacks Should Be Obviously Safe

A callback is well-designed when a programmer can reason: "Of course this should always happen when X occurs." If you have to trace through multiple layers to understand when a callback fires, it's probably the wrong tool.

## Practical Guidelines

### 1. Start with the Domain

Before writing controllers or services, ask: "What does this entity do?" Write methods on the entity that capture domain operations:

```ruby
card.postpone
card.resume
card.gild
card.ungild
card.send_back_to_triage
card.triage_into(column)
```

### 2. Controllers Exercise the Domain

Controllers should read like a table of contents for your application's capabilities. One-liners that invoke domain logic.

```ruby
def create
  @card.gild
  respond_to do |format|
    format.turbo_stream { render_card_replacement }
  end
end
```

### 3. Use Plain Objects Sparingly, Semantically

When you need a domain operation that doesn't fit on an entity, create a plain object with an intention-revealing name and method:

```ruby
Signup.new(...).create_identity
AccountNameGenerator.new(...).generate
ActivitySpikeDetector.new(card).detect
```

Not:

```ruby
SignupService.new(...).call
AccountNameService.new(...).call
ActivitySpikeService.new(card).call
```

### 4. Jobs Are Thin

Jobs exercise the domain model from system boundaries:

```ruby
class NotifyRecipientsJob < ApplicationJob
  def perform(notifiable)
    notifiable.notify_recipients
  end
end
```

### 5. Organize with Concerns, Implement with Objects

Use concerns to organize large domain models. Within those concerns, use object-oriented patterns:

```ruby
module Card::Stallable
  def detect_activity_spikes
    ActivitySpikeDetector.new(self).detect  # Delegates to a specialized object
  end
end
```

### 6. Test the Real Thing

Test your domain model through its public interface. Don't stub internals unless you must. Your tests should survive refactoring the implementation:

```ruby
test "triaging a card sets its column" do
  card.triage_into(columns(:doing))
  assert_equal columns(:doing), card.reload.column
end

test "sending card back to triage clears its column" do
  card.update! column: columns(:doing)
  card.send_back_to_triage
  assert_nil card.reload.column
end
```

## The Philosophy

The goal is code that's a pleasure to read. Code that makes you think "of course, that's how it should work." Code organized around the problem domain, not around architectural abstractions.

This isn't about avoiding abstractions. It's about using the right abstractions: the ones from your domain model. When someone asks "how does triaging work?" you should be able to point them to `card.triage_into(column)` and have the code tell the story.

Rails gives you powerful tools: Active Record, concerns, callbacks. Use them. Don't fight them by introducing service layers that recreate what Rails already provides.

Keep controllers thin. Keep jobs thin. Keep your domain model rich. That's the essence of vanilla Rails, and it's plenty.

## Common Anti-Patterns to Avoid

### Anti-Pattern 1: The God Service Object

```ruby
# BAD
class CardService
  def create(params) # ...
  def update(card, params) # ...
  def delete(card) # ...
  def gild(card) # ...
  def ungild(card) # ...
  def triage(card, column) # ...
  # ... 50 more methods
end
```

This is just a procedural module masquerading as a service. All the behavior belongs on `Card`.

### Anti-Pattern 2: The Anemic Model

```ruby
# BAD
class Card < ApplicationRecord
  # Just associations, scopes, and validations
  # No behavior
end

# All behavior scattered across services
class GildCardService
  def call(card)
    card.create_goldness!
  end
end

class UngildCardService
  def call(card)
    card.goldness&.destroy
  end
end
```

You've hollowed out your domain model. Stop it.

### Anti-Pattern 3: The Generic Call Method

```ruby
# BAD - What does this do?
SomeService.new(thing).call

# GOOD - Clear intention
Signup.new(...).create_identity
```

`call` tells you nothing. Use semantic names.

### Anti-Pattern 4: Service Objects for Simple CRUD

```ruby
# BAD - Unnecessary abstraction
class CreateCommentService
  def call(card, params)
    card.comments.create!(params)
  end
end

# GOOD - Direct and clear
@card.comments.create!(comment_params)
```

Don't add indirection where none is needed.

### Anti-Pattern 5: Callbacks for Complex Orchestration

```ruby
# BAD - Hard to follow, brittle
class Card
  after_update :maybe_update_related_stuff
  after_update :possibly_send_notifications
  after_update :check_if_should_do_something_else
  # Each callback has complex conditionals
end

# GOOD - Explicit when complexity warrants it
def close
  transaction do
    update! status: :closed
    postponements.destroy_all
    track_event "closed"
  end
end
```

## Conclusion

Domain-driven design isn't complicated. Put your domain model at the center. Make it rich with behavior. Connect it to the external world through thin controllers and jobs. Organize it with concerns. Implement it with objects.

That's vanilla Rails. And vanilla Rails is plenty.
