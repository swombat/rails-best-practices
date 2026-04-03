# View Layer and CSS

This document is a portable Rails reference. The core philosophy is that ERB partials, helpers, Stimulus, and custom CSS are enough for most Rails applications when they are structured deliberately.

## Use Partials as the Main Composition Tool

Partials work well when they are:

- small
- named after a visible concept
- kept at one level of abstraction

A large page should read like a table of contents:

- nav
- list
- item
- composer
- sidebar

That is easier to maintain than giant templates or heavy component ceremony for every fragment.

## Use Helpers for Small Structural Bits

Helpers are best when they generate:

- a small chunk of HTML
- a consistent tag shape
- repeated data attributes
- a reusable button or link pattern

They are especially useful for wiring Stimulus and Turbo attributes because that wiring is easy to get wrong through repetition.

If the helper starts owning too much branching or multi-part rendering, move back to a partial or a dedicated presenter object.

## Keep Server-Owned HTML as the Default

When the server renders the HTML for list items, stream fragments, and partial updates, you get:

- one rendering path
- better cacheability
- easier designer participation
- less client-side duplication

This is a strong fit for Hotwire applications.

## Let CSS Architecture Be Simple but Intentional

You do not need a utility framework to get organized CSS.

A practical Rails CSS stack often has:

- token files for colors, spacing, and typography
- base element styles
- utility classes for common layout primitives
- feature stylesheets for screens or components

Custom properties are especially useful because they make theme changes and local overrides cheap without creating a giant design-token system prematurely.

## Keep JavaScript Narrow and DOM-Oriented

Stimulus works best when it enhances server-rendered HTML rather than replacing it.

Good jobs for Stimulus:

- focus management
- scroll behavior
- websocket subscriptions
- optimistic insertion of pending UI
- local toggles

Avoid moving rendering rules into JavaScript unless the browser truly owns that interaction.

## Campfire Notes

- `app/views/rooms/show.html.erb` is a good example of partial-driven page composition: nav, invitation, messages, composer, and sidebar are all separate pieces.
- `app/views/messages/_message.html.erb` keeps message rendering server-owned and cacheable.
- Helpers such as `MessagesHelper#message_area_tag`, `MessagesHelper#messages_tag`, and `RoomsHelper#composer_form_tag` centralize repeated `data-controller`, `data-action`, and DOM ID wiring.
- Campfire uses Importmap plus Stimulus, keeping the JavaScript stack small and Rails-native.
- CSS is split into a clear layered structure:
  - `colors.css` for color tokens
  - `utilities.css` for layout and spacing primitives
  - `base.css` for element defaults
  - feature files like `messages.css`, `composer.css`, `sidebar.css`, and `layout.css`
- The application stays on custom CSS instead of Tailwind, and it relies heavily on CSS custom properties for theming and local overrides.
