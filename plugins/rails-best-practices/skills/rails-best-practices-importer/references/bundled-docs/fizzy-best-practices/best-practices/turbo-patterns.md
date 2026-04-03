# Turbo & Hotwire Patterns for Real-Time Rails Applications

This document describes patterns for building real-time, multi-user Rails applications using Turbo (part of Hotwire). These patterns enable live updates across user sessions, smooth animations, user-specific rendering, and DRY abstractions—all with minimal JavaScript.

## The Core Philosophy

Turbo enables "HTML-over-the-wire"—the server renders HTML, and Turbo handles updating the page. This inverts the SPA model: instead of JSON APIs and client-side rendering, you keep rendering on the server where Rails excels.

The key insight: **most real-time features don't need custom WebSocket code**. Turbo Streams over ActionCable handle the plumbing. You focus on what to broadcast and where.

## Live Updates Across User Sessions

### The Broadcasting Model

When one user makes a change, other users see it instantly. This requires:

1. **Model declares what to broadcast** - Using `broadcasts_refreshes` or custom broadcasts
2. **Views subscribe to streams** - Using `turbo_stream_from`
3. **ActionCable authenticates connections** - Users only see what they should

### Basic Broadcasting Setup

**Model-level broadcasting:**

```ruby
module Card::Broadcastable
  extend ActiveSupport::Concern

  included do
    # Automatically broadcast page refresh when card changes
    broadcasts_refreshes
  end
end
```

`broadcasts_refreshes` is a Turbo 8 feature that broadcasts a "refresh" signal. All subscribed browsers re-fetch the page and Turbo morphs the differences.

**View subscription:**

```erb
<%# Subscribe to updates for this specific board %>
<%= turbo_stream_from @board %>

<%# Subscribe to updates for this card %>
<%= turbo_stream_from @card %>

<%# Subscribe to multiple streams %>
<%= turbo_stream_from @card %>
<%= turbo_stream_from @card, :activity %>
```

### Multi-Channel Broadcasting

Sometimes you need to broadcast to multiple channels:

```ruby
module Board::Broadcastable
  extend ActiveSupport::Concern

  included do
    # Broadcast to the specific board's channel
    broadcasts_refreshes

    # Also broadcast to the "all boards" channel for dashboard views
    broadcasts_refreshes_to ->(board) { [board.account, :all_boards] }
  end
end
```

**Subscribing to the right channels:**

```erb
<%# Dashboard view - subscribe based on what user is viewing %>
<% if viewing_specific_boards? %>
  <% @boards.each do |board| %>
    <%= turbo_stream_from board %>
  <% end %>
<% else %>
  <%# Subscribe to all boards in the account %>
  <%= turbo_stream_from Current.account, :all_boards %>
<% end %>
```

### ActionCable Authentication

The WebSocket connection must authenticate and scope to the current user:

```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        if session = find_session_by_cookie
          account = Account.find_by(external_account_id: request.env["fizzy.external_account_id"])
          Current.account = account
          self.current_user = session.identity.users.find_by!(account: account) if account
        end
      end

      def find_session_by_cookie
        Session.find_signed(cookies.signed[:session_token])
      end
  end
end
```

This ensures WebSocket connections have the same authentication as HTTP requests.

## User-Specific Rendering

Some content looks different for different users:
- Notifications are personal
- "You commented" vs "Jane commented"
- Pins, bookmarks, read status

### User-Scoped Broadcasting

Broadcast to a user-specific channel:

```ruby
class Notification < ApplicationRecord
  after_create_commit :broadcast_to_user
  after_destroy_commit :remove_from_user

  private
    def broadcast_to_user
      # Only the notification's owner receives this
      broadcast_prepend_to(
        [user, :notifications],
        target: "notifications",
        partial: "notifications/notification"
      )
    end

    def remove_from_user
      broadcast_remove_to [user, :notifications]
    end
end
```

**User subscribes to their personal channel:**

```erb
<%# In the notifications tray partial %>
<%= turbo_stream_from Current.user, :notifications %>

<div id="notifications">
  <%= render @notifications %>
</div>
```

### Updating User-Specific Views of Shared Content

When shared content changes, users with personalized views need updates:

