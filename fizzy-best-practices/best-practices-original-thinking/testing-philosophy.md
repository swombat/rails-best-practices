# Testing Philosophy: The 37signals Approach

## The Goal: Confidence, Not Coverage

Kent Beck got it right: **tests exist to give you confidence about your system**.

Everything else—speed, coverage metrics, TDD dogma, test pyramid diagrams—is secondary. These things matter, but only insofar as they contribute to confidence. The moment they become goals themselves, you've lost the plot.

A 100% test coverage badge means nothing if you're not confident deploying on Friday afternoon. A blazing-fast test suite that only tests trivial paths gives you false security. Tests that break every time you refactor internals erode confidence by making you afraid to improve the code.

**Good tests make you confident. Bad tests make you cautious.**

## Tests Are Not Free

This is the uncomfortable truth many developers ignore: tests cost time and money.

They cost time to write. More importantly, **they cost time to maintain**. Every test you write is code you're committing to maintain. It will need updating when requirements change. It will need fixing when you refactor. It will slow down your test suite.

Bad tests cost even more. Tests that are brittle, slow, or unclear make the entire team less productive. They create friction against refactoring. They make developers dread running the suite. They fail for unclear reasons and waste everyone's time.

Be deliberate about what you test. Ask yourself: "Will this test give me enough confidence to justify its maintenance burden?" If the answer is no, don't write it.

## Prefer Integrated Tests

Test the real thing.

Don't test a mock. Don't test a stub. Don't test a carefully constructed test double that behaves almost like the real object except in the ways you've decided to fake.

**Exercise the full stack. Observe the system as a black box. Interact with it, observe outcomes.**

### What This Looks Like

In a Rails application, this means controller tests that exercise actual HTTP endpoints:

```ruby
class Cards::TriagesControllerTest < ActionController::TestCase
  include CardScoped

  test "triaging a card assigns it to a column" do
    card = cards(:inbox_card)
    column = columns(:doing)

    post :create, params: {
      account_id: @account.id,
      card_id: card.id,
      column_id: column.id
    }

    assert_equal column, card.reload.column
    assert_redirected_to card_path(card)
  end

  test "triaging creates an event" do
    card = cards(:inbox_card)
    column = columns(:doing)

    assert_difference -> { card.events.count }, +1 do
      post :create, params: {
        account_id: @account.id,
        card_id: card.id,
        column_id: column.id
      }
    end

    event = card.events.last
    assert_equal "triaged", event.action
    assert_equal column.name, event.particulars["column"]
  end
end
```

Look at what we're checking:

- **Database modifications**: Did the card's column actually change?
- **Side effects**: Did we create the expected event?
- **HTTP responses**: Did we redirect correctly?

We're not stubbing `Card#triage_into`. We're calling the controller action, which hits the router, instantiates the controller, loads the card from the database, calls the domain method, commits the transaction, and returns a response.

That's confidence.

### Model Tests Follow the Same Philosophy

```ruby
class CardTest < ActiveSupport::TestCase
  test "triaging into a column sets the column" do
    card = cards(:inbox_card)
    column = columns(:doing)

    card.triage_into(column)

    assert_equal column, card.reload.column
    assert card.active?
    assert card.triaged?
  end

  test "cannot triage into a column from a different board" do
    card = cards(:inbox_card)
    other_board_column = columns(:other_board_doing)

    assert_raises(RuntimeError) do
      card.triage_into(other_board_column)
    end
  end

  test "triaging resumes a postponed card" do
    card = cards(:postponed_card)
    column = columns(:doing)

    card.triage_into(column)

    assert card.active?
    refute card.postponed?
  end
end
```

We're testing the public interface. We call `triage_into`, then check observable outcomes in the database. We don't care how it works internally. We care that it works.

## Avoid Stubbing Internals

Here's a smell: if changing a private method breaks your tests, your tests are too coupled to the implementation.

**Tests should survive refactoring.**

