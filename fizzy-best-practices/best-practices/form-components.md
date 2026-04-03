# Professional Form Components in Rails

This document describes patterns for building consistent, accessible, and feature-rich form components in Rails applications. These patterns achieve a professional look and advanced functionality using CSS custom properties, Stimulus controllers, and progressive enhancement.

## The Core Philosophy

Form components should be:
- **Consistent** - All inputs share visual language through CSS custom properties
- **Accessible** - Proper labels, ARIA, keyboard navigation, focus management
- **Progressive** - Work without JavaScript, enhanced with Stimulus
- **Mobile-friendly** - Touch targets, iOS zoom prevention, responsive sizing

## Base Input Styling

### The .input Class

Create a foundational input class using CSS custom properties for complete customization:

```css
@layer components {
  .input {
    /* Customization points */
    --input-background: transparent;
    --input-border-color: var(--color-border);
    --input-border-radius: 0.5em;
    --input-border-size: 1px;
    --input-color: var(--color-ink);
    --input-padding: 0.5em 0.75em;

    /* Applied styles */
    background-color: var(--input-background);
    border: var(--input-border-size) solid var(--input-border-color);
    border-radius: var(--input-border-radius);
    color: var(--input-color);
    padding: var(--input-padding);

    /* Prevent iOS zoom on focus (must be 16px+) */
    font-size: max(16px, 1em);

    /* Full width by default */
    inline-size: 100%;

    /* Accent color for checkboxes/radios */
    accent-color: var(--color-primary);

    /* Focus state */
    &:focus-visible {
      outline: var(--focus-ring-size) solid var(--focus-ring-color);
      outline-offset: var(--focus-ring-offset);
    }

    /* Disabled state */
    &:disabled {
      cursor: not-allowed;
      opacity: 0.5;
    }

    /* Placeholder styling */
    &::placeholder {
      color: var(--color-ink-light);
      opacity: 1;
    }
  }
}
```

### Handling Autofill

Browsers style autofilled inputs with a yellow background. Override it:

```css
.input:autofill,
.input:-webkit-autofill {
  /* Force text color */
  -webkit-text-fill-color: var(--color-ink);

  /* Override yellow background with large inset shadow */
  -webkit-box-shadow: 0 0 0 1000px var(--color-canvas-subtle) inset;
  box-shadow: 0 0 0 1000px var(--color-canvas-subtle) inset;
}
```

### Input Variants

**Select inputs with custom caret:**

```css
.input--select {
  --caret-icon: url("data:image/svg+xml,...");

  appearance: none;
  background-image: var(--caret-icon);
  background-position: right 0.75em center;
  background-repeat: no-repeat;
  background-size: 1em;
  padding-inline-end: 2.5em;

  /* Pill shape for compact selects */
  border-radius: 2em;
}

/* Dark mode caret */
@media (prefers-color-scheme: dark) {
  .input--select {
    --caret-icon: url("data:image/svg+xml,..."); /* Light version */
  }
}
```

**Textarea:**

```css
.input--textarea {
  /* Modern browsers: auto-grow with content */
  field-sizing: content;

  /* Fallback for older browsers */
  @supports not (field-sizing: content) {
    min-block-size: 6em;
  }

  /* Allow vertical resize only */
  resize: vertical;
}
```

**One-time code input (for magic links):**

```css
.input--code {
  font-family: var(--font-mono);
  font-weight: 700;
  letter-spacing: 0.5ch;
  text-align: center;
  inline-size: 12ch;
}
```

## Auto-Growing Textareas

For browsers without `field-sizing: content`, use a CSS grid trick:

### The Pattern

```html
<label class="autoresize" data-controller="autoresize">
  <div class="autoresize__wrapper" data-autoresize-target="wrapper">
    <textarea
      class="autoresize__textarea input"
      data-autoresize-target="textarea"
      data-action="input->autoresize#resize"
    ></textarea>
  </div>
</label>
```

### CSS

