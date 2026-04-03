# Modern CSS Architecture Without a Build Step

This document describes how to build a maintainable, powerful CSS architecture using modern CSS features, without Tailwind, Sass, or any build step. These patterns work with Rails' asset pipeline (Propshaft) and importmaps, leveraging native CSS capabilities that have matured significantly since 2020.

## The Core Philosophy

Modern CSS has evolved to handle everything we used to need preprocessors for:
- **Variables** → CSS Custom Properties
- **Nesting** → Native CSS Nesting
- **Calculations** → `calc()`, `clamp()`, `min()`, `max()`
- **Color manipulation** → `oklch()`, `color-mix()`
- **Imports** → Cascade Layers + Asset Pipeline

The result: simpler tooling, faster development, and CSS that runs directly in browsers without transformation.

## File Organization

### Many Small Files, One Responsibility Each

Instead of monolithic stylesheets or deeply nested Sass partials, use many small, focused CSS files:

```
app/assets/stylesheets/
├── _global.css          # Design tokens (load first)
├── reset.css            # CSS reset/normalize
├── base.css             # Base element styles
├── layout.css           # Page layout structures
│
├── buttons.css          # Button component
├── cards.css            # Card component
├── inputs.css           # Form inputs
├── icons.css            # Icon system
├── avatars.css          # Avatar component
│
├── header.css           # Header module
├── nav.css              # Navigation module
├── popups.css           # Popup/modal module
├── trays.css            # Slide-out tray module
│
├── utilities.css        # Utility classes (load last)
├── animation.css        # Keyframes and transitions
├── print.css            # Print styles
└── native.css           # Platform-specific (iOS, Android)
```

**Key principles:**
- One component or concern per file
- Files don't import each other (no `@import`)
- Load order controlled by Rails asset pipeline
- Alphabetical ordering within layers works fine
- 50-200 lines per file is ideal

### How Loading Works (No Build)

Rails' Propshaft concatenates all CSS files into one request:

```erb
<%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
```

Configure in `config/initializers/assets.rb`:
```ruby
Rails.application.config.assets.precompile += %w[app.css]
```

The asset pipeline:
1. Finds all `.css` files in the stylesheets directory
2. Concatenates them in order
3. Serves as a single file (with fingerprinting in production)
4. No Sass, no PostCSS, no webpack—just CSS

## Cascade Layers (@layer)

The most important modern CSS feature for architecture is `@layer`. It gives you explicit control over the cascade without specificity wars.

### Defining Layer Order

At the top of your first-loaded file (like `_global.css`):

```css
@layer reset, base, components, modules, utilities;
```

This declaration sets the order. Later layers override earlier ones, regardless of selector specificity.

### Assigning Styles to Layers

Each file declares which layer it belongs to:

```css
/* reset.css */
@layer reset {
  *, *::before, *::after {
    box-sizing: border-box;
  }

  body {
    margin: 0;
  }
}
```

```css
/* buttons.css */
@layer components {
  .btn {
    display: inline-flex;
    padding: var(--btn-padding);
    /* ... */
  }
}
```

```css
/* utilities.css */
@layer utilities {
  .flex { display: flex; }
  .hidden { display: none; }
}
```

### Why Layers Matter

**Without layers:**
```css
/* buttons.css - specificity: 0,1,0 */
.btn { color: blue; }

/* utilities.css - specificity: 0,1,0 */
.text-red { color: red; }

/* Problem: If .btn appears after .text-red in HTML,
   which wins? Depends on file load order. */
```

**With layers:**
```css
@layer components {
  .btn { color: blue; }  /* Always loses to utilities */
}

@layer utilities {
  .text-red { color: red; }  /* Always wins over components */
}
```

Utilities always override components, components always override base—regardless of selector complexity or source order.

## Design Tokens with CSS Custom Properties

### The Token File

Create a comprehensive `_global.css` that defines all your design tokens:

```css
:root {
  /* ========================================
     SPACING
     ======================================== */
  --space-unit: 1rem;
  --space-half: calc(var(--space-unit) / 2);
  --space-quarter: calc(var(--space-unit) / 4);
  --space-double: calc(var(--space-unit) * 2);
  --space-triple: calc(var(--space-unit) * 3);

  /* Inline (horizontal) spacing using ch for text-relative sizing */
  --inline-space: 1ch;
  --inline-space-half: calc(var(--inline-space) / 2);
  --inline-space-double: calc(var(--inline-space) * 2);

  /* ========================================
     TYPOGRAPHY
     ======================================== */
  --font-family-base: system-ui, -apple-system, sans-serif;
  --font-family-mono: ui-monospace, monospace;

  --text-xs: 0.75rem;
  --text-sm: 0.875rem;
  --text-base: 1rem;
  --text-lg: 1.125rem;
  --text-xl: 1.25rem;
  --text-2xl: 1.5rem;
  --text-3xl: 2rem;

  --line-height-tight: 1.25;
  --line-height-normal: 1.5;
  --line-height-relaxed: 1.75;

  --font-weight-normal: 400;
  --font-weight-medium: 500;
  --font-weight-bold: 700;

  /* ========================================
     COLORS (using OKLCH for perceptual uniformity)
     ======================================== */
  --color-ink: oklch(20% 0.02 250);
  --color-ink-light: oklch(40% 0.02 250);
  --color-ink-lighter: oklch(60% 0.01 250);

  --color-canvas: oklch(100% 0 0);
  --color-canvas-subtle: oklch(97% 0.005 250);
  --color-canvas-muted: oklch(94% 0.01 250);

  --color-primary: oklch(55% 0.25 250);
  --color-primary-hover: oklch(45% 0.25 250);

  --color-positive: oklch(55% 0.2 145);
  --color-negative: oklch(55% 0.2 25);
  --color-warning: oklch(70% 0.15 85);

  --color-border: oklch(85% 0.01 250);
  --color-border-strong: oklch(75% 0.02 250);

  /* ========================================
     SHADOWS
     ======================================== */
  --shadow-sm: 0 1px 2px oklch(20% 0.02 250 / 0.05);
  --shadow-md:
    0 1px 3px oklch(20% 0.02 250 / 0.1),
    0 1px 2px oklch(20% 0.02 250 / 0.06);
  --shadow-lg:
    0 4px 6px oklch(20% 0.02 250 / 0.1),
    0 2px 4px oklch(20% 0.02 250 / 0.06);

  /* ========================================
     BORDERS & RADII
     ======================================== */
  --radius-sm: 0.25rem;
  --radius-md: 0.5rem;
  --radius-lg: 1rem;
  --radius-full: 9999px;

  --border-width: 1px;

  /* ========================================
     TRANSITIONS
     ======================================== */
  --duration-fast: 100ms;
  --duration-normal: 200ms;
  --duration-slow: 300ms;

  --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-out-expo: cubic-bezier(0.19, 1, 0.22, 1);
  --ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);

  /* ========================================
     FOCUS RING
     ======================================== */
  --focus-ring-color: var(--color-primary);
  --focus-ring-size: 2px;
  --focus-ring-offset: 2px;

  /* ========================================
     Z-INDEX SCALE
     ======================================== */
  --z-dropdown: 100;
  --z-sticky: 200;
  --z-modal: 300;
  --z-popover: 400;
  --z-tooltip: 500;
}
```

### Why OKLCH for Colors

OKLCH (Lightness, Chroma, Hue) is perceptually uniform—a 10% lightness change looks the same across all hues. This makes color manipulation predictable:

```css
/* Creating color variations is intuitive */
--blue: oklch(55% 0.25 250);
--blue-light: oklch(70% 0.2 250);   /* Just increase L */
--blue-dark: oklch(40% 0.25 250);   /* Just decrease L */
--blue-muted: oklch(55% 0.1 250);   /* Just decrease C */
```

### Responsive Tokens

Adjust tokens at breakpoints for responsive typography:

```css
:root {
  --text-base: 1rem;
  --text-lg: 1.125rem;
}

@media (max-width: 640px) {
  :root {
    --text-base: 0.9375rem;
    --text-lg: 1rem;
  }
}
```

## Dark Mode Implementation

### The Pattern

Support both explicit user preference and system preference:

```css
/* Light mode (default) */
:root {
  --color-canvas: oklch(100% 0 0);
  --color-ink: oklch(20% 0.02 250);
  /* ... all color tokens */
}

/* Dark mode: explicit user choice */
html[data-theme="dark"] {
  --color-canvas: oklch(15% 0.02 250);
  --color-ink: oklch(95% 0.01 250);
  /* ... remap all color tokens */
}

/* Dark mode: system preference (when no explicit choice) */
@media (prefers-color-scheme: dark) {
  html:not([data-theme]) {
    --color-canvas: oklch(15% 0.02 250);
    --color-ink: oklch(95% 0.01 250);
    /* ... same remapping */
  }
}
```

### JavaScript Theme Controller

A Stimulus controller to manage theme preference:

```javascript
// theme_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle() {
    const current = document.documentElement.dataset.theme
    const next = current === "dark" ? "light" : "dark"
    document.documentElement.dataset.theme = next
    localStorage.setItem("theme", next)
  }

  connect() {
    const saved = localStorage.getItem("theme")
    if (saved) {
      document.documentElement.dataset.theme = saved
    }
  }
}
```

### Meta Tags for Browser Chrome

```erb
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0d181d" media="(prefers-color-scheme: dark)">
```

## Modern CSS Selectors

### :has() - The Parent Selector

The game-changer. Select elements based on their descendants:

```css
/* Card with an image gets different padding */
.card:has(> .card__image) {
  padding-top: 0;
}

/* Form group with invalid input shows error styling */
.form-group:has(:invalid) {
  --border-color: var(--color-negative);
}

/* Navigation item with active child gets highlight */
.nav-item:has(.is-active) {
  background: var(--color-canvas-subtle);
}
```

### :where() - Zero Specificity

Wrap selectors to reduce their specificity to zero:

```css
/* These utility classes won't fight with component styles */
:where(.flex) { display: flex; }
:where(.hidden) { display: none; }
:where(.text-center) { text-align: center; }

/* Easy to override even with low-specificity selectors */
.modal .text-center { text-align: left; }  /* Works! */
```

### :is() - Grouping Selectors

Combine selectors while taking the highest specificity:

```css
/* Style all interactive elements consistently */
:is(a, button, input, textarea, select):focus-visible {
  outline: var(--focus-ring-size) solid var(--focus-ring-color);
  outline-offset: var(--focus-ring-offset);
}

/* Apply to multiple heading levels */
:is(h1, h2, h3, h4, h5, h6) {
  font-weight: var(--font-weight-bold);
  line-height: var(--line-height-tight);
}
```

### Native CSS Nesting

No preprocessor needed—browsers support nesting natively:

```css
.card {
  background: var(--color-canvas);
  border-radius: var(--radius-md);

  &:hover {
    box-shadow: var(--shadow-md);
  }

  &.is-selected {
    border-color: var(--color-primary);
  }

  & .card__title {
    font-weight: var(--font-weight-bold);
  }

  @media (max-width: 640px) {
    padding: var(--space-half);
  }
}
```

## Component Patterns

### Naming Convention (BEM-inspired)

```css
/* Block */
.card { }

/* Element (child) */
.card__header { }
.card__body { }
.card__footer { }

/* Modifier (variant) */
.card--featured { }
.card--compact { }

/* State (dynamic) */
.card.is-selected { }
.card.is-loading { }
```

### Component Variables Pattern

Define component-specific variables for customization:

```css
.btn {
  /* Component tokens with defaults */
  --btn-padding-block: var(--space-half);
  --btn-padding-inline: var(--space-unit);
  --btn-background: var(--color-primary);
  --btn-color: white;
  --btn-radius: var(--radius-md);
  --btn-font-weight: var(--font-weight-medium);

  /* Use the tokens */
  display: inline-flex;
  align-items: center;
  gap: var(--space-half);
  padding: var(--btn-padding-block) var(--btn-padding-inline);
  background: var(--btn-background);
  color: var(--btn-color);
  border-radius: var(--btn-radius);
  font-weight: var(--btn-font-weight);

  &:hover {
    filter: brightness(0.9);
  }
}

/* Variants override the tokens */
.btn--secondary {
  --btn-background: transparent;
  --btn-color: var(--color-primary);
}

.btn--danger {
  --btn-background: var(--color-negative);
}

.btn--small {
  --btn-padding-block: var(--space-quarter);
  --btn-padding-inline: var(--space-half);
}
```

### Derived Colors with color-mix()

Automatically derive related colors:

```css
.card {
  /* User sets one color */
  --card-color: oklch(55% 0.2 250);

  /* Derive background (lighter, less saturated) */
  --card-background: color-mix(
    in oklch,
    var(--card-color) 15%,
    var(--color-canvas)
  );

  /* Derive border (slightly darker) */
  --card-border-color: color-mix(
    in oklch,
    var(--card-color) 30%,
    var(--color-canvas)
  );

  background: var(--card-background);
  border: 1px solid var(--card-border-color);
}
```

## Utility Classes (The Right Amount)

### Layout Utilities

```css
@layer utilities {
  /* Display */
  :where(.flex) { display: flex; }
  :where(.grid) { display: grid; }
  :where(.hidden) { display: none; }
  :where(.block) { display: block; }

  /* Flex direction */
  :where(.flex-column) { flex-direction: column; }
  :where(.flex-row) { flex-direction: row; }

  /* Alignment */
  :where(.items-center) { align-items: center; }
  :where(.items-start) { align-items: flex-start; }
  :where(.justify-between) { justify-content: space-between; }
  :where(.justify-center) { justify-content: center; }

  /* Gap */
  :where(.gap) { gap: var(--space-unit); }
  :where(.gap-half) { gap: var(--space-half); }
  :where(.gap-double) { gap: var(--space-double); }

  /* Padding */
  :where(.pad) { padding: var(--space-unit); }
  :where(.pad-half) { padding: var(--space-half); }
  :where(.pad-block) { padding-block: var(--space-unit); }
  :where(.pad-inline) { padding-inline: var(--space-unit); }

  /* Margin */
  :where(.margin-block) { margin-block: var(--space-unit); }
  :where(.margin-auto) { margin: auto; }
}
```

### Typography Utilities

```css
@layer utilities {
  :where(.text-sm) { font-size: var(--text-sm); }
  :where(.text-base) { font-size: var(--text-base); }
  :where(.text-lg) { font-size: var(--text-lg); }

  :where(.font-bold) { font-weight: var(--font-weight-bold); }
  :where(.font-medium) { font-weight: var(--font-weight-medium); }

  :where(.text-center) { text-align: center; }
  :where(.text-muted) { color: var(--color-ink-light); }

  :where(.truncate) {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
}
```

### When to Use Utilities vs Components

**Use utilities for:**
- One-off layout adjustments
- Spacing tweaks
- Simple text formatting
- Responsive visibility

**Use components for:**
- Repeated UI patterns (buttons, cards, forms)
- Complex styling with multiple properties
- Interactive states
- Anything with variants

## The Icon System (SVG + CSS Masks)

This is an elegant pattern for colorable, scalable icons without icon fonts or complex SVG embedding.

### How It Works

1. SVG files stored as static assets
2. CSS uses `mask-image` to apply the SVG as a mask
3. `background-color: currentColor` makes the icon inherit text color
4. Sizing via CSS variables

### Icon CSS

```css
@layer components {
  .icon {
    /* Inherit color from parent text */
    background-color: currentColor;

    /* Size control */
    --icon-size: 1em;
    width: var(--icon-size);
    height: var(--icon-size);

    /* The SVG becomes a mask */
    mask-image: var(--svg);
    mask-size: contain;
    mask-repeat: no-repeat;
    mask-position: center;

    /* Also support webkit */
    -webkit-mask-image: var(--svg);
    -webkit-mask-size: contain;
    -webkit-mask-repeat: no-repeat;
    -webkit-mask-position: center;

    /* Inline display */
    display: inline-block;
    vertical-align: middle;
    flex-shrink: 0;
  }

  /* Icon definitions */
  .icon--add { --svg: url("add.svg"); }
  .icon--arrow-left { --svg: url("arrow-left.svg"); }
  .icon--check { --svg: url("check.svg"); }
  .icon--close { --svg: url("close.svg"); }
  .icon--menu { --svg: url("menu.svg"); }
  .icon--search { --svg: url("search.svg"); }
  /* ... more icons */
}
```

### Using Icons in HTML

```erb
<button class="btn">
  <span class="icon icon--add"></span>
  Add Item
</button>

<a href="..." class="btn btn--icon-only">
  <span class="icon icon--close" style="--icon-size: 1.5em"></span>
</a>
```

### Benefits of This Approach