When you stub internal methods, you're making implicit assertions about how the code works. You're saying "I expect this method to call that method." Now when you refactor and change which internal methods get called, your tests break even though the behavior didn't change.

This is backwards. Tests should let you refactor with confidence, not punish you for it.

### When Stubbing Is Necessary

Sometimes you must stub. When you're interacting with external systems—APIs, payment processors, email services—you don't want your tests making real HTTP calls.

```ruby
test "relaying an event delivers to webhook" do
  webhook = webhooks(:active_webhook)
  event = events(:card_published)

  stub_request(:post, webhook.url)
    .with(body: hash_including(action: "card_published"))
    .to_return(status: 200)

  event.relay_now

  assert_requested :post, webhook.url
end
```

This is pragmatic. We stub the HTTP call because we're not trying to test Stripe's or Slack's servers. We're testing that our code makes the right request.

But notice: we're stubbing an **external boundary**, not an internal method. We're not stubbing `Event#prepare_webhook_payload` or some other internal detail. If we refactor how we build the payload, this test keeps working.

### The Rule

Stub only what you must: external dependencies you don't control. Everything else, test the real implementation.

## What to Test

### Controller Tests (Integration Tests)

These are your bread and butter. Every endpoint should have tests that:

- **Exercise the full request/response cycle**
- **Check database modifications**
- **Verify HTTP responses** (status codes, redirects, JSON structure)
- **Confirm side effects** (emails queued, jobs enqueued, events created)

```ruby
class Cards::GoldnessesControllerTest < ActionController::TestCase
  test "gilding a card creates goldness" do
    card = cards(:inbox_card)

    assert_difference -> { Goldness.count }, +1 do
      post :create, params: { account_id: @account.id, card_id: card.id }
    end

    assert card.reload.golden?
  end

  test "gilding enqueues notification job" do
    card = cards(:inbox_card)

    assert_enqueued_with(job: NotifyRecipientsJob) do
      post :create, params: { account_id: @account.id, card_id: card.id }
    end
  end
end
```

### Model Tests

Test domain behavior through the public interface:

```ruby
class Card::PostponableTest < ActiveSupport::TestCase
  test "postponing a card changes its status" do
    card = cards(:active_card)

    card.postpone

    assert card.postponed?
    refute card.active?
  end

  test "postponing clears the column" do
    card = cards(:triaged_card)
    original_column = card.column

    card.postpone

    assert_nil card.reload.column
  end

  test "resuming a postponed card makes it active" do
    card = cards(:postponed_card)

    card.resume

    assert card.active?
    refute card.postponed?
  end
end
```

### What About View Tests?

We rarely check view content directly. Here's why:

**Designers iterate on views constantly.** After a feature ships, they refine the markup, adjust classes, try different layouts. If tests assert on specific HTML structure or CSS classes, every design iteration breaks tests.

The tests become friction against the very thing we want to encourage: continuous improvement of the interface.

Instead, we test views through integration tests. We verify that the right data flows through the system. We trust that if the wrong data reaches the view, someone will notice in development or staging.

This isn't cavalier. It's pragmatic. The lack of direct view tests has never been a recurring source of bugs. When something breaks in a view, it's obvious—you see it in the browser.

### The Rare Exception

Sometimes you really do need to check view output. At 37signals, we've hit storage limits where we needed to verify the UI correctly shows warnings and prevents actions.

Testing this required both stubbing (to simulate being over quota) and view assertions (to verify the warnings appear):

```ruby
test "shows storage warning when over limit" do
  @account.stub(:over_storage_limit?, true) do
    get :new, params: { account_id: @account.id }

    assert_select ".storage-warning",
      text: /storage limit/
    assert_select "input[type=submit][disabled]"
  end
end
```

This breaks our guidelines. We're stubbing an internal method. We're asserting on HTML structure. But it gives us confidence about a critical business constraint that would be hard to test otherwise.

**Know the guidelines. Break them when justified.**

## System Tests: A Tradeoff We Didn't Take