```css
@supports not (field-sizing: content) {
  .autoresize__wrapper {
    display: grid;
    position: relative;

    /* Both textarea and pseudo-element occupy same grid cell */
    > *,
    &::after {
      grid-area: 1 / 1;
    }

    /* Invisible clone that drives the height */
    &::after {
      content: attr(data-clone-value) " ";
      visibility: hidden;
      white-space: pre-wrap;

      /* Match textarea styling */
      padding: var(--input-padding);
      font: inherit;
      border: var(--input-border-size) solid transparent;
    }
  }

  .autoresize__textarea {
    /* Overlay the pseudo-element */
    position: absolute;
    inset: 0;
    overflow: hidden;
    resize: none;
  }
}
```

### Stimulus Controller

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "wrapper"]

  connect() {
    this.resize()
  }

  resize() {
    // Copy value to wrapper's data attribute for CSS ::after content
    this.wrapperTarget.dataset.cloneValue = this.textareaTarget.value
  }
}
```

The trick: A CSS `::after` pseudo-element mirrors the textarea content (via `attr()`), sized naturally. The textarea overlays it, inheriting the height.

## Toggle Switches

Pure CSS toggle switches that are accessible and animated.

### HTML Structure

```html
<label class="switch">
  <input type="checkbox" class="switch__input" name="enabled">
  <span class="switch__track"></span>
  <span class="sr-only">Enable feature</span>
</label>
```

### CSS

```css
.switch {
  --switch-width: 3em;
  --switch-height: 1.75em;
  --switch-track-color: var(--color-border-strong);
  --switch-track-color-checked: var(--color-primary);
  --switch-knob-size: 1.35em;
  --switch-knob-color: white;
  --switch-padding: 0.2em;

  display: inline-flex;
  position: relative;
  cursor: pointer;
}

/* Hide the actual checkbox but keep it accessible */
.switch__input {
  position: absolute;
  opacity: 0;
  width: 0;
  height: 0;
}

.switch__track {
  display: block;
  width: var(--switch-width);
  height: var(--switch-height);
  background-color: var(--switch-track-color);
  border-radius: var(--switch-height);
  transition: background-color 150ms ease;
  position: relative;

  /* The knob */
  &::before {
    content: "";
    position: absolute;
    width: var(--switch-knob-size);
    height: var(--switch-knob-size);
    background-color: var(--switch-knob-color);
    border-radius: 50%;
    top: var(--switch-padding);
    left: var(--switch-padding);
    transition: transform 150ms ease;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
  }
}

/* Checked state */
.switch__input:checked + .switch__track {
  background-color: var(--switch-track-color-checked);

  &::before {
    transform: translateX(calc(var(--switch-width) - var(--switch-knob-size) - var(--switch-padding) * 2));
  }
}

/* Focus state */
.switch__input:focus-visible + .switch__track {
  outline: var(--focus-ring-size) solid var(--focus-ring-color);
  outline-offset: var(--focus-ring-offset);
}

/* Disabled state */
.switch__input:disabled + .switch__track {
  opacity: 0.5;
  cursor: not-allowed;
}
```

### Instant Submit on Toggle

```erb
<label class="switch">
  <%= form.check_box :published, class: "switch__input",
        data: { action: "change->form#submit" } %>
  <span class="switch__track"></span>
</label>
```

## Searchable Combobox

A dropdown select with search/filter capabilities and keyboard navigation.

### HTML Structure

```html
<div
  class="combobox"
  data-controller="combobox dialog"
  data-combobox-selection-attribute-value="aria-selected"
>
  <!-- Trigger button -->
  <button type="button" class="btn input input--select" data-action="dialog#toggle">
    <span data-combobox-target="label">Select an option...</span>
  </button>

  <!-- Hidden field for form submission -->
  <template data-combobox-target="hiddenFieldTemplate">
    <input type="hidden" name="category_id">
  </template>

  <!-- Dropdown dialog -->
  <dialog
    class="combobox__dialog popup"
    data-dialog-target="dialog"
    data-controller="navigable-list filter"
  >
    <!-- Search input -->
    <input
      type="search"
      class="input combobox__search"
      placeholder="Search..."
      data-action="input->filter#filter"
      data-filter-target="input"
    >

    <!-- Options list -->
    <ul role="listbox" class="combobox__list" data-filter-target="list">
      <li
        role="option"
        aria-selected="false"
        data-value="1"
        data-action="click->combobox#select"
        data-filter-target="item"
      >
        Option One
      </li>
      <li
        role="option"
        aria-selected="false"
        data-value="2"
        data-action="click->combobox#select"
        data-filter-target="item"
      >
        Option Two
      </li>
    </ul>
  </dialog>
