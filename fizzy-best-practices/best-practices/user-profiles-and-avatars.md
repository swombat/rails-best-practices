# User Profiles and Avatars

This document describes patterns for handling user profiles, avatars, and preferences in Rails applications. These patterns leverage modern Rails features like Active Storage variants, CSS custom properties for theming, and client-side preference detection.

## Avatar Handling with Active Storage

### The Attachment Pattern

Avatars belong to the per-account User model (not the global Identity), allowing different avatars per workspace:

```ruby
class User < ApplicationRecord
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_fill: [256, 256], process: :immediately
  end
end
```

**Key decisions:**

1. **Single variant** - One thumbnail size (256x256) serves all use cases. CSS handles display sizing. This minimizes storage and processing.

2. **Immediate processing** - `process: :immediately` generates the variant on upload rather than first access. Users see their new avatar instantly.

3. **resize_to_fill** - Maintains aspect ratio while cropping to a square. Better than `resize_to_fit` which would leave whitespace.

### Validation

Protect against malicious uploads:

```ruby
ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp]
MAX_DIMENSIONS = 4096

validate :validate_avatar_content_type
validate :validate_avatar_dimensions

private
  def validate_avatar_content_type
    return unless avatar.attached?
    unless ALLOWED_CONTENT_TYPES.include?(avatar.content_type)
      errors.add(:avatar, "must be a JPEG, PNG, GIF, or WebP image")
    end
  end

  def validate_avatar_dimensions
    return unless avatar.attached?
    metadata = avatar.blob.metadata
    if metadata[:width].to_i > MAX_DIMENSIONS || metadata[:height].to_i > MAX_DIMENSIONS
      errors.add(:avatar, "dimensions must not exceed #{MAX_DIMENSIONS}x#{MAX_DIMENSIONS}")
    end
  end
```

### Accessing the Thumbnail

Create a helper method that handles non-variable images (like SVG):

```ruby
def avatar_thumbnail
  avatar.variable? ? avatar.variant(:thumb) : avatar
end
```

## Dynamic Default Avatars

When no avatar is uploaded, generate an SVG with the user's initials. This is more personal than generic silhouettes and requires no pre-generated images.

### The Initials Avatar Controller

```ruby
class Users::AvatarsController < ApplicationController
  def show
    if @user.system?
      redirect_to image_path("system_user.png")
    elsif @user.avatar.attached?
      redirect_to rails_blob_url(@user.avatar_thumbnail, disposition: "inline")
    elsif stale?(@user, cache_control: cache_control)
      render_initials
    end
  end

  private
    def render_initials
      render formats: [:svg], content_type: "image/svg+xml"
    end

    def cache_control
      if @user == Current.user
        {}  # No caching for own avatar
      else
        { max_age: 30.minutes, stale_while_revalidate: 1.week }
      end
    end
end
```

**Caching strategy:**
- Own avatar: No browser caching (see changes immediately after upload)
- Other users: 30-minute max-age with week-long stale-while-revalidate
- Uses ETag-based `stale?` for efficient revalidation

### The SVG Template

```erb
<!-- users/avatars/show.svg.erb -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <rect width="512" height="512" fill="<%= avatar_background_color(@user) %>" />
  <text x="50%" y="50%" text-anchor="middle" dy="0.35em"
        fill="white" font-family="system-ui" font-size="200" font-weight="600">
    <%= @user.initials %>
  </text>
</svg>
```

### Extracting Initials

```ruby
module User::Named
  def initials
    name.scan(/\b\p{L}/).join.upcase
  end
end
```

The regex `\b\p{L}` matches Unicode letter characters at word boundaries, supporting international names.

### Deterministic Color Assignment

Assign consistent colors based on user ID:

```ruby
module AvatarsHelper
  AVATAR_COLORS = %w[
    #AF2E1B #CC6324 #3B4B59 #BFA07A #ED8008 #ED3F1C #BF1B1B #736B1E
    #D07B53 #736356 #AD1D1D #BF7C2A #C09C6F #698F9C #7C956B #5D618F
  ]

  def avatar_background_color(user)
    AVATAR_COLORS[Zlib.crc32(user.to_param) % AVATAR_COLORS.size]
  end
end
```

CRC32 provides fast, deterministic hashing. The same user always gets the same color.

## Upload Preview

Show the new avatar instantly before form submission:

```javascript
// upload_preview_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "image"]

  previewImage() {
    const file = this.inputTarget.files[0]
    if (file) {
      this.imageTarget.src = URL.createObjectURL(file)
      this.imageTarget.onload = () => URL.revokeObjectURL(this.imageTarget.src)
    }
  }
}
```

```erb
<div data-controller="upload-preview">
  <%= image_tag avatar_url(@user), data: { upload_preview_target: "image" } %>
  <%= file_field :avatar, data: {
    upload_preview_target: "input",
    action: "change->upload-preview#previewImage"
  } %>
</div>
```

Memory cleanup with `revokeObjectURL` prevents leaks when users select multiple files.

## Timezone Handling

### Client-Side Detection

Detect the user's timezone via JavaScript and store in a cookie:

```javascript
// timezone_cookie_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.#setTimezoneCookie()
  }

  #setTimezoneCookie() {
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    document.cookie = `timezone=${encodeURIComponent(timezone)}; path=/`
  }
}
```