System tests (Capybara + browser automation) provide value. They exercise your entire stack including JavaScript, CSS, and user interactions. They're the closest thing to a user clicking through your app.

But they have serious costs:

- **Slow to write**: Setting up page objects, dealing with timing issues, handling JavaScript edge cases
- **Slow to run**: Spinning up a browser, rendering pages, waiting for animations
- **Brittle**: Break when CSS classes change, when timing changes, when you refactor the DOM

We ran system tests for a while in Fizzy. Eventually, we decided they weren't worth the tradeoff.

The confidence they provided wasn't proportional to the pain they caused. The tests were slow. They were flaky. They broke when designers iterated on the UI. They became a tax on productivity.

We deleted them.

Now we rely on controller tests for confidence and manual testing for UI behavior. This works because:

1. **Our controller tests are thorough.** They verify data flows correctly through the system.
2. **We ship continuously.** Features go to production quickly where real users catch issues.
3. **We fix bugs fast.** A bug in production gets fixed the same day, often within hours.

Your calculus might differ. If you're in a regulated industry where bugs are catastrophic, system tests might be worth it. If you ship infrequently, they might catch issues before they sit in a queue for weeks.

But don't write system tests out of obligation. Write them if they give you confidence proportional to their cost.

## Fixtures Over Factories

This is a hill worth dying on: **fixtures are vastly superior to factories for most Rails applications.**

### The Speed Difference

Factories create records on every test run. Even with sophisticated transactional fixtures and database parallelization, you're executing SQL inserts for every test.

Fixtures dump data once at test suite start, then roll back changes after each test. The difference in speed is dramatic:

```
# With FactoryBot
Time: 00:03:24, Memory: 450 MB

# With fixtures
Time: 00:00:42, Memory: 180 MB
```

That's not exaggeration. That's real data from refactoring a medium-sized Rails app.

### Fixtures as Realistic Data

A common objection: "Fixtures become a tangled mess of global state!"

This happens when you treat fixtures as test setup instead of realistic seed data.

**Build fixtures that make sense as user data.**

```yaml
# cards.yml
inbox_card:
  account: acme
  board: engineering
  title: "Fix login bug"
  description: "Users can't log in with magic links"
  status: active
  created_at: <%= 2.days.ago %>

triaged_card:
  account: acme
  board: engineering
  column: doing
  title: "Add dark mode"
  description: "Support dark mode in settings"
  status: active
  created_at: <%= 1.week.ago %>

postponed_card:
  account: acme
  board: engineering
  title: "Refactor authentication"
  description: "Clean up auth module"
  status: postponed
  created_at: <%= 2.weeks.ago %>
```

These fixtures tell a story. You can read them and understand the state of the system. When you write a test, you grab the fixture that represents the scenario you're testing:

```ruby
test "triaging moves card to column" do
  card = cards(:inbox_card)
  column = columns(:doing)

  card.triage_into(column)

  assert_equal column, card.reload.column
end
```

Clear. Fast. No factory setup. No mysterious `create(:card, :with_associations, :in_some_state)` calls.

### Fixtures as Development Seed Data

Here's a bonus: use your fixtures for development too.

```bash
bin/rails db:fixtures:load
```

Now your development database has realistic data. You can click around and see how the UI handles different states. Designers can work with representative content instead of lorem ipsum.

Your test data and development data stay in sync. If you add a new fixture for a test, it appears in development. If a designer needs a specific state for UI work, they add a fixture that tests can also use.

### When Fixtures Fall Short

Sometimes you do need to create records in tests. When you're testing creation logic or you need hundreds of variations, factories (or just `Card.create!`) make sense.

```ruby
test "automatically postpones stale cards" do
  # Create a bunch of old cards
  10.times do |i|
    Card.create!(
      account: @account,
      board: boards(:engineering),
      title: "Old card #{i}",
      status: :active,
      updated_at: 31.days.ago
    )
  end

  Card.postpone_stale_cards

  assert_equal 10, @account.cards.postponed.count
end
```