</div>
```

### Combobox Controller

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label", "hiddenFieldTemplate"]
  static values = {
    selectionAttribute: { type: String, default: "aria-selected" }
  }

  select(event) {
    const item = event.currentTarget

    // Deselect all
    this.#items.forEach(i => {
      i.setAttribute(this.selectionAttributeValue, "false")
    })

    // Select clicked item
    item.setAttribute(this.selectionAttributeValue, "true")

    // Update label
    this.labelTarget.textContent = item.textContent.trim()

    // Update hidden field
    this.#updateHiddenField(item.dataset.value)

    // Close dialog
    this.dispatch("selected", { detail: { value: item.dataset.value } })
  }

  get #items() {
    return this.element.querySelectorAll("[role='option']")
  }

  #updateHiddenField(value) {
    // Remove existing hidden field
    const existing = this.element.querySelector("input[type='hidden'][name]")
    existing?.remove()

    // Clone template and set value
    const template = this.hiddenFieldTemplateTarget
    const clone = template.content.cloneNode(true)
    const input = clone.querySelector("input")
    input.value = value

    this.element.appendChild(clone)
  }
}
```

### Multi-Select Combobox

For selecting multiple values:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label", "hiddenFieldTemplate"]
  static values = {
    selectionAttribute: { type: String, default: "aria-checked" },
    noSelectionLabel: { type: String, default: "Select..." },
    labelPrefix: String
  }

  toggle(event) {
    const item = event.currentTarget
    const isSelected = item.getAttribute(this.selectionAttributeValue) === "true"

    // Toggle selection
    item.setAttribute(this.selectionAttributeValue, String(!isSelected))

    // Check for exclusive selections (like "All" or "None")
    if (item.hasAttribute("data-exclusive")) {
      this.#deselectAllExcept(item)
    } else {
      this.#deselectExclusiveItems()
    }

    this.#updateLabel()
    this.#updateHiddenFields()
  }

  get #selectedItems() {
    return [...this.element.querySelectorAll(`[${this.selectionAttributeValue}="true"]`)]
  }

  #updateLabel() {
    const selected = this.#selectedItems
    if (selected.length === 0) {
      this.labelTarget.textContent = this.noSelectionLabelValue
    } else if (selected.length === 1) {
      this.labelTarget.textContent = `${this.labelPrefixValue} ${selected[0].textContent.trim()}`
    } else {
      this.labelTarget.textContent = `${this.labelPrefixValue} (${selected.length})`
    }
  }

  #updateHiddenFields() {
    // Remove all existing hidden fields
    this.element.querySelectorAll("input[type='hidden'][name]").forEach(i => i.remove())

    // Add one hidden field per selection
    this.#selectedItems.forEach(item => {
      const clone = this.hiddenFieldTemplateTarget.content.cloneNode(true)
      const input = clone.querySelector("input")
      input.value = item.dataset.value
      this.element.appendChild(clone)
    })
  }
}
```

## Keyboard Navigation

A reusable controller for arrow key navigation in lists.

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    selectionAttribute: { type: String, default: "aria-selected" },
    vertical: { type: Boolean, default: true },
    horizontal: { type: Boolean, default: false },
    wrap: { type: Boolean, default: true }
  }

  connect() {
    this.#currentIndex = this.#findSelectedIndex()
  }

  navigate(event) {
    const key = event.key
    let handled = false

    switch (key) {
      case "ArrowDown":
        if (this.verticalValue) {
          this.#moveSelection(1)
          handled = true
        }
        break
      case "ArrowUp":
        if (this.verticalValue) {
          this.#moveSelection(-1)
          handled = true
        }
        break
      case "ArrowRight":
        if (this.horizontalValue) {
          this.#moveSelection(1)
          handled = true
        }
        break
      case "ArrowLeft":
        if (this.horizontalValue) {
          this.#moveSelection(-1)
          handled = true
        }
        break
      case "Enter":
      case " ":
        this.#activateCurrentItem()
        handled = true
        break
      case "Home":
        this.#selectIndex(0)
        handled = true
        break
      case "End":
        this.#selectIndex(this.#items.length - 1)
        handled = true
        break
    }

    if (handled) {
      event.preventDefault()
      event.stopPropagation()
    }
  }

  get #items() {
    return [...this.element.querySelectorAll("[role='option'], [role='menuitem']")]
  }

  #moveSelection(delta) {
    let newIndex = this.#currentIndex + delta

    if (this.wrapValue) {
      // Wrap around
      if (newIndex < 0) newIndex = this.#items.length - 1
      if (newIndex >= this.#items.length) newIndex = 0
    } else {
      // Clamp
      newIndex = Math.max(0, Math.min(newIndex, this.#items.length - 1))
    }

    this.#selectIndex(newIndex)
  }

  #selectIndex(index) {
    // Deselect current
    if (this.#currentIndex >= 0) {
      this.#items[this.#currentIndex]?.setAttribute(this.selectionAttributeValue, "false")
    }

    // Select new
    this.#currentIndex = index
    const item = this.#items[index]
    if (item) {
      item.setAttribute(this.selectionAttributeValue, "true")
      item.scrollIntoView({ block: "nearest" })
      item.focus()
    }
  }

  #activateCurrentItem() {
    const item = this.#items[this.#currentIndex]
    item?.click()
  }

  #findSelectedIndex() {
    return this.#items.findIndex(
      item => item.getAttribute(this.selectionAttributeValue) === "true"
    )
  }
}
```