```ruby
module Card::Pinnable
  extend ActiveSupport::Concern

  included do
    has_many :pins

    # When card preview changes, update all users who pinned it
    after_update_commit :broadcast_to_pinners, if: :preview_changed?
  end

  private
    def broadcast_to_pinners
      pins.find_each do |pin|
        # Each user gets their pin view updated
        pin.broadcast_replace_to(
          [pin.user, :pins],
          partial: "pins/pin"
        )
      end
    end
end
```

### The "You" vs "Someone Else" Pattern

For displaying "You did X" vs "Jane did X":

**Option 1: CSS-based (no extra broadcasts)**

```erb
<%# Render both versions, CSS shows the right one %>
<span data-creator-id="<%= comment.creator_id %>">
  <span data-show-to-creator>You</span>
  <span data-show-to-others><%= comment.creator.name %></span>
</span>
```

```css
/* Default: show "others" version */
[data-show-to-creator] { display: none; }

/* When viewing as creator, swap */
[data-current-user-id="123"] [data-creator-id="123"] {
  [data-show-to-creator] { display: inline; }
  [data-show-to-others] { display: none; }
}
```

Set `data-current-user-id` on the body element.

**Option 2: Broadcast both versions**

```ruby
def broadcast_comment_created
  # Broadcast to creator with "You" version
  broadcast_replace_to(
    [creator, :activity],
    partial: "comments/comment",
    locals: { comment: self, viewer_is_creator: true }
  )

  # Broadcast to others with name version
  card.watchers.where.not(id: creator_id).each do |watcher|
    broadcast_replace_to(
      [watcher, :activity],
      partial: "comments/comment",
      locals: { comment: self, viewer_is_creator: false }
    )
  end
end
```

Option 1 is simpler and more efficient. Option 2 allows for more complex personalization.

## Empty State Handling

When adding the first item or removing the last, you need to show/hide empty states gracefully.

### CSS :has() for Declarative Empty States

The modern approach uses CSS `:has()` to show/hide empty states without JavaScript:

```erb
<div class="card-list" id="cards">
  <%# Empty state - always in DOM %>
  <div class="empty-state">
    <p>No cards yet. Create your first card!</p>
  </div>

  <%# Actual cards %>
  <%= render @cards %>
</div>
```

```css
/* Hide empty state when there are cards */
.card-list:has(.card) .empty-state {
  display: none;
}

/* Style empty state when visible */
.card-list:not(:has(.card)) .empty-state {
  padding: 2rem;
  text-align: center;
  color: var(--color-muted);
}
```

**How this works with Turbo Streams:**

1. Initial render: If no cards, empty state shows
2. Turbo Stream prepends a card: CSS `:has(.card)` now matches, empty state hides
3. Turbo Stream removes last card: `:has(.card)` no longer matches, empty state shows

No JavaScript needed. No special Turbo handling. Pure CSS.

### Placeholder Cards Pattern

For lists where you always want some visual presence:

```erb
<div class="card-list" id="cards">
  <%# Placeholder card - hidden when real cards exist %>
  <div class="card card--placeholder">
    <p>Drop cards here</p>
  </div>

  <%= render @cards %>
</div>
```

```css
/* Hide placeholder when real cards exist */
.card-list:has(.card:not(.card--placeholder)) .card--placeholder {
  display: none;
}
```

### Filter-Aware Empty States

When filters produce no results:

```erb
<div class="card-grid" id="cards">
  <%# Empty due to filters %>
  <div class="empty-state empty-state--filtered">
    <p>No cards match your filters.</p>
    <%= link_to "Clear filters", cards_path %>
  </div>

  <%# Empty with no cards at all %>
  <div class="empty-state empty-state--empty">
    <p>No cards yet.</p>
  </div>

  <%= render @cards %>
</div>
```

```css
/* Hide both empty states when cards exist */
.card-grid:has(.card) .empty-state {
  display: none;
}

/* When filtering and no results, show filter message */
.card-grid[data-filtered]:not(:has(.card)) .empty-state--empty {
  display: none;
}

/* When not filtering and empty, show empty message */
.card-grid:not([data-filtered]):not(:has(.card)) .empty-state--filtered {
  display: none;
}
```

## Animation and Smooth Effects

