# Testing Philosophy

This document is a portable Rails testing reference. The main idea is to prefer tests that exercise the real stack, keep domain-heavy logic in model tests, and reserve browser tests for behavior that genuinely depends on the browser.

## Prefer Request and Integration Tests for Application Behavior

When you want confidence that the app works, hit the real endpoint.

That usually covers:

- routes
- controller filters
- authentication
- authorization
- persistence
- response format
- side effects

This is usually more valuable than isolated controller tests that only prove a method can be called.

## Keep Dense Business Rules in Model Tests

Model tests are the right place for:

- state transitions
- callback-driven invariants
- query scopes with business meaning
- rich domain methods

Use them to cover the rule set in detail while request tests prove the application reaches those rules correctly.

## Use Fixtures or Other Named Data That Reads Clearly

The exact fixture-vs-factory choice matters less than the outcome:

- test setup should be fast
- common scenarios should have stable names
- the suite should not rebuild the world in every example

Named fixtures are still a strong fit for Rails apps that lean on integration tests.

## Assert Real Outcomes, Not Just Method Calls

The best assertions usually check:

- records changed
- broadcasts happened
- jobs were enqueued
- the response body changed
- the user can see the result

This is stronger than verifying that your own internal method was invoked.

## Use Browser Tests for Browser Behavior

System tests are valuable when the browser is part of the feature:

- realtime flows across sessions
- rich text interactions
- clipboard and file uploads
- Turbo- and websocket-driven UI

They are not the default answer for every CRUD flow.

## Keep Test Helpers Small and Reusable

A few focused helpers can drastically improve readability:

- sign in helpers
- Turbo broadcast assertions
- mention or rich-text builders
- browser flow helpers

The goal is to eliminate repetitive ceremony without hiding the behavior under test.

## Protect Parallel Test Isolation

Parallel tests surface hidden shared state. That is good.

If the suite runs in parallel:

- clear pubsub state
- reset global collaborators
- avoid leaked network stubs
- keep `Current` and other request globals scoped

Any mutable global should have an explicit reset story.

## Campfire Notes

- The suite is integration-heavy. `test/controllers/*` hits real routes and asserts on responses, records, jobs, and broadcasts.
- `test/models/*` covers domain logic such as user deactivation and membership grants.
- Fixtures are loaded globally and used by name throughout the suite.
- `TurboTestHelper` adds assertions over Turbo broadcasts rather than forcing every test to parse the raw pubsub payload by hand.
- `SessionTestHelper` and other helpers keep authentication and mention setup concise.
- `ApplicationSystemTestCase` is used for behavior that truly depends on the browser, especially multi-session realtime flows like sending, editing, and deleting messages across two users.
- The test setup explicitly resets Action Cable pubsub state, the web push pool, and WebMock configuration to stay safe under parallel execution.