## Filter/Search Controller

For filtering visible items in a list:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item", "empty"]

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()
    let visibleCount = 0

    this.itemTargets.forEach(item => {
      const text = item.textContent.toLowerCase()
      const matches = query === "" || text.includes(query)

      item.hidden = !matches
      if (matches) visibleCount++
    })

    // Show/hide empty state
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visibleCount > 0
    }
  }

  clear() {
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
  }
}
```

## Form Controller Patterns

### Core Form Controller

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit", "cancel"]
  static values = {
    debounce: { type: Number, default: 300 }
  }

  #debounceTimer = null
  #isComposing = false  // For IME input

  // Track IME composition (for CJK input)
  compositionStart() { this.#isComposing = true }
  compositionEnd() { this.#isComposing = false }

  // Prevent empty submissions with custom validation message
  preventEmptySubmit(event) {
    if (!this.hasInputTarget) return

    const value = this.inputTarget.value.trim()
    if (value.length === 0) {
      event.preventDefault()

      const message = this.inputTarget.dataset.validationMessage
        || "Please fill out this field"

      this.inputTarget.setCustomValidity(message)
      this.inputTarget.reportValidity()

      // Clear validation on next input
      this.inputTarget.addEventListener("input", () => {
        this.inputTarget.setCustomValidity("")
      }, { once: true })
    }
  }

  // Debounced form submission (for auto-save)
  debouncedSubmit() {
    if (this.#isComposing) return  // Don't submit during IME

    clearTimeout(this.#debounceTimer)
    this.#debounceTimer = setTimeout(() => {
      this.element.requestSubmit()
    }, this.debounceValue)
  }

  // Enable/disable submit based on validity
  validateForSubmit() {
    if (!this.hasSubmitTarget) return

    requestAnimationFrame(() => {
      const isValid = this.element.checkValidity()
      this.submitTarget.disabled = !isValid
    })
  }

  // Cancel action (triggered by Escape key)
  cancel() {
    this.cancelTarget?.click()
  }

  // Select all text on focus
  selectAll(event) {
    event.target.select()
  }
}
```

### Usage in Views