This is fine. Use the right tool for the job. Just don't reach for factories by default when fixtures would work better.

## No Hardcore Rules

Everything in this document is a guideline, not a law.

Sometimes you need to stub internal methods. Sometimes you need to check HTML output. Sometimes you need to create records instead of using fixtures.

**Be pragmatic when confidence requires it.**

The goal is confidence. If a test gives you confidence about critical behavior and requires breaking a guideline, break it. Just know why you're breaking it.

### Questions to Ask

When deciding how to test something:

1. **Does this test give me confidence?** If not, don't write it.

2. **Will this test survive refactoring?** If it breaks when you rename a private method, it's too coupled.

3. **Is the maintenance burden worth it?** Slow, brittle tests erode confidence over time.

4. **Am I testing the real thing?** Prefer integration over unit tests with mocks.

5. **Could I use a fixture instead of creating records?** Speed matters.

## Examples from Fizzy

### Testing Card Triage

```ruby
# Controller test - exercises the full stack
class Cards::TriagesControllerTest < ActionController::TestCase
  test "triaging a card works" do
    card = cards(:inbox_card)
    column = columns(:doing)

    post :create, params: {
      account_id: @account.id,
      card_id: card.id,
      column_id: column.id
    }

    assert_equal column, card.reload.column
    assert_redirected_to card_path(card)
  end
end

# Model test - checks domain behavior
class Card::TriageableTest < ActiveSupport::TestCase
  test "can triage into board column" do
    card = cards(:inbox_card)
    column = columns(:doing)

    card.triage_into(column)

    assert_equal column, card.reload.column
    assert card.triaged?
  end

  test "cannot triage into different board column" do
    card = cards(:inbox_card)
    other_column = columns(:other_board_doing)

    error = assert_raises(RuntimeError) do
      card.triage_into(other_column)
    end

    assert_match /must belong to the card board/, error.message
  end
end
```

### Testing Event Webhooks

```ruby
class Event::RelayingTest < ActiveSupport::TestCase
  test "relaying delivers to active webhooks" do
    event = events(:card_published)
    webhook = webhooks(:active_webhook)

    # Stub the external HTTP call
    stub_request(:post, webhook.url)
      .with(body: hash_including(
        action: "card_published",
        card_id: event.card.id
      ))
      .to_return(status: 200)

    event.relay_now

    # Verify we made the request
    assert_requested :post, webhook.url

    # Verify we recorded the delivery
    delivery = webhook.deliveries.last
    assert_equal event, delivery.event
    assert_equal 200, delivery.response_code
  end

  test "does not deliver to inactive webhooks" do
    event = events(:card_published)
    webhook = webhooks(:inactive_webhook)

    event.relay_now

    # Should not have made any HTTP requests
    assert_not_requested :post, webhook.url
  end
end
```

### Testing Background Jobs

```ruby
class Card::DetectActivitySpikesJobTest < ActiveJob::TestCase
  test "enqueues after card update" do
    card = cards(:active_card)

    assert_enqueued_with(job: Card::DetectActivitySpikesJob, args: [card]) do
      card.update!(title: "New title")
    end
  end

  test "detects activity spike" do
    card = cards(:stale_card)

    # Create a bunch of recent events
    5.times { card.events.create!(action: "card_commented", creator: users(:david)) }

    Card::DetectActivitySpikesJob.perform_now(card)

    assert card.reload.has_activity_spike?
  end
end
```

## The Philosophy

Write tests that make you confident about deploying to production.

Don't write tests because you're supposed to. Don't chase coverage metrics. Don't follow TDD dogmatically. Don't build elaborate mock hierarchies.

Write tests that exercise the real system. Tests that check observable outcomes. Tests that survive refactoring. Tests that are fast enough to run constantly.

And when a test doesn't give you confidence proportional to its cost, delete it.

Your test suite should make you feel safe. If it doesn't, you're doing it wrong.