Attach to a persistent element (like the body):

```erb
<body data-controller="timezone-cookie">
```

### Server-Side Application

Use a controller concern to apply the timezone:

```ruby
module CurrentTimezone
  extend ActiveSupport::Concern

  included do
    around_action :set_current_timezone
  end

  private
    def set_current_timezone(&block)
      Time.use_zone(timezone_from_cookie, &block)
    end

    def timezone_from_cookie
      @timezone_from_cookie ||= begin
        tz = cookies[:timezone]
        ActiveSupport::TimeZone[tz] if tz.present?
      end
    end
end
```

### User-Configurable Override

Allow users to override auto-detected timezone:

```ruby
class User::Settings < ApplicationRecord
  belongs_to :user

  def timezone
    if timezone_name.present?
      ActiveSupport::TimeZone[timezone_name] || default_timezone
    else
      default_timezone
    end
  end

  def default_timezone
    ActiveSupport::TimeZone["UTC"]
  end
end
```

Provide a helper for scoped time operations:

```ruby
module User::Configurable
  def in_time_zone(&block)
    Time.use_zone(settings.timezone, &block)
  end
end
```

## Light/Dark Mode

### The Three-Option Approach

Offer three choices: Light, Dark, and System (follows OS preference).

### Client-Side Implementation

Store preference in localStorage (not server-side) for instant application:

```javascript
// theme_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  setLight() { this.#theme = "light" }
  setDark() { this.#theme = "dark" }
  setAuto() { this.#theme = "auto" }

  set #theme(theme) {
    localStorage.setItem("theme", theme)
    if (theme === "auto") {
      document.documentElement.removeAttribute("data-theme")
    } else {
      document.documentElement.setAttribute("data-theme", theme)
    }
  }
}
```

### Preventing Flash of Wrong Theme

Apply theme before page renders with an inline script in `<head>`:

```erb
<%= javascript_tag nonce: true do %>
  const theme = localStorage.getItem("theme")
  if (theme && theme !== "auto") {
    document.documentElement.dataset.theme = theme
  }
<% end %>
```

This runs synchronously before CSS loads, preventing flash.

### CSS Implementation

Define colors using CSS custom properties with two override strategies:

```css
/* Base (light) theme */
:root {
  --color-canvas: oklch(98% 0.01 250);
  --color-ink: oklch(20% 0.02 250);
  --color-accent: oklch(55% 0.15 250);
}

/* Explicit dark theme */
html[data-theme="dark"] {
  --color-canvas: oklch(15% 0.02 250);
  --color-ink: oklch(90% 0.01 250);
  --color-accent: oklch(70% 0.12 250);
}

/* System preference (when no explicit choice) */
@media (prefers-color-scheme: dark) {
  html:not([data-theme]) {
    --color-canvas: oklch(15% 0.02 250);
    --color-ink: oklch(90% 0.01 250);
    --color-accent: oklch(70% 0.12 250);
  }
}
```

The selector `html:not([data-theme])` ensures system preference only applies when user hasn't made an explicit choice.

## Profile Structure: Identity vs User

### The Separation

**Identity** (global, email-based):
- Email address
- Staff flag
- Sessions and authentication tokens
- Can belong to multiple accounts

**User** (per-account membership):
- Name
- Role (owner/admin/member)
- Avatar
- Settings (timezone, notification preferences)
- Account-specific permissions

### Why This Matters for Profiles

A person might have different names and avatars in different workspaces:
- "Dan" with casual avatar in personal projects
- "Daniel Tenner" with professional photo at work

The User model per account enables this naturally.

### Profile Editing Permissions

```ruby
module User::Role
  def can_change?(other)
    (admin? && !other.owner?) || other == self
  end
end
```

Rules:
- Users can always edit their own profile
- Admins can edit non-owner users
- Owners cannot be modified by anyone else

### Email Changes Cross Boundaries

Email belongs to Identity (global), so changing it requires special handling:

1. User requests email change
2. System sends verification to new address
3. Verification creates/finds Identity with new email
4. User record's identity association is updated

This is handled by a dedicated controller that operates outside the normal account scope.

## Notification Preferences

### Email Frequency Settings

```ruby
class User::Settings < ApplicationRecord
  enum :bundle_email_frequency,
    %i[never every_few_hours daily weekly],
    default: :every_few_hours,
    prefix: :bundle_email
end
```

### Controller Pattern

```ruby
class Notifications::SettingsController < ApplicationController
  def update
    Current.user.settings.update!(settings_params)
    redirect_to notifications_settings_path
  end

  private
    def settings_params
      params.require(:user_settings).permit(:bundle_email_frequency)
    end
end
```

## Summary

**Avatar handling:**
- Single Active Storage variant with immediate processing
- Dynamic SVG initials for defaults with deterministic colors
- Smart caching (none for self, aggressive for others)
- Client-side preview before upload

**Preferences:**
- Timezone: Client detection via cookie, user override via settings
- Theme: localStorage for instant application, CSS custom properties for implementation
- Notifications: Per-user frequency settings

**Profile architecture:**
- Separate Identity (authentication) from User (authorization)
- Per-account profiles allow different names/avatars per workspace
- Permission system protects owner from modification
