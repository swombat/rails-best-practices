# Platform-Aware Rails

This document describes a portable Rails pattern for treating request metadata, timezone, and client platform as first-class application inputs. This is not just front-end trivia. Layouts, caching, analytics, bridge clients, and feature support often depend on the same platform information.

Use the generic sections below when adapting the pattern to another codebase. The final section describes how Fizzy currently applies it.

## Why Platform Awareness Belongs in the App Layer

Many apps eventually need to answer questions like:

- what timezone should this response render in?
- is this request coming from the normal web app, a native shell, or an embedded client?
- should the layout expose bridge hooks or client-specific instructions?
- should this browser even be allowed through?

If those answers are scattered across helpers, controllers, and JavaScript, the codebase gets inconsistent quickly.

The better approach is:

1. derive request and platform state once
2. store it in request scope
3. publish it to the places that need it

## Keep Request Metadata in One Place

Request-scoped metadata often belongs on `Current` or a sibling request object.

Useful fields:

- HTTP method
- request ID
- user agent
- IP address
- referrer

Representative shape:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :request_id, :http_method, :user_agent, :ip_address, :referrer, :platform
end
```

This is useful for:

- analytics and telemetry
- error reporting
- audit trails
- domain logic that records request context

The win is not novelty. The win is that every layer can ask one place for request facts instead of threading arguments everywhere.

## Treat Timezone as Request Context

Timezone is often handled too late, inside helpers or view formatting calls. A better pattern is to make it part of request rendering.

Typical approach:

1. detect the client timezone
2. persist it in a cookie or account preference
3. wrap the request in `Time.use_zone`
4. vary cache keys or ETags when timezone changes output

Representative shape:

```ruby
module CurrentTimezone
  extend ActiveSupport::Concern

  included do
    around_action :use_current_timezone
  end

  private
    def use_current_timezone(&block)
      Time.use_zone(timezone_from_request, &block)
    end
end
```

That keeps rendered timestamps, caches, and user expectations aligned.

## Derive Platform Once

Apps that support more than one client surface often need a small platform object.

Possible inputs:

- request user agent
- a cookie set by a native wrapper
- a signed client identifier
- request headers from a trusted shell or bridge

Representative shape:

```ruby
class Platform
  def self.from(request:, cookies:)
    user_agent = cookies[:x_user_agent].presence || request.user_agent
    new(user_agent)
  end
end
```

The important part is not the parser. It is that platform detection happens once and produces a stable object the rest of the app can use.

## Publish Platform State Through the Layout

Once platform is known, publish it declaratively.

Common options:

- data attributes on `<body>`
- helper methods for small conditionals
- small JSON configuration objects for client-side code

This creates a clean split:

- Rails derives the platform once
- the layout exposes it
- CSS and JavaScript react to it

That is usually cleaner than sprinkling user-agent checks throughout templates.

## Be Explicit About Browser Support

Modern Rails stacks increasingly depend on:

- Hotwire
- modern CSS selectors and layout features
- View Transitions
- passkeys
- native bridge integrations

If your app depends on modern browser capabilities, state that policy explicitly rather than pretending to support everything.

In Rails, that may look like:

```ruby
allow_browser versions: :modern
```

The specific gate may vary, but the broader rule stands: your compatibility policy should match the capabilities your UI actually requires.

## Use Narrow Client Configuration Endpoints

If native shells or embedded clients need server-driven configuration, do not force them to reverse-engineer full HTML pages.

A lightweight configuration endpoint can be a better fit:

```text
/client_configurations/ios_v1
/client_configurations/android_v2
```

Useful data for these endpoints:

- feature flags
- bridge capabilities
- minimum supported client version
- upgrade prompts
- platform-specific copy or URLs

This gives you a shared contract without duplicating the entire web layer.

## Testing Guidance

Useful tests for platform-aware Rails code:

- timezone cookies affect rendered output
- cache variance changes when timezone changes visible content
- platform detection is stable for expected client inputs
- unsupported browsers are rejected consistently
- layouts publish the expected platform data attributes or config payloads

The main thing to protect against is platform logic becoming inconsistent across controllers and templates.

## When Not to Use This Pattern

You probably do not need all of this if:

- the app is web-only
- timezone is fixed or irrelevant
- there is no native shell or embedded client
- the UI does not branch on platform or capability

In that case, a smaller helper-only approach may be enough.

## Practical Guidance

- Put request metadata in one request-scoped object.
- Treat timezone as part of rendering, not as a formatting afterthought.
- Derive platform once and expose it declaratively.
- Make browser support policy explicit.
- Use small configuration endpoints when non-browser clients need server-driven behavior.

## Fizzy Notes

Fizzy currently uses request-scoped metadata, timezone cookies, platform detection, an explicit modern-browser policy, and platform/version-based client configuration endpoints. The layout publishes platform state so CSS, Stimulus, and bridge code can react to it declaratively.