```erb
<%= form_with model: @board, class: "form-stack",
      data: {
        controller: "form",
        action: "submit->form#preventEmptySubmit"
      } do |form| %>

  <%= form.text_field :name,
        required: true,
        class: "input",
        autofocus: true,
        data: {
          form_target: "input",
          action: "keydown.esc@document->form#cancel input->form#validateForSubmit",
          validation_message: "Board name is required"
        } %>

  <div class="form-actions">
    <%= form.submit "Create Board", class: "btn btn--primary",
          data: { form_target: "submit" } %>

    <%= link_to "Cancel", boards_path,
          data: { form_target: "cancel" },
          hidden: true %>
  </div>
<% end %>
```

## Auto-Save Pattern

For forms that save automatically:

```javascript
import { Controller } from "@hotwired/stimulus"

const AUTOSAVE_INTERVAL = 3000

export default class extends Controller {
  static targets = ["status"]

  #dirty = false
  #timer = null

  connect() {
    // Save when leaving page
    window.addEventListener("beforeunload", this.#saveSync)
  }

  disconnect() {
    // Save on disconnect (navigation, tab close)
    this.save()
    window.removeEventListener("beforeunload", this.#saveSync)
  }

  // Mark form as dirty and schedule save
  change(event) {
    if (event.target.form !== this.element) return

    if (!this.#dirty) {
      this.#dirty = true
      this.#scheduleAutoSave()
    }
  }

  // Save immediately
  async save() {
    if (!this.#dirty) return

    this.#cancelScheduledSave()
    this.#showSaving()

    try {
      await this.#submitForm()
      this.#dirty = false
      this.#showSaved()
    } catch (error) {
      this.#showError()
    }
  }

  #scheduleAutoSave() {
    this.#timer = setTimeout(() => this.save(), AUTOSAVE_INTERVAL)
  }

  #cancelScheduledSave() {
    clearTimeout(this.#timer)
    this.#timer = null
  }

  async #submitForm() {
    const response = await fetch(this.element.action, {
      method: this.element.method,
      body: new FormData(this.element),
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    })

    if (!response.ok) throw new Error("Save failed")
  }

  #showSaving() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Saving..."
    }
  }

  #showSaved() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Saved"
      setTimeout(() => {
        this.statusTarget.textContent = ""
      }, 2000)
    }
  }

  #showError() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Save failed"
    }
  }

  #saveSync = () => {
    if (this.#dirty) {
      // Use sendBeacon for sync save on page unload
      navigator.sendBeacon(this.element.action, new FormData(this.element))
    }
  }
}
```

## Button States

### Loading State on Submit

```css
.btn {
  position: relative;
  transition: opacity 150ms ease;

  &[disabled] {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

/* When form is submitting */
form[aria-busy="true"] .btn[type="submit"] {
  /* Hide button content */
  > * {
    visibility: hidden;
  }

  /* Show loading dots */
  &::after {
    content: "";
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;

    /* Animated dots using mask */
    background-color: currentColor;
    mask-image: url("data:image/svg+xml,..."); /* Three dots SVG */
    mask-size: 1.5em;
    mask-repeat: no-repeat;
    mask-position: center;
    animation: loading-dots 1s infinite;
  }
}

@keyframes loading-dots {
  0%, 100% { mask-position: center left; }
  50% { mask-position: center right; }
}
```

### Success Animation

```css
.btn--success {
  animation: success-pulse 600ms ease;
}

@keyframes success-pulse {
  0% { transform: scale(1); }
  50% { transform: scale(1.05); }
  100% { transform: scale(1); }
}

.btn--success .icon {
  animation: success-icon 400ms ease;
}

@keyframes success-icon {
  0% { transform: scale(0); opacity: 0; }
  50% { transform: scale(1.2); }
  100% { transform: scale(1); opacity: 1; }
}
```

## Local Storage Persistence

For rich text or complex forms, persist drafts to localStorage:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { key: String }

  connect() {
    this.#restore()
  }

  save() {
    const value = this.inputTarget.value
    if (value && value.trim()) {
      localStorage.setItem(this.keyValue, value)
    } else {
      this.clear()
    }
  }

  clear() {
    localStorage.removeItem(this.keyValue)
  }

  #restore() {
    const saved = localStorage.getItem(this.keyValue)
    if (saved && !this.inputTarget.value) {
      this.inputTarget.value = saved
      this.#dispatchChange()
    }
  }

  #dispatchChange() {
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
```

## Accessibility Checklist

### Labels

Every input needs an associated label:

```erb
<%# Explicit label %>
<%= form.label :name %>
<%= form.text_field :name, class: "input" %>