### View Transitions API

Turbo 8 integrates with the browser's View Transitions API for smooth page transitions:

**Enable globally:**

```erb
<%# In layout head %>
<meta name="view-transition" content="same-origin">
```

**Configure Turbo to use morphing:**

```erb
<% turbo_refreshes_with method: :morph, scroll: :preserve %>
```

This tells Turbo to:
1. Use morphing (DOM diffing) instead of full replacement
2. Preserve scroll position during refreshes

### Per-Element View Transitions

Give elements a `view-transition-name` for individual animation:

```erb
<article
  id="<%= dom_id(card) %>"
  style="view-transition-name: <%= dom_id(card) %>"
>
  <%= card.title %>
</article>
```

When navigating between pages, elements with matching `view-transition-name` animate smoothly.

**Customize the transition with CSS:**

```css
/* Cards cross-fade during transitions */
::view-transition-old(card_123),
::view-transition-new(card_123) {
  animation-duration: 200ms;
}

/* Sidebar slides */
::view-transition-group(sidebar) {
  animation-duration: 300ms;
}

/* Keep certain elements on top during transition */
::view-transition-group(header) {
  z-index: 100;
}
```

### Animating Turbo Stream Insertions

When Turbo Stream adds an element, animate its entrance:

```css
/* New items fade and slide in */
.card {
  animation: slide-in 200ms ease-out;
}

@keyframes slide-in {
  from {
    opacity: 0;
    transform: translateY(-10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```

For removals, you need JavaScript since the element is removed immediately:

```javascript
// Intercept stream removal to animate first
document.addEventListener("turbo:before-stream-render", (event) => {
  const stream = event.target
  if (stream.action === "remove") {
    const target = document.getElementById(stream.target)
    if (target) {
      event.preventDefault()

      target.animate(
        [
          { opacity: 1, transform: "scale(1)" },
          { opacity: 0, transform: "scale(0.95)" }
        ],
        { duration: 150, easing: "ease-out" }
      ).onfinish = () => target.remove()
    }
  }
})
```

### Staggered Animations

For lists where items animate in sequence:

```css
.tray-item {
  --delay: calc(var(--index) * 30ms);
  animation: fade-in 200ms ease-out;
  animation-delay: var(--delay);
  animation-fill-mode: backwards;
}
```

Set the index in the view:

```erb
<% @items.each.with_index do |item, index| %>
  <div class="tray-item" style="--index: <%= index %>">
    <%= render item %>
  </div>
<% end %>
```

### Disabling Transitions Temporarily

Sometimes you need to disable transitions (e.g., restoring state):

```javascript
export default class extends Controller {
  restoreWithoutAnimation() {
    this.element.classList.add("no-transitions")
    this.restore()

    // Re-enable after next frame
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.element.classList.remove("no-transitions")
      })
    })
  }
}
```

```css
.no-transitions,
.no-transitions * {
  transition: none !important;
}
```

## DRY Patterns and Abstractions

### Shared Controller Concern for Turbo Responses

```ruby
module TurboResponsive
  extend ActiveSupport::Concern

  private
    def replace_with_morph(target, partial:, locals: {})
      render turbo_stream: turbo_stream.replace(
        target,
        partial: partial,
        method: :morph,
        locals: locals
      )
    end

    def prepend_to(target, partial:, locals: {})
      render turbo_stream: turbo_stream.prepend(
        target,
        partial: partial,
        locals: locals
      )
    end

    def remove_and_update(remove_target, update_target:, partial:, locals: {})
      render turbo_stream: [
        turbo_stream.remove(remove_target),
        turbo_stream.update(update_target, partial: partial, locals: locals)
      ]
    end
end
```

### Card-Scoped Controller Pattern

For controllers that operate on cards and need consistent Turbo responses:

```ruby
module CardScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_card
  end

  private
    def set_card
      @card = Current.user.accessible_cards.find(params[:card_id])
    end

    def render_card_container
      render turbo_stream: turbo_stream.replace(
        [@card, :container],
        partial: "cards/container",
        method: :morph,
        locals: { card: @card.reload }
      )
    end
end
```

Usage:

