# View Layer Philosophy

The 37signals approach to Rails views is radically simple: **partials and helpers are enough**. This document captures the philosophy behind how we structure our view layer and when (rarely) to reach for more sophisticated abstractions.

## The Foundation: Partials and Helpers Work Great

For 95% of your view needs, vanilla Rails gives you everything you need. The key is treating view composition with the same care you give to methods in your models and controllers.

**Divide your views into smaller chunks with proper names, keeping each chunk at the same level of abstraction.**

Just as you wouldn't write a 200-line method in a model, don't write a 200-line template. Break it down. Give the pieces meaningful names. Keep related concerns together.

### Example: Composing Card Views

Look at how we compose a card container:

```erb
<section id="<%= dom_id(card, :card_container) %>" class="card-perma">
  <% cache card do %>
    <div class="card-perma__actions card-perma__actions--left">
      <%= render "cards/container/gild", card: card if card.published? && !card.closed? %>
      <%= render "cards/container/image", card: card %>
    </div>

    <div class="card-perma__bg">
      <%= card_article_tag card, class: "card" do %>
        <header class="card__header">
          <%= render "cards/display/perma/board", card: card %>
          <%= render "cards/display/perma/tags", card: card %>
        </header>

        <div class="card__body justify-space-between">
          <div class="card__content">
            <%= render "cards/container/content", card: card %>
            <%= render "cards/display/perma/steps", card: card %>
          </div>
        </div>

        <footer class="card__footer full-width flex align-start gap">
          <%= render "cards/display/perma/meta", card: card %>
          <%= render "cards/display/perma/background", card: card %>
        </footer>
      <% end %>
    </div>
  <% end %>
</section>
```

Each partial does one clear thing. The names tell you what they do. The composition reads like a table of contents for the card's structure.

## When to Use Partials vs Helpers

The decision is straightforward:

**Helpers are for simple HTML bits.** A turbo frame tag with specific attributes. An icon. A back button with a keyboard shortcut. Small, reusable pieces that you want to invoke with a method call.

```ruby
module ApplicationHelper
  def icon_tag(name, **options)
    tag.span class: class_names("icon icon--#{name}", options.delete(:class)),
             "aria-hidden": true,
             **options
  end

  def back_link_to(label, url, action, **options)
    link_to url, class: "btn btn--back", data: { controller: "hotkey", action: action }, **options do
      icon_tag("arrow-left") +
      tag.strong("Back to #{label}", class: "overflow-ellipsis") +
      tag.kbd("ESC", class: "txt-x-small hide-on-touch").html_safe
    end
  end
end
```

**Partials are for more substantial HTML.** When you're composing larger chunks of markup, partials work better. They let you include context, use conditionals naturally, and nest other partials or helpers without awkward string concatenation.

```ruby
module CardsHelper
  def card_article_tag(card, id: dom_id(card, :article), data: {}, **options, &block)
    classes = [
      options.delete(:class),
      ("golden-effect" if card.golden?),
      ("card--postponed" if card.postponed?),
      ("card--active" if card.active?)
    ].compact.join(" ")

    data[:drag_and_drop_top] = true if card.golden? && !card.closed? && !card.postponed?

    tag.article \
      id: id,
      style: "--card-color: #{card.color}; view-transition-name: #{id}",
      class: classes,
      data: data,
      **options,
      &block
  end
end
```

**When in doubt, prefer partials for HTML composition.** They're easier to read, easier to maintain, and easier for designers to work with.

## Why Not View Components?

We've looked at View Components. They're well-designed. But they would need to be "night and day" better than what we have to justify the switch. They're not.

**ERB templates are the common ground where designers work.**

Designers at 37signals have enormous agency and autonomy. They work directly in the codebase, shipping features, iterating on interfaces, refining interactions. We've had over 2000 pull requests from designers working directly with ERB templates.

A more programmatic approach—wrapping everything in Ruby classes, adding ceremony around component initialization—would hurt this common ground. It would make the code less accessible to people who think primarily in HTML and CSS, not Ruby object hierarchies.

We optimize for designers having direct access to the view layer. ERB lets them stay in the markup. Partials are just files. Helpers are methods they can call. It's simple. It works.

View Components aren't significantly better enough to justify losing this. Not even close.

## Presenter Objects for Complex Views (But This Is Rare)

Sometimes helpers fall short. You find yourself writing helpers that invoke other helpers, always passing the same data around. Everything gets tangled up. You're in a "salad of helper methods."

**That's a signal: there's a missing abstraction.**

This is when you reach for a plain Ruby object. Don't call it a presenter (we don't care about names). Just create an object that gives the view a cleaner API.

### Example: Day Timeline

The day timeline shows events grouped by time across three columns: "Added," "Updated," and "Done." It needs to filter events, group them by hour, handle pagination, and provide a clean interface for rendering.

This is too complex for a salad of helpers. So we extracted `User::DayTimeline`:

```ruby
class User::DayTimeline
  attr_reader :user, :day, :filter

  def initialize(user, day, filter)
    @user, @day, @filter = user, day, filter
  end

  def has_activity?
    events.any?
  end

  def events
    filtered_events.where(created_at: window).order(created_at: :desc)
  end

  def added_column
    @added_column ||= build_column(:added, "Added", 1,
      events.where(action: %w[card_published card_reopened]))
  end

  def updated_column
    @updated_column ||= build_column(:updated, "Updated", 2,
      events.where.not(action: %w[card_published card_closed card_reopened]))
  end

  def closed_column
    @closed_column ||= build_column(:closed, "Done", 3,
      events.where(action: "card_closed"))
  end

  private
    def build_column(id, base_title, index, events)
      Column.new(self, id, base_title, index, events)
    end

    def filtered_events
      # Complex filtering logic...
    end
end
```

The view becomes simple:

```erb
<% cache [ day_timeline.events ] do %>
  <% if day_timeline.has_activity? %>
    <div class="events__columns">
      <%= render "events/day_timeline/column", column: day_timeline.added_column %>
      <%= render "events/day_timeline/column", column: day_timeline.updated_column %>
      <%= render "events/day_timeline/column", column: day_timeline.closed_column %>
    </div>
  <% end %>
<% end %>
```

Each column is itself an object with a view-friendly API:

```ruby
class User::DayTimeline::Column
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  include TimeHelper

  attr_reader :index, :id, :base_title, :day_timeline, :events

  def initialize(day_timeline, id, base_title, index, events)
    @id = id
    @day_timeline = day_timeline
    @base_title = base_title
    @index = index
    @events = events
  end

  def title
    date_tag = local_datetime_tag(day_timeline.day, style: :agoorweekday)
    parts = [ base_title, date_tag ]
    parts << tag.span("(#{full_events_count})", class: "font-weight-normal") if full_events_count > 0
    safe_join(parts, " ")
  end

  def events_by_hour
    limited_events.group_by { it.created_at.hour }
  end

  def has_more_events?
    limited_events.count < full_events_count
  end

  private
    def limited_events
      @limited_events ||= events.limit(100).load
    end
end
```

Notice these are just plain Ruby objects. They include the helpers they need. They provide methods that return view-friendly data—sometimes even pre-formatted HTML.

### Presentation Concerns Can Live in Models Too

Sometimes the best place for presentation logic is right in the domain model. Consider `Event#description_for(user)`:

```ruby
class Event < ApplicationRecord
  def description_for(user)
    Event::Description.new(self, user)
  end
end
```

This returns a presenter object that knows how to format event descriptions for display:

```ruby
class Event::Description
  include ActionView::Helpers::TagHelper

  def initialize(event, user)
    @event = event
    @user = user
  end

  def to_html
    to_sentence(creator_tag, card_title_tag).html_safe
  end

  def to_plain_text
    to_sentence(creator_name, card.title)
  end

  private
    def creator_tag
      tag.span data: { creator_id: event.creator.id } do
        tag.span("You", data: { only_visible_to_you: true }) +
        tag.span(event.creator.name, data: { only_visible_to_others: true })
      end
    end

    def action_sentence(creator, card_title)
      case event.action
      when "card_assigned"
        assigned_sentence(creator, card_title)
      when "card_published"
        "#{creator} added #{card_title}"
      when "card_closed"
        %(#{creator} moved #{card_title} to "Done")
      # ... more cases
      end
    end
end
```

The view just calls `event.description_for(Current.user).to_html`. Clean. Testable. All the complex logic is in a place where it can evolve independently.

**But this is rare.** Fizzy has only 2-3 examples of presenter objects in the entire codebase. Templates and view helpers are used everywhere, all the time.

## Don't Test Views Directly

We test views through integration tests—controller tests that exercise the full request/response cycle. We look at expected outcomes: database modifications, HTTP responses, redirects, flash messages.

**We do not write tests that assert on specific HTML output.**

Why? Because designers keep iterating on views after features ship. They refine the markup. They adjust classes. They try different layouts. If we had tests asserting on specific HTML structure or CSS classes, every iteration would break tests. The tests would get in the way of iteration.

This isn't a problem in practice. The lack of direct view tests has never been a recurring source of bugs. When something breaks in a view, it's obvious—you see it in the browser. You fix it.

Integration tests give us confidence that the right data flows through the system. That's what matters.

## Summary: Keep It Simple

1. **Use partials and helpers for 95% of your view needs.** Divide views into well-named chunks at consistent levels of abstraction.

2. **Helpers for simple HTML bits.** Partials for substantial markup that composes well with other HTML.

3. **When in doubt, prefer partials.** They're easier for designers to work with.

4. **Avoid fancy abstractions that hurt the common ground.** ERB is where designers and programmers meet. Keep it accessible.

5. **Extract presenter objects when you're drowning in helper salad.** When helpers start calling other helpers with the same data over and over, create a plain Ruby object with a view-friendly API.

6. **This is rare.** If you find yourself creating lots of presenter objects, you're probably overcomplicating things.

7. **Test views through integration tests.** Don't assert on HTML. Assert on outcomes.

The simpler you keep your view layer, the easier it is for everyone on the team to work with it. That's the goal.