<%# Implicit label (wrapping) %>
<label class="field">
  <span class="field__label">Name</span>
  <%= form.text_field :name, class: "input" %>
</label>

<%# Screen reader only label %>
<%= form.text_field :search, class: "input",
      "aria-label": "Search cards" %>
```

### ARIA for Custom Components

```html
<!-- Combobox -->
<div role="combobox" aria-expanded="false" aria-haspopup="listbox">
  <input aria-autocomplete="list" aria-controls="options-list">
</div>
<ul id="options-list" role="listbox">
  <li role="option" aria-selected="false">Option 1</li>
</ul>

<!-- Switch -->
<button role="switch" aria-checked="false">
  Dark mode
</button>

<!-- Multi-select -->
<ul role="listbox" aria-multiselectable="true">
  <li role="option" aria-selected="true">Selected</li>
  <li role="option" aria-selected="false">Not selected</li>
</ul>
```

### Focus Management

```javascript
// After opening a dialog, focus the first input
dialog.addEventListener("open", () => {
  const firstInput = dialog.querySelector("input, button, [tabindex='0']")
  firstInput?.focus()
})

// Return focus after closing
let previouslyFocused
function openDialog() {
  previouslyFocused = document.activeElement
  dialog.showModal()
}

dialog.addEventListener("close", () => {
  previouslyFocused?.focus()
})
```

### Validation Announcements

```javascript
// Announce validation errors to screen readers
function announceError(message) {
  const announcer = document.getElementById("aria-announcer")
  announcer.textContent = message

  // Clear after announcement
  setTimeout(() => {
    announcer.textContent = ""
  }, 1000)
}
```

```html
<div id="aria-announcer" role="alert" aria-live="polite" class="sr-only"></div>
```

## Form Helper Patterns

### Auto-Submit Form Helper

```ruby
module FormsHelper
  def auto_submit_form_with(**options, &block)
    options[:data] ||= {}
    options[:data][:controller] = token_list(
      options[:data][:controller],
      "auto-submit"
    )
    form_with(**options, &block)
  end

  def debounced_form_with(debounce: 300, **options, &block)
    options[:data] ||= {}
    options[:data][:controller] = token_list(
      options[:data][:controller],
      "form"
    )
    options[:data][:form_debounce_value] = debounce
    form_with(**options, &block)
  end
end
```

### Input Wrapper Helper

```ruby
module FormsHelper
  def field_wrapper(form, field, label: nil, hint: nil, &block)
    tag.div(class: "field") do
      concat form.label(field, label, class: "field__label") if label
      concat capture(&block)
      concat tag.p(hint, class: "field__hint") if hint
    end
  end
end
```

Usage:

```erb
<%= field_wrapper form, :email, label: "Email address", hint: "We'll never share your email" do %>
  <%= form.email_field :email, class: "input" %>
<% end %>
```

## Summary

**Key patterns for professional form components:**

1. **CSS Custom Properties** - Define `--input-*` variables for complete customization
2. **iOS Zoom Prevention** - Use `font-size: max(16px, 1em)` on inputs
3. **Auto-Growing Textareas** - CSS grid trick with `::after` pseudo-element
4. **Pure CSS Switches** - Hidden checkbox + styled label, no JavaScript needed
5. **Stimulus for Enhancement** - Form validation, auto-save, keyboard navigation
6. **ARIA for Custom Controls** - Proper roles and states for screen readers
7. **Keyboard Navigation** - Arrow keys, Enter, Home/End for lists
8. **Debounced Submission** - Prevent rapid-fire saves on every keystroke
9. **IME Awareness** - Track composition state for CJK input
10. **Local Storage Drafts** - Persist work-in-progress to prevent data loss

These patterns create forms that are accessible, mobile-friendly, and provide a polished user experience while remaining maintainable and DRY.
