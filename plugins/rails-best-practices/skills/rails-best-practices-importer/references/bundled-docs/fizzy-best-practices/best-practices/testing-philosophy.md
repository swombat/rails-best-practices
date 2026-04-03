# Testing Philosophy

This document is a portable Rails testing reference. The central idea is simple: prefer tests that exercise the real application stack, use smaller tests for dense domain logic, and reserve browser automation for the places where the browser itself is the behavior.

If your project uses RSpec instead of Minitest, translate the examples into request specs, model specs, and system specs. The philosophy stays the same.

## The Goal: Confidence Through Realism

Good tests do not prove that you can call your own methods in isolation. They prove that the application behaves correctly the way users, jobs, and external systems actually hit it.

That usually means:

- routes instead of direct controller method calls
- persisted records instead of elaborate doubles
- real response shapes instead of invented ones
- assertions on visible outcomes rather than implementation details

The right question is not "what is the smallest thing I can unit test?" The right question is "what is the smallest test that still exercises the real behavior I care about?"

## Prefer Integrated Request Tests for Controller Behavior

For controller and request behavior, hit the real endpoint.

That gives you confidence in:

- route wiring
- middleware and request setup
- authentication and authorization
- redirects and response formats
- database writes and side effects

Representative example:

```ruby
class Tasks::ClosuresControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "closing a task changes its state and records an event" do
    task = tasks(:draft)

    assert_difference -> { task.events.count }, +1 do
      post task_closure_path(task)
    end

    assert task.reload.closed?
    assert_redirected_to task_path(task)
  end

  test "closing a task as JSON returns no content" do
    task = tasks(:draft)

    post task_closure_path(task), as: :json

    assert_response :no_content
    assert task.reload.closed?
  end
end
```

The point is not merely that `create` was called. The point is that the route, controller, auth, domain call, and response all work together.

## Test Happy Paths and Failure Modes

Request tests should usually cover more than the sunny day.

Typical cases:

- success
- authentication failure
- authorization failure
- validation failure
- state-specific rejection
- side effects such as events, jobs, or notifications

Representative example:

```ruby
test "members cannot close tasks they do not own" do
  sign_in_as users(:bob)
  task = tasks(:admin_only)

  assert_no_difference -> { task.events.count } do
    post task_closure_path(task)
  end

  assert_response :forbidden
  refute task.reload.closed?
end
```

## Keep Dense Domain Behavior in Model Tests

Use request tests to prove that the app exercises the domain correctly. Use model tests to prove the domain rules in detail.

Good candidates for model tests:

- state transitions
- invariants and edge cases
- callback-triggered behavior
- query scopes that encode business meaning
- rich domain methods that would be awkward to set up through a route every time

Representative example:

```ruby
class Task::CloseableTest < ActiveSupport::TestCase
  test "closing is idempotent" do
    task = tasks(:closed)

    task.close

    assert task.closed?
  end

  test "closing creates the closure record" do
    task = tasks(:draft)

    assert_difference -> { Task::Closure.count }, +1 do
      task.close
    end
  end
end
```

This split keeps the suite fast while still protecting the real business rules.

## Test the Response Shapes You Actually Support

Many Rails controllers serve more than one format:

- HTML
- Turbo Stream
- JSON

When different formats carry different behavior, test those differences explicitly.

Examples:

- HTML create redirects to the next page
- Turbo Stream updates part of the current page
- JSON returns `head :no_content`, a serialized resource, or an error payload

If HTML and JSON both hit the same domain method, one test can prove the shared domain behavior while a second test proves the response difference.

## Prefer Stable, Named Test Data

The data strategy matters less than the principle:

- test data should be easy to name
- common scenarios should be reusable
- setup should be fast

That often points toward fixtures in Rails applications:

- they load quickly
- they make named scenarios easy
- they can be shared across models, requests, jobs, and system tests

Representative fixture usage:

```ruby
task = tasks(:draft)
project = projects(:internal)
user = users(:alice)
```

Factories can still be useful when:

- a scenario is highly specific
- attributes are too varied for static fixtures
- the suite already uses factories consistently

The real rule is: do not make every test build its world from scratch if the same scenarios appear across the suite.

## VCR and WebMock Are Better Than Hand-Written Fantasy APIs

When your app talks to an external HTTP service, prefer recorded real interactions over bespoke stubs.

Why:

- you test against real response shapes
- cassettes are easier to inspect than hand-built fake payloads
- regressions surface when upstream behavior changes

Representative example:

```ruby
test "delivers a webhook successfully" do
  VCR.use_cassette("webhook_delivery_success") do
    delivery = webhook_deliveries(:pending)

    delivery.deliver_now

    assert delivery.delivered?
    assert_equal 200, delivery.response_code
  end
end
```

Use direct WebMock stubs when you need a failure that is hard to record, such as a DNS error or socket timeout.

## Parallel Tests Change What Is Safe

If your suite runs in parallel, protect against hidden shared state.

That means:

- do not rely on global mutable objects leaking between tests
- clear request-scoped globals in teardown when you introduce them
- keep helpers and setup logic local to each test

Parallelization is a forcing function for cleaner test boundaries.

## Use System Tests Sparingly

System tests are valuable, but they are not the default answer.

Use them when you actually need to protect behavior that depends on the browser:

- drag and drop
- clipboard access
- browser-native dialogs
- JavaScript interactions that cannot be covered well through request tests
- end-to-end flows where client behavior is part of the contract

Do not upgrade ordinary request coverage to full browser automation just because the test writer can generate it quickly. Runtime and flakiness still matter.

## What to Cover

For request tests:

- happy path
- authentication
- authorization
- validation failures
- meaningful response-format differences
- side effects such as events, notifications, and jobs

For model tests:

- state transitions
- invariants and edge cases
- callback-triggered behavior
- scope behavior that carries domain meaning

For jobs:

- the right domain object or service is invoked
- retry and discard behavior when it is part of the contract
- tenant or request context restoration when background work depends on it

## What to Avoid

- controller tests that bypass routing and middleware
- heavy mocking around your own domain objects
- giant setup blocks that rebuild the world for every example
- system tests for behavior already well covered by request tests
- assertions that only prove internal implementation rather than real outcomes

## Practical Rule

If a behavior is exposed through a route, prove it through a real request first. If the behavior is primarily domain logic, prove it in a model test. Only move up to a system test when the browser itself is part of the behavior you are protecting.

## Fizzy Notes

Fizzy currently instantiates this philosophy with:

- `ActionDispatch::IntegrationTest` for controller and request behavior
- `ActiveSupport::TestCase` for models, jobs, and lower-level tests
- a fixture-first test data strategy
- VCR and WebMock for external HTTP
- selective `ApplicationSystemTestCase` coverage where browser behavior truly matters