```ruby
class Cards::PinsController < ApplicationController
  include CardScoped

  def create
    @card.pin_for(Current.user)
    render_card_container
  end

  def destroy
    @card.unpin_for(Current.user)
    render_card_container
  end
end
```

### Frame Helper with Morph Defaults

```ruby
module FrameHelper
  def morphing_frame_tag(id, src: nil, **options, &block)
    options[:refresh] = :morph if src.present?
    options[:data] = (options[:data] || {}).merge(
      controller: "frame",
      action: "turbo:before-frame-render->frame#morphRender"
    )

    turbo_frame_tag(id, src: src, **options, &block)
  end
end
```

### Pagination Helper

```ruby
module PaginationHelper
  def paginated_list(id, page, &block)
    tag.div(
      id: id,
      data: {
        controller: "pagination",
        pagination_page_value: page.current_page
      }
    ) do
      turbo_frame_tag("#{id}_frame") do
        capture(&block) +
        (link_to_next_page(page) if page.next_page?)
      end
    end
  end

  private
    def link_to_next_page(page)
      link_to(
        "Load more",
        url_for(page: page.next_page),
        data: {
          pagination_target: "nextPage",
          turbo_frame: "#{id}_frame"
        }
      )
    end
end
```

## Turbo Frame Patterns

### Lazy Loading with src

Load content on demand:

```erb
<%# Placeholder that loads when visible %>
<%= turbo_frame_tag "comments",
      src: card_comments_path(@card),
      loading: :lazy %>
```

The frame fetches its content when it enters the viewport.

### Preserving Elements Across Navigation

Keep certain UI elements (modals, trays) across page navigations:

```erb
<%# In layout %>
<div id="persistent_ui" data-turbo-permanent>
  <%= render "notifications/tray" %>
  <%= render "pins/tray" %>
</div>
```

`data-turbo-permanent` tells Turbo to never replace these elements during navigation.

### Frame Targeting

Navigate frames from links/forms:

```erb
<%# Update specific frame %>
<%= link_to "Edit", edit_card_path(@card), data: { turbo_frame: "card_form" } %>

<%# Break out of frame to full page %>
<%= link_to "View all", cards_path, data: { turbo_frame: "_top" } %>
```

### Reloading Frames on Events

```javascript
// frame_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  reload() {
    this.element.reload()
  }

  // Reload when document morphs (to refresh stale data)
  refreshOnMorph() {
    this.element.reload()
  }
}
```

```erb
<%= turbo_frame_tag "notifications",
      src: notifications_path,
      data: {
        controller: "frame",
        action: "turbo:morph@document->frame#refreshOnMorph"
      } %>
```

## Turbo Stream Response Patterns

### Common Actions

**Replace with morph (best for updates):**

```erb
<%= turbo_stream.replace dom_id(@card),
      partial: "cards/card",
      method: :morph,
      locals: { card: @card } %>
```

**Prepend (new items at top):**

```erb
<%= turbo_stream.prepend "cards",
      partial: "cards/card",
      locals: { card: @card } %>
```

**Append (new items at bottom):**

```erb
<%= turbo_stream.append "comments",
      partial: "comments/comment",
      locals: { comment: @comment } %>
```

**Before/After (insert relative to element):**

```erb
<%# Insert before the "new comment" form %>
<%= turbo_stream.before "new_comment",
      partial: "comments/comment",
      locals: { comment: @comment } %>
```

**Remove:**

```erb
<%= turbo_stream.remove @comment %>
```

**Update (inner HTML only):**

```erb
<%= turbo_stream.update "comment_count" do %>
  <%= @card.comments.count %> comments
<% end %>
```

### Multiple Streams in One Response

```erb
<%# create.turbo_stream.erb %>

<%# Add the new comment %>
<%= turbo_stream.before "new_comment",
      partial: "comments/comment",
      locals: { comment: @comment } %>

<%# Reset the form %>
<%= turbo_stream.replace "new_comment",
      partial: "comments/form",
      locals: { card: @card, comment: Comment.new } %>

<%# Update the count %>
<%= turbo_stream.update "comment_count" do %>
  <%= @card.comments.count %>
<% end %>
```

### Conditional Streams