1. **Colorable**: Icons automatically match text color
2. **Scalable**: Change size with one CSS variable
3. **No HTTP requests**: SVGs are inlined by asset pipeline
4. **No JavaScript**: Pure CSS solution
5. **No icon fonts**: Better accessibility, no FOUT
6. **Easy to add icons**: Just drop SVG in assets folder

## Setting Up a Local Icon Library

### Choosing an Icon Source

Recommended open-source icon libraries:

| Library | Style | License | Notes |
|---------|-------|---------|-------|
| [Lucide](https://lucide.dev) | Outlined | ISC | Fork of Feather, very active |
| [Heroicons](https://heroicons.com) | Outlined/Solid | MIT | From Tailwind team |
| [Phosphor](https://phosphoricons.com) | Multiple weights | MIT | Very comprehensive |
| [Tabler Icons](https://tabler-icons.io) | Outlined | MIT | Large collection |
| [Remix Icon](https://remixicon.com) | Outlined/Filled | Apache 2.0 | Good variety |

### Directory Structure

```
app/assets/images/icons/
├── add.svg
├── arrow-left.svg
├── arrow-right.svg
├── check.svg
├── chevron-down.svg
├── close.svg
├── edit.svg
├── menu.svg
├── search.svg
├── trash.svg
└── ...
```

### SVG Optimization

Before adding icons, optimize them:

1. **Remove unnecessary attributes**: `width`, `height`, `fill` (let CSS control these)
2. **Remove metadata**: Comments, editor data
3. **Use `currentColor`**: For stroke or fill that should inherit

Optimized SVG example:
```xml
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <line x1="12" y1="5" x2="12" y2="19"/>
  <line x1="5" y1="12" x2="19" y2="12"/>
</svg>
```

### Rake Task to Import Icons

Create a task to pull icons from your chosen library:

```ruby
# lib/tasks/icons.rake
namespace :icons do
  desc "Import icons from Lucide"
  task :import do
    require 'fileutils'
    require 'open-uri'

    # Icons you want to use
    icons = %w[
      plus minus x check
      chevron-up chevron-down chevron-left chevron-right
      arrow-up arrow-down arrow-left arrow-right
      search menu settings user
      edit trash copy clipboard
      eye eye-off lock unlock
      mail phone calendar clock
      folder file image link
      heart star bookmark flag
      bell alert-circle info help-circle
    ]

    output_dir = Rails.root.join("app/assets/images/icons")
    FileUtils.mkdir_p(output_dir)

    icons.each do |icon|
      url = "https://unpkg.com/lucide-static@latest/icons/#{icon}.svg"
      content = URI.open(url).read

      # Optimize: remove width/height, ensure currentColor
      content = content
        .gsub(/\s*width="[^"]*"/, '')
        .gsub(/\s*height="[^"]*"/, '')
        .gsub(/stroke="[^"]*"/, 'stroke="currentColor"')

      File.write(output_dir.join("#{icon}.svg"), content)
      puts "Downloaded: #{icon}.svg"
    end
  end
end
```

Run with: `rails icons:import`

### Generate Icon CSS Classes

Create a task to generate icon CSS from your SVG files:

```ruby
# lib/tasks/icons.rake
namespace :icons do
  desc "Generate icon CSS classes"
  task :css do
    icons_dir = Rails.root.join("app/assets/images/icons")
    css_file = Rails.root.join("app/assets/stylesheets/icons.css")

    icons = Dir.glob(icons_dir.join("*.svg")).map do |path|
      File.basename(path, ".svg")
    end

    css = <<~CSS
      @layer components {
        .icon {
          background-color: currentColor;
          --icon-size: 1em;
          width: var(--icon-size);
          height: var(--icon-size);
          mask-image: var(--svg);
          mask-size: contain;
          mask-repeat: no-repeat;
          mask-position: center;
          -webkit-mask-image: var(--svg);
          -webkit-mask-size: contain;
          -webkit-mask-repeat: no-repeat;
          -webkit-mask-position: center;
          display: inline-block;
          vertical-align: middle;
          flex-shrink: 0;
        }

        #{icons.map { |name| ".icon--#{name} { --svg: url(\"icons/#{name}.svg\"); }" }.join("\n  ")}
      }
    CSS

    File.write(css_file, css)
    puts "Generated #{css_file} with #{icons.length} icons"
  end
end
```

### Icon Helper

Create a helper for easier icon usage:

```ruby
# app/helpers/icon_helper.rb
module IconHelper
  def icon(name, size: nil, **options)
    classes = ["icon", "icon--#{name}", options.delete(:class)].compact.join(" ")
    style = size ? "--icon-size: #{size};" : nil

    tag.span(class: classes, style: style, **options)
  end
end
```

Usage in views:
```erb
<%= icon "plus" %>
<%= icon "search", size: "1.5em" %>
<%= icon "check", class: "text-positive" %>
```

## Animation and Transitions

### Base Transition Setup

Apply subtle transitions to interactive elements:

```css
@layer base {
  :is(a, button, input, textarea, select, .btn) {
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease-out);
    transition-property:
      background-color,
      border-color,
      box-shadow,
      color,
      opacity,
      transform;
  }
}
```

### Keyframe Animations

```css
@layer utilities {
  @keyframes fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slide-up {
    from {
      opacity: 0;
      transform: translateY(1rem);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .animate-fade-in {
    animation: fade-in var(--duration-normal) var(--ease-out);
  }

  .animate-slide-up {
    animation: slide-up var(--duration-normal) var(--ease-out);
  }

  .animate-spin {
    animation: spin 1s linear infinite;
  }
}
```

### Reduced Motion

Always respect user preferences:

```css
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

### View Transitions (with Turbo)

For smooth page transitions:

```css
/* Named elements animate between pages */
.header {
  view-transition-name: header;
}

.sidebar {
  view-transition-name: sidebar;
}

/* Customize the transition */
::view-transition-old(header) {
  animation: fade-out var(--duration-fast);
}

::view-transition-new(header) {
  animation: fade-in var(--duration-fast);
}
```

## Accessibility

### Focus Styles

Never remove focus outlines—make them beautiful:

```css
@layer base {
  :is(a, button, input, textarea, select, [tabindex]):focus-visible {
    outline: var(--focus-ring-size) solid var(--focus-ring-color);
    outline-offset: var(--focus-ring-offset);
  }

  /* Remove default outline since we're using custom */
  :is(a, button, input, textarea, select, [tabindex]):focus:not(:focus-visible) {
    outline: none;
  }
}
```

### Screen Reader Only Content

```css
@layer utilities {
  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }
}
```

### Skip Navigation

```css
.skip-link {
  position: absolute;
  left: -9999px;
  z-index: var(--z-tooltip);
  padding: var(--space-half) var(--space-unit);
  background: var(--color-canvas);

  &:focus {
    left: var(--space-unit);
    top: var(--space-unit);
  }
}
```

## Print Styles

```css
@layer utilities {
  @media print {
    /* Hide interactive elements */
    nav,
    .btn,
    .no-print {
      display: none !important;
    }

    /* Force colors to print */
    * {
      print-color-adjust: exact;
      -webkit-print-color-adjust: exact;
    }

    /* Prevent awkward page breaks */
    .card,
    .section {
      break-inside: avoid;
    }

    /* Sensible text settings */
    body {
      font-size: 12pt;
      line-height: 1.5;
      color: black;
      background: white;
    }

    /* Show link URLs */
    a[href]::after {
      content: " (" attr(href) ")";
      font-size: 0.8em;
      color: gray;
    }
  }
}
```

## Responsive Design

Modern CSS provides powerful tools for responsive design that go far beyond simple media query breakpoints. The approach combines fluid sizing, container queries, and interaction detection for truly adaptive interfaces.

### Breakpoint Strategy

Use a small set of consistent breakpoints throughout your application:

| Breakpoint | Target | Usage |
|------------|--------|-------|
| 640px | Tablet | Primary breakpoint for layout shifts |
| 960px | Desktop | Secondary breakpoint for wider layouts |

Define styles mobile-first, then enhance for larger screens:

```css
/* Mobile: single column (default) */
.card-grid {
  --columns: 1;
  display: grid;
  grid-template-columns: repeat(var(--columns), 1fr);
  gap: var(--space-unit);
}

/* Tablet: two columns */
@media (min-width: 640px) {
  .card-grid {
    --columns: 2;
  }
}

/* Desktop: three columns */
@media (min-width: 960px) {
  .card-grid {
    --columns: 3;
  }
}
```

### Fluid Sizing with clamp()

Instead of jumping between fixed values at breakpoints, use `clamp()` for smooth scaling:

```css
/* clamp(minimum, preferred, maximum) */

/* Fluid typography */
.hero-title {
  font-size: clamp(var(--text-xl), 5vw, var(--text-3xl));
}

/* Fluid spacing */
.section {
  padding: clamp(var(--space-unit), 4vw, var(--space-triple));
}

/* Fluid container width */
.container {
  max-width: min(65ch, calc(100vw - var(--space-double)));
  margin-inline: auto;
}
```

**When to use which:**
- `clamp(min, preferred, max)` - Value scales but stays within bounds
- `min(a, b)` - Use the smaller of two values (great for max-widths)
- `max(a, b)` - Use the larger of two values (great for min-heights)

### Responsive Typography

Adjust the base type scale at breakpoints, then let components inherit:

```css
:root {
  --text-sm: 0.875rem;
  --text-base: 1rem;
  --text-lg: 1.125rem;
  --text-xl: 1.25rem;
  --text-2xl: 1.5rem;
}

/* Slightly smaller on mobile */
@media (max-width: 639px) {
  :root {
    --text-sm: 0.8125rem;
    --text-base: 0.9375rem;
    --text-lg: 1rem;
    --text-xl: 1.125rem;
    --text-2xl: 1.375rem;
  }
}
```

Components use the tokens and automatically adapt:

```css
.card__title {
  font-size: var(--text-lg);  /* Adapts based on breakpoint */
}
```

For truly fluid typography (scales with viewport):

```css
.hero__title {
  font-size: clamp(var(--text-xl), 4vw + 1rem, var(--text-3xl));
}
```

### Container Queries

Media queries respond to the viewport. Container queries respond to a parent element's size—essential for reusable components:

```css
/* Define a container */
.card-container {
  container-type: inline-size;
}

/* Query the container's width */
.card {
  display: flex;
  flex-direction: column;
}

@container (min-width: 400px) {
  .card {
    flex-direction: row;
  }
}
```

**Container query units:**
- `cqi` - 1% of container's inline size (width)
- `cqb` - 1% of container's block size (height)

```css
.card-container {
  container-type: inline-size;
}

.card__title {
  /* Font scales with card width, not viewport */
  font-size: clamp(0.875rem, 4cqi, 1.25rem);
}

.card__icon {
  /* Icon scales with container */
  --icon-size: clamp(1rem, 8cqi, 2rem);
}
```

**When to use container vs media queries:**
- **Media queries**: Page layout, navigation visibility, major structural changes
- **Container queries**: Component internals that should adapt to available space

### Touch and Hover Detection

Not all devices support hover. Detect input capabilities:

```css
/* Only show hover effects on devices that support hover */
@media (any-hover: hover) {
  .btn:hover {
    background: var(--color-primary-hover);
  }

  .card:hover {
    box-shadow: var(--shadow-lg);
  }
}

/* Alternative styles for touch devices */
@media (any-hover: none) {
  /* Touch devices: use active state instead */
  .btn:active {
    background: var(--color-primary-hover);
  }

  /* Hide hover-only UI hints */
  .tooltip-on-hover {
    display: none;
  }

  /* Hide keyboard shortcut hints */
  kbd {
    display: none;
  }
}
```

**Pointer precision detection:**

```css
/* Fine pointer (mouse) - can use smaller targets */
@media (pointer: fine) {
  .btn--small {
    padding: var(--space-quarter) var(--space-half);
  }
}

/* Coarse pointer (touch) - need larger tap targets */
@media (pointer: coarse) {
  .btn--small {
    padding: var(--space-half) var(--space-unit);
    min-height: 44px;  /* Apple's recommended touch target */
  }
}
```

### Modern Viewport Units

Use dynamic viewport units to handle mobile browser chrome (URL bar, etc.):

| Unit | Description |
|------|-------------|
| `dvw` / `dvh` | Dynamic viewport (changes as browser UI shows/hides) |
| `svw` / `svh` | Small viewport (browser UI visible) |
| `lvw` / `lvh` | Large viewport (browser UI hidden) |

```css
/* Full-height hero that accounts for mobile browser chrome */
.hero {
  min-height: 100dvh;
}

/* Modal that doesn't get cut off by URL bar */
.modal {
  max-height: 90dvh;
}
```

### Safe Area Insets

Support notched phones and PWAs with safe area insets:

```css
.header {
  padding-top: calc(var(--space-unit) + env(safe-area-inset-top));
  padding-left: calc(var(--space-unit) + env(safe-area-inset-left));
  padding-right: calc(var(--space-unit) + env(safe-area-inset-right));
}

.footer {
  padding-bottom: calc(var(--space-unit) + env(safe-area-inset-bottom));
}
```

Enable in your viewport meta tag:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
```

### Responsive Utilities

Create utilities for common responsive patterns:

```css
@layer utilities {
  /* Hide on touch devices */
  :where(.hide-on-touch) {
    @media (any-hover: none) {
      display: none;
    }
  }

  /* Show only on touch devices */
  :where(.show-on-touch) {
    display: none;
    @media (any-hover: none) {
      display: unset;
    }
  }

  /* Hide in standalone PWA mode */
  :where(.hide-in-pwa) {
    @media (display-mode: standalone) {
      display: none;
    }
  }

  /* Hide in browser (show only in PWA) */
  :where(.hide-in-browser) {
    @media (display-mode: browser) {
      display: none;
    }
  }

  /* Responsive visibility */
  :where(.hide-mobile) {
    @media (max-width: 639px) {
      display: none;
    }
  }

  :where(.hide-desktop) {
    @media (min-width: 640px) {
      display: none;
    }
  }
}
```

### Component-Level Responsive Patterns

#### Pattern: CSS Variable Overrides

Override component variables at breakpoints:

```css
.card {
  --card-padding: var(--space-half);
  --card-gap: var(--space-half);

  padding: var(--card-padding);
  gap: var(--card-gap);
}

@media (min-width: 640px) {
  .card {
    --card-padding: var(--space-unit);
    --card-gap: var(--space-unit);
  }
}
```

#### Pattern: Swap Layouts

```css
.feature {
  display: flex;
  flex-direction: column;
  gap: var(--space-unit);
}

@media (min-width: 640px) {
  .feature {
    flex-direction: row;
    align-items: center;
  }

  .feature__content {
    flex: 1;
  }

  .feature__image {
    flex: 0 0 40%;
  }
}
```

#### Pattern: Show/Hide Elements

```css
.nav__menu-button {
  display: flex;
}

.nav__links {
  display: none;
}

@media (min-width: 640px) {
  .nav__menu-button {
    display: none;
  }

  .nav__links {
    display: flex;
  }
}
```

### Reduced Motion

Always respect user preferences for reduced motion:

```css
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

### The Responsive Philosophy

1. **Start mobile**: Write base styles for the smallest screens
2. **Enhance progressively**: Add complexity for larger screens with `min-width`
3. **Use fluid values**: Prefer `clamp()` over fixed breakpoint jumps
4. **Component-level adaptation**: Use container queries for reusable components
5. **Detect capabilities**: Use `any-hover` and `pointer` for input-aware styling
6. **Modern units**: Use `dvh`/`dvw` for viewport, `cqi` for containers
7. **Respect preferences**: Honor `prefers-reduced-motion` and `prefers-color-scheme`

This approach creates interfaces that adapt smoothly across the full spectrum of devices, from phones to ultrawide monitors, from touch to mouse, from low-power mode to full animation.

## Summary: The No-Build CSS Stack

**What you need:**
- Rails with Propshaft (or Sprockets)
- Plain `.css` files
- Modern browsers (2020+)

**What you don't need:**
- Sass/SCSS
- PostCSS
- Tailwind
- Webpack/esbuild for CSS
- Any CSS build step

**Key patterns:**
1. **@layer** for cascade control
2. **CSS Custom Properties** for design tokens
3. **Native nesting** instead of Sass
4. **:has(), :where(), :is()** for powerful selectors
5. **oklch() and color-mix()** for color manipulation
6. **mask-image** for colorable icons
7. **Many small files** organized by concern
8. **Component variables** for customizable components
9. **Minimal utilities** for layout and spacing

This approach produces CSS that is:
- Easier to debug (no source maps needed)
- Faster to develop (no compilation)
- Smaller (no framework overhead)
- More maintainable (clear organization)
- More powerful (modern CSS features)

Modern CSS has grown up. Use it directly.
