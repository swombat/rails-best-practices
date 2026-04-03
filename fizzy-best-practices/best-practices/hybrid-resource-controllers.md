# Hybrid Resource Controllers

This document describes a portable Rails pattern for serving HTML, Turbo Stream, and JSON from the same resource controller. The core idea is simple: keep one controller per resource, and branch by representation only where the response shape or workflow truly differs.

This pattern is especially useful when the same domain model powers:

- normal browser navigation
- progressively enhanced Hotwire flows
- lightweight JSON clients

## The Core Pattern

Use one resource-oriented controller and keep the shared parts shared:

- route and resource naming
- record lookup
- authorization
- strong parameters
- domain method calls

Then branch only where the response or workflow differs.

Representative shape:

```ruby
class TasksController < ApplicationController
  wrap_parameters :task, include: %i[title description due_on]

  def create
    respond_to do |format|
      format.html do
        @task = Current.membership.tasks.create!(task_params)
        redirect_to @task
      end

      format.json do
        @task = Current.membership.tasks.create!(task_params)
        render :show, status: :created, location: task_path(@task, format: :json)
      end
    end
  end

  def update
    @task.update!(task_params)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @task }
      format.json { render :show }
    end
  end
end
```

The branching is about representation, not ownership of the business logic.

## What Should Usually Stay Shared

Across formats, these should usually remain the same:

- which record is loaded
- who is allowed to act on it
- which domain method runs
- which validations apply

If those parts start drifting apart, you may not actually have one resource with many representations. You may have different workflows that deserve different endpoints.

## What Can Differ by Format

It is fine for formats to differ when the user experience truly differs.

Common examples:

- HTML create redirects to the new record
- Turbo Stream update renders stream actions instead of a full page
- JSON update returns a serialized resource or `head :no_content`
- HTML create may start a draft flow while JSON create publishes immediately

The rule is not "every format must behave identically." The rule is "differences should be explicit and intentional."

## Keep the Domain Call Direct

Hybrid controllers work best when controllers stay small and the model owns the interesting behavior.

Example:

```ruby
class Tasks::ClosuresController < ApplicationController
  def create
    @task = Current.membership.tasks.find(params[:task_id])
    @task.close

    respond_to do |format|
      format.html { redirect_to @task }
      format.turbo_stream
      format.json { head :no_content }
    end
  end
end
```

The controller is still doing the same three things:

1. load the resource
2. call the domain method
3. render the appropriate representation

Do not introduce a service object just to hide a controller that is already small and honest.

## Flat JSON Input Can Still Use Rails Parameter Conventions

If you want JSON clients to send flat payloads, you do not need a parallel API controller stack.

Pattern:

```ruby
class ProjectsController < ApplicationController
  wrap_parameters :project, include: %i[name archived color]

  private
    def project_params
      params.expect(project: [ :name, :archived, :color ])
    end
end
```

That lets the client send:

```json
{ "name": "Internal Tools" }
```

while your controller code still works with the same nested parameter expectations as normal form posts.

## JSON Does Not Need a Separate Domain Layer

A common mistake is building:

- one set of HTML controllers
- one set of API controllers
- one set of domain calls for each

That often duplicates authentication rules, authorization rules, and workflow code.

If JSON is just another representation of the same resource, keep it on the same controller and test the important response differences.

Split the controller stack only when the API really is a different product surface with different versioning, security, or workflow constraints.

## CSRF and Same-Origin JSON

If JSON is first-class for browser clients, make sure your CSRF strategy matches that reality.

Common patterns:

- require CSRF tokens in headers for non-GET requests
- allow same-origin JSON requests from your own app shell
- keep bearer-token API auth separate from session-based browser auth

The exact implementation depends on your app, but the broader rule is stable: do not create a second controller stack just to dodge request-forgery handling.

## Testing Guidance

For controllers that support multiple representations, cover the meaningful variants.

Typical tests:

- HTML success path and redirect target
- Turbo Stream rendering when present
- JSON status and payload shape
- shared domain side effects across representations

Use real request tests or request specs, not controller tests that bypass routing and middleware.

## When to Split Controllers Instead

Do not force this pattern where it does not fit.

Separate controllers may be better when:

- the API is versioned independently
- browser and API authentication are fundamentally different
- the API exposes workflows the browser never uses
- the API needs different pagination, filtering, or serialization contracts

One resource controller with many formats is elegant. Two genuinely different product surfaces should stay separate.

## Practical Guidance

- Start with a normal resource controller.
- Add `respond_to` only when a second representation is real.
- Keep record loading and authorization shared across formats.
- Keep domain methods format-agnostic.
- Return small JSON responses by default unless the client truly needs a larger payload.
- Test the response differences, not just the shared model mutation.

## Fizzy Notes

Fizzy currently uses this pattern heavily:

- the same resource controllers often serve HTML, Turbo Stream, and JSON
- JSON is treated as a first-class representation, not a separate API layer
- `wrap_parameters` is used to support flat JSON while keeping nested parameter expectations
- controller tests cover the differing response shapes where they matter