```erb
<%= turbo_stream.replace dom_id(@card), partial: "cards/card", locals: { card: @card } %>

<% if @card.column_previously_changed? %>
  <%# Also update adjacent columns %>
  <% @card.column.adjacent_columns.each do |column| %>
    <%= turbo_stream.replace dom_id(column),
          partial: "columns/column",
          method: :morph,
          locals: { column: column } %>
  <% end %>
<% end %>
```

## Morphing Best Practices

Turbo 8's morphing (via Idiomorph) diffs the DOM instead of replacing it. This preserves:
- Form input values
- Scroll position
- Focus state
- CSS transitions in progress

### Enable Morphing Globally

```erb
<% turbo_refreshes_with method: :morph, scroll: :preserve %>
```

### Frame-Level Morphing

For frames that should morph their content:

```javascript
// frame_controller.js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  morphRender(event) {
    event.detail.render = (currentElement, newElement) => {
      Turbo.morphChildren(currentElement, newElement)
    }
  }
}
```

```erb
<%= turbo_frame_tag "cards",
      data: {
        controller: "frame",
        action: "turbo:before-frame-render->frame#morphRender"
      } %>
```

### Morph Callbacks

Respond to morph events:

```erb
<body data-action="turbo:morph@document->app#onMorph">
```

```javascript
// app_controller.js
onMorph() {
  // Re-initialize any third-party libraries
  // Update any cached references
}
```

### Preserving State During Morph

Mark elements that should survive morphing:

```erb
<div data-turbo-permanent id="video_player">
  <%# Video player state preserved across morphs %>
</div>
```

## Putting It All Together

### A Complete Example: Real-Time Comments

**Model:**

```ruby
class Comment < ApplicationRecord
  belongs_to :card
  belongs_to :creator, class_name: "User"

  after_create_commit :broadcast_created
  after_destroy_commit :broadcast_removed

  private
    def broadcast_created
      broadcast_append_to(
        card,
        target: "comments",
        partial: "comments/comment"
      )
    end

    def broadcast_removed
      broadcast_remove_to card
    end
end
```

**Controller:**

```ruby
class CommentsController < ApplicationController
  include CardScoped

  def create
    @comment = @card.comments.create!(comment_params.merge(creator: Current.user))

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @card }
    end
  end

  def destroy
    @comment = @card.comments.find(params[:id])
    @comment.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@comment) }
      format.html { redirect_to @card }
    end
  end
end
```

**View subscription:**

```erb
<%# cards/show.html.erb %>
<%= turbo_stream_from @card %>

<div id="comments">
  <%= render @card.comments %>

  <%# Empty state via CSS :has() %>
  <p class="empty-state">No comments yet.</p>
</div>

<%= render "comments/form", card: @card %>
```

**Stream template:**

```erb
<%# comments/create.turbo_stream.erb %>
<%= turbo_stream.append "comments", @comment %>

<%= turbo_stream.replace "new_comment",
      partial: "comments/form",
      locals: { card: @card } %>
```

**CSS:**

```css
#comments:has(.comment) .empty-state {
  display: none;
}

.comment {
  animation: slide-in 150ms ease-out;
}
```

This gives you:
- Real-time comments across all users viewing the card
- Smooth animation when comments appear
- Empty state that shows/hides automatically
- Form reset after submission
- Works without JavaScript for basic functionality

## Summary

**Key patterns:**

1. **Broadcasting**: Use `broadcasts_refreshes` for automatic real-time updates; scope broadcasts appropriately (model, user, or custom channels)

2. **User-specific content**: Broadcast to `[user, :channel_name]` for personal content; use CSS tricks for "You vs Others" rendering

3. **Empty states**: Use CSS `:has()` for declarative show/hide—no JavaScript needed

4. **Animations**: Use View Transitions API with Turbo; intercept `turbo:before-stream-render` for removal animations

5. **DRY code**: Extract common Turbo responses to concerns; create helpers for common frame patterns

6. **Morphing**: Enable globally with `turbo_refreshes_with method: :morph`; use frame-level morphing for partial updates

7. **Frames**: Use `src` for lazy loading; `data-turbo-permanent` for persistent UI; frame targeting for scoped updates

The result: real-time, multi-user applications with minimal custom JavaScript, leveraging Rails' rendering strengths and Turbo's HTML-over-the-wire architecture.
