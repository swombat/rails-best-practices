# Advanced Rails Patterns

This document covers sophisticated architectural patterns for building production-grade Rails applications. These patterns address common challenges in multi-tenant SaaS applications: background job context, storage tracking, search at scale, webhooks, notifications, and more.

## Multi-Tenant Background Jobs

### The Problem

When a background job runs, it loses the request context. In multi-tenant applications, jobs need to know which account they're operating on. Passing `account_id` explicitly to every job is tedious and error-prone.

### The Solution: Automatic Context Serialization

Prepend a module to ActiveJob that captures and restores the current account:

```ruby
# config/initializers/active_job.rb
module FizzyActiveJobExtensions
  extend ActiveSupport::Concern

  prepended do
    attr_reader :account

    # Wait for transaction commit before enqueueing (Rails 7.2+)
    self.enqueue_after_transaction_commit = true
  end

  # Capture current account when job is instantiated
  def initialize(...)
    super
    @account = Current.account
  end

  # Serialize account into job payload
  def serialize
    super.merge({ "account" => @account&.to_gid })
  end

  # Deserialize account when job is loaded
  def deserialize(job_data)
    super
    if _account = job_data.fetch("account", nil)
      @account = GlobalID::Locator.locate(_account)
    end
  end

  # Wrap execution in account context
  def perform_now
    if account.present?
      Current.with_account(account) { super }
    else
      super
    end
  end
end

ActiveSupport.on_load(:active_job) do
  prepend FizzyActiveJobExtensions
end
```

**Benefits:**
- Jobs automatically have correct account context
- No explicit `account_id` parameter needed
- Works with any job, including third-party gems
- GlobalID handles serialization safely

### Concurrency Control with Solid Queue

For jobs that shouldn't run concurrently on the same resource:

```ruby
class Storage::ReconcileJob < ApplicationJob
  queue_as :backend

  # Only one reconcile job per owner at a time
  limits_concurrency to: 1, key: ->(owner) { owner }

  # Skip if record was deleted
  discard_on ActiveJob::DeserializationError

  # Retry transient failures
  retry_on ReconcileAborted, wait: 1.minute, attempts: 3

  def perform(owner)
    owner.reconcile_storage
  end
end
```

### Declarative Recurring Jobs

Define recurring jobs in YAML with ERB for conditional scheduling:

```yaml
# config/recurring.yml
production: &production
  # Run every 30 minutes
  deliver_bundled_notifications:
    command: "Notification::Bundle.deliver_all_later"
    schedule: every 30 minutes

  # Run at specific minute of each hour
  auto_postpone_all_due:
    command: "Card.auto_postpone_all_due"
    schedule: every hour at minute 50

  # Conditional based on deployment mode
  <% if Rails.application.config.saas_mode %>
  collect_metrics:
    command: "Metrics.collect"
    schedule: every 60 seconds
  <% end %>

development:
  <<: *production
```

### SMTP Error Handling

Create a concern for comprehensive email delivery error handling:

```ruby
# app/jobs/concerns/smtp_delivery_error_handling.rb
module SmtpDeliveryErrorHandling
  extend ActiveSupport::Concern

  included do
    # Retry network timeouts with exponential backoff
    retry_on Net::OpenTimeout,
             Net::ReadTimeout,
             Socket::ResolutionError,
             wait: :polynomially_longer

    # Retry server busy errors
    retry_on Net::SMTPServerBusy,
             wait: :polynomially_longer

    # Handle syntax errors (often invalid addresses)
    rescue_from Net::SMTPSyntaxError do |error|
      case error.message
      when /\A501 5\.1\.3/  # Bad recipient address
        Sentry.capture_exception error, level: :info if Fizzy.saas?
      else
        raise  # Re-raise other syntax errors
      end
    end

    rescue_from Net::SMTPFatalError do |error|
      case error.message
      when /\A550 5\.1\.1/, /\A552 5\.6\.0/, /\A555 5\.5\.4/
        Sentry.capture_exception error, level: :info if Fizzy.saas?
      else
        raise
      end
    end
  end
end
```

## Storage Ledger System

### The Problem

Tracking file storage usage accurately is tricky:
- Files are uploaded and deleted constantly
- Need real-time-ish totals for quota enforcement
- Can't query blob sizes on every request (too slow)
- Must handle concurrent operations safely

### The Solution: Event-Sourced Ledger

Create a ledger of storage changes (like double-entry bookkeeping):

```ruby
# app/models/storage/entry.rb
class Storage::Entry < ApplicationRecord
  belongs_to :account
  belongs_to :board, optional: true
  belongs_to :recordable, polymorphic: true, optional: true
  belongs_to :blob, optional: true

  # operation: "upload", "delete", "transfer"
  # delta: positive for additions, negative for deletions

  def self.record(delta:, operation:, account:, board: nil, recordable: nil, blob: nil)
    return if delta.zero?
    return if account.destroyed?

    entry = create!(
      account_id: account.id,
      board_id: board&.id,
      recordable_type: recordable&.class&.name,
      recordable_id: recordable&.id,
      blob_id: blob&.id,
      delta: delta,
      operation: operation,
      user_id: Current.user&.id,
      request_id: Current.request_id
    )

    account.materialize_storage_later
    board&.materialize_storage_later unless board&.destroyed?
    entry
  end
end
```

### Materialized Totals with Cursor Tracking

Instead of summing all entries on every read, maintain materialized snapshots:

```ruby
# app/models/concerns/storage/totaled.rb
module Storage::Totaled
  extend ActiveSupport::Concern

  included do
    has_many :storage_entries, as: :owner
    has_one :storage_total, as: :owner
  end

  def materialize_storage
    total = storage_total || create_storage_total!(bytes_stored: 0)

    total.with_lock do
      latest_entry_id = storage_entries.maximum(:id)

      # Only process new entries since last materialization
      if latest_entry_id && total.last_entry_id != latest_entry_id
        scope = storage_entries.where(id: ..latest_entry_id)
        scope = scope.where(id: (total.last_entry_id + 1)..) if total.last_entry_id

        delta_sum = scope.sum(:delta)

        total.update!(
          bytes_stored: total.bytes_stored + delta_sum,
          last_entry_id: latest_entry_id
        )
      end
    end
  end

  def materialize_storage_later
    Storage::MaterializeJob.perform_later(self)
  end
end
```

### Reconciliation with Concurrent Write Detection

Periodically verify materialized totals match reality:

```ruby
def reconcile_storage
  # Record cursor before scanning
  cursor_before = storage_entries.maximum(:id)

  # Calculate actual storage from blobs
  actual_bytes = calculate_actual_storage

  # Check if new entries arrived during scan
  cursor_after = storage_entries.maximum(:id)

  if cursor_before != cursor_after
    # Concurrent write detected - abort and retry later
    Rails.logger.warn "[Storage] Reconcile aborted: cursor moved"
    return false
  end

  # Apply correction if needed
  current_bytes = storage_total&.bytes_stored || 0
  difference = actual_bytes - current_bytes

  if difference != 0
    Storage::Entry.record(
      delta: difference,
      operation: "reconciliation",
      account: self
    )
  end

  true
end
```

## Sharded Full-Text Search

### The Problem

Full-text search tables can grow very large in multi-tenant apps. A single table becomes:
- Slow to update (index maintenance)
- Slow to query (large index scans)
- Hard to maintain (migrations take forever)

### The Solution: CRC32-Based Sharding

Distribute search records across multiple tables using account ID:

```ruby
# app/models/search/record.rb
class Search::Record < ApplicationRecord
  SHARD_COUNT = 16

  self.abstract_class = true

  # Generate shard classes dynamically
  SHARDS = SHARD_COUNT.times.map do |shard_id|
    Class.new(self) do
      self.table_name = "search_records_#{shard_id}"

      # Keep class name consistent for Rails internals
      def self.name
        "Search::Record"
      end
    end
  end.freeze

  class << self
    def shard_for(account_id)
      shard_id = Zlib.crc32(account_id.to_s) % SHARD_COUNT
      SHARDS[shard_id]
    end

    def search(account:, query:)
      shard_for(account.id).where(
        "MATCH(content) AGAINST(? IN BOOLEAN MODE)",
        sanitize_query(query)
      )
    end

    private

    def sanitize_query(query)
      # Handle unbalanced quotes
      balanced = query.count('"').even? ? query : query.delete('"')

      # Escape special characters
      balanced.gsub(/[+\-<>()~*@]/, ' ')
    end
  end
end
```

### Migration for Sharded Tables

```ruby
class CreateSearchRecordShards < ActiveRecord::Migration[7.1]
  def change
    16.times do |shard_id|
      create_table "search_records_#{shard_id}" do |t|
        t.references :account, null: false
        t.references :searchable, polymorphic: true, null: false
        t.text :content, null: false
        t.timestamps

        t.index [:account_id, :searchable_type, :searchable_id],
                unique: true,
                name: "idx_search_#{shard_id}_unique"
      end

      # Add full-text index (MySQL)
      execute "ALTER TABLE search_records_#{shard_id} ADD FULLTEXT INDEX idx_search_#{shard_id}_ft (content)"
    end
  end
end
```

### Search Highlighting

Extract relevant snippets with highlighted matches:

```ruby
# app/models/search/highlighter.rb
class Search::Highlighter
  def initialize(terms, tag: "mark")
    @terms = terms
    @tag = tag
  end

  def snippet(text, max_words: 20)
    words = text.split(/\s+/)

    # Find first matching word
    match_index = words.index { |word| matches?(word) }

    if words.length <= max_words
      highlight(text)
    elsif match_index
      # Center snippet on match
      start_idx = [0, match_index - max_words / 2].max
      end_idx = [words.length - 1, start_idx + max_words - 1].min

      snippet_words = words[start_idx..end_idx]
      snippet_text = snippet_words.join(" ")

      # Add ellipses
      snippet_text = "..." + snippet_text if start_idx > 0
      snippet_text = snippet_text + "..." if end_idx < words.length - 1

      highlight(snippet_text)
    else
      # No match in text, return beginning
      words.first(max_words).join(" ") + "..."
    end
  end

  def highlight(text)
    @terms.reduce(text) do |t, term|
      t.gsub(/(#{Regexp.escape(term)})/i, "<#{@tag}>\\1</#{@tag}>")
    end
  end

  private

  def matches?(word)
    @terms.any? { |term| word.downcase.include?(term.downcase) }
  end
end
```

## Webhook System

### SSRF Protection

Prevent Server-Side Request Forgery when delivering webhooks:

```ruby
# app/models/ssrf_protection.rb
module SsrfProtection
  extend ActiveSupport::Concern

  # Use public DNS to prevent DNS rebinding attacks
  DNS_SERVERS = %w[1.1.1.1 8.8.8.8]

  # Additional blocked ranges beyond RFC 1918
  BLOCKED_RANGES = [
    IPAddr.new("0.0.0.0/8"),       # "This" network
    IPAddr.new("100.64.0.0/10"),   # Carrier-grade NAT
    IPAddr.new("169.254.0.0/16"),  # Link-local
    IPAddr.new("192.0.0.0/24"),    # IETF Protocol Assignments
    IPAddr.new("192.0.2.0/24"),    # TEST-NET-1
    IPAddr.new("198.18.0.0/15"),   # Benchmark testing
    IPAddr.new("198.51.100.0/24"), # TEST-NET-2
    IPAddr.new("203.0.113.0/24"),  # TEST-NET-3
  ].freeze

  def resolve_safe_ip(hostname)
    # Resolve using public DNS
    resolver = Resolv::DNS.new(nameserver: DNS_SERVERS)
    addresses = resolver.getaddresses(hostname)

    # Filter to public IPs only
    public_ips = addresses.map { |a| IPAddr.new(a.to_s) }
                          .reject { |ip| unsafe_ip?(ip) }

    # Prefer IPv4
    public_ips.sort_by { |ip| ip.ipv4? ? 0 : 1 }.first
  end

  def unsafe_ip?(ip)
    ip.private? ||
    ip.loopback? ||
    ip.link_local? ||
    BLOCKED_RANGES.any? { |range| range.include?(ip) }
  end
end
```

### Webhook Delinquency Tracking

Automatically disable webhooks that consistently fail:

```ruby
# app/models/webhook/delinquency_tracker.rb
class Webhook::DelinquencyTracker < ApplicationRecord
  belongs_to :webhook

  FAILURE_THRESHOLD = 10
  FAILURE_WINDOW = 1.hour

  def record_delivery(delivery)
    if delivery.succeeded?
      reset!
    else
      increment_failures
      webhook.deactivate! if delinquent?
    end
  end

  def delinquent?
    consecutive_failures >= FAILURE_THRESHOLD &&
    first_failure_at <= FAILURE_WINDOW.ago
  end

  private

  def increment_failures
    self.first_failure_at ||= Time.current
    increment!(:consecutive_failures)
  end

  def reset!
    update!(
      consecutive_failures: 0,
      first_failure_at: nil
    )
  end
end
```

### Multi-Format Webhook Payloads

Support different payload formats for different services:

```ruby
# app/models/webhook/delivery.rb
class Webhook::Delivery
  def payload
    case webhook.format
    when "json"
      render_json_payload
    when "slack"
      render_slack_payload
    when "html"
      render_html_payload
    end
  end

  private

  def render_slack_payload
    html = render_html_payload
    mrkdwn = html_to_mrkdwn(html)
    { text: mrkdwn }.to_json
  end

  def html_to_mrkdwn(html)
    html
      .gsub(/<strong>(.*?)<\/strong>/m, '*\1*')
      .gsub(/<em>(.*?)<\/em>/m, '_\1_')
      .gsub(/<a href="(.*?)">(.*?)<\/a>/m, '<\1|\2>')
      .gsub(/<[^>]+>/, '')  # Strip remaining tags
  end
end
```

## Notification Bundling

### The Problem

Sending an email for every notification is noisy. Users prefer digests. But implementing time-windowed aggregation is complex.

### The Solution: Notification Bundles

Create bundle records that collect notifications within a time window:

```ruby
# app/models/notification/bundle.rb
class Notification::Bundle < ApplicationRecord
  belongs_to :user

  scope :pending, -> { where(status: :pending) }
  scope :due, -> { pending.where("ends_at <= ?", Time.current) }

  enum :status, { pending: 0, delivered: 1, cancelled: 2 }

  def notifications
    user.notifications
        .where(created_at: starts_at..ends_at)
        .unread
  end

  def set_default_window
    self.starts_at ||= Time.current
    self.ends_at ||= starts_at + user.notification_bundle_period
  end

  def deliver
    return if notifications.empty?

    NotificationMailer.bundle(self).deliver_later
    delivered!
  end

  class << self
    def for_notification(notification)
      user = notification.user
      existing = user.notification_bundles
                     .pending
                     .where("starts_at <= ? AND ends_at > ?",
                            notification.created_at,
                            notification.created_at)
                     .first

      existing || user.notification_bundles.create!
    end

    def deliver_all_due
      due.find_each(&:deliver)
    end
  end
end
```

### One-Click Unsubscribe

Implement RFC 8058 compliant one-click unsubscribe:

```ruby
# app/mailers/concerns/mailers/unsubscribable.rb
module Unsubscribable
  extend ActiveSupport::Concern

  included do
    after_action :set_unsubscribe_headers, if: :unsubscribable?
  end

  private

  def set_unsubscribe_headers
    # RFC 8058: List-Unsubscribe-Post header enables one-click
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    # URL that handles the unsubscribe
    headers["List-Unsubscribe"] = "<#{unsubscribe_url}>"
  end

  def unsubscribe_url
    # Generate signed URL that doesn't require login
    notifications_unsubscribe_url(
      token: @user.generate_token_for(:unsubscribe)
    )
  end

  def unsubscribable?
    @user.present?
  end
end
```

## URL-Friendly UUIDs

### Base36-Encoded UUIDv7

UUIDv7 is time-sortable (great for database performance) but long. Encode in base36 for shorter URLs:

```ruby
# lib/rails_ext/active_record_uuid_type.rb
module UuidType
  BASE36_LENGTH = 25  # 36^25 > 2^128

  def self.generate
    # UUIDv7: timestamp-based, sortable
    uuid = SecureRandom.uuid_v7
    hex = uuid.delete("-")
    hex_to_base36(hex)
  end

  def self.hex_to_base36(hex)
    hex.to_i(16).to_s(36).rjust(BASE36_LENGTH, "0")
  end

  def self.base36_to_hex(base36)
    base36.to_i(36).to_s(16).rjust(32, "0")
  end

  def self.to_uuid_format(base36)
    hex = base36_to_hex(base36)
    "#{hex[0..7]}-#{hex[8..11]}-#{hex[12..15]}-#{hex[16..19]}-#{hex[20..31]}"
  end
end
```

**Comparison:**
- Standard UUID: `01234567-89ab-cdef-0123-456789abcdef` (36 chars)
- Base36 encoded: `0k3t5qvmzgz0hqn8c9y7xw2a1` (25 chars)

### Automatic UUID Defaults

Configure Rails to use UUIDs as primary keys:

```ruby
# config/initializers/uuid_primary_keys.rb
Rails.application.config.generators do |g|
  g.orm :active_record, primary_key_type: :uuid
end

# Automatically set default for UUID primary keys
module UuidPrimaryKeyDefault
  extend ActiveSupport::Concern

  class_methods do
    def load_schema!
      super
      if uuid_primary_key?
        attribute primary_key, :uuid, default: -> { UuidType.generate }
      end
    end

    private

    def uuid_primary_key?
      primary_key &&
      columns_hash[primary_key]&.type == :uuid
    end
  end
end

ActiveSupport.on_load(:active_record) do
  extend UuidPrimaryKeyDefault
end
```

## Timezone Handling

### Cookie-Based Detection

Detect user timezone on the client and send to server:

```javascript
// app/javascript/controllers/timezone_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.#setTimezoneCookie()
  }

  #setTimezoneCookie() {
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    document.cookie = `timezone=${encodeURIComponent(timezone)}; path=/; max-age=31536000`
  }
}
```

### Server-Side Timezone Application

```ruby
# app/controllers/concerns/current_timezone.rb
module CurrentTimezone
  extend ActiveSupport::Concern

  included do
    around_action :set_current_timezone
    helper_method :timezone_from_cookie
    etag { timezone_from_cookie }
  end

  private

  def set_current_timezone(&block)
    Time.use_zone(timezone_from_cookie, &block)
  end

  def timezone_from_cookie
    @timezone_from_cookie ||= begin
      timezone = cookies[:timezone]
      ActiveSupport::TimeZone[timezone] if timezone.present?
    end
  end
end
```

### User-Specific Timezone

For logged-in users, prefer their saved timezone:

```ruby
# app/models/user/configurable.rb
module User::Configurable
  extend ActiveSupport::Concern

  included do
    delegate :timezone, to: :settings, allow_nil: true
  end

  def in_time_zone(&block)
    Time.use_zone(timezone, &block)
  end
end
```

## Database Portability

### Database-Agnostic Date Arithmetic

Support both MySQL and SQLite with adapter-specific SQL:

```ruby
# lib/rails_ext/active_record_date_arithmetic.rb
module DateArithmetic
  def self.included(base)
    adapter = ActiveRecord::Base.connection.adapter_name.downcase

    case adapter
    when /mysql/
      base.extend(MysqlArithmetic)
    when /sqlite/
      base.extend(SqliteArithmetic)
    when /postgres/
      base.extend(PostgresArithmetic)
    end
  end

  module MysqlArithmetic
    def date_add(column, seconds)
      "DATE_ADD(#{column}, INTERVAL #{seconds} SECOND)"
    end

    def date_subtract(column, seconds)
      "DATE_SUB(#{column}, INTERVAL #{seconds} SECOND)"
    end
  end

  module SqliteArithmetic
    def date_add(column, seconds)
      "datetime(#{column}, '+' || (#{seconds}) || ' seconds')"
    end

    def date_subtract(column, seconds)
      "datetime(#{column}, '-' || (#{seconds}) || ' seconds')"
    end
  end

  module PostgresArithmetic
    def date_add(column, seconds)
      "(#{column} + (#{seconds} || ' seconds')::interval)"
    end

    def date_subtract(column, seconds)
      "(#{column} - (#{seconds} || ' seconds')::interval)"
    end
  end
end
```

## Data Export

### Async ZIP Export with Streaming

For large exports, generate ZIPs asynchronously and stream attachments:

```ruby
# app/models/export.rb
class Export < ApplicationRecord
  has_one_attached :file

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  def build
    processing!

    Tempfile.create(["export", ".zip"]) do |tempfile|
      generate_zip(tempfile.path)

      file.attach(
        io: File.open(tempfile.path),
        filename: "export-#{id}.zip",
        content_type: "application/zip"
      )
    end

    completed!
    ExportMailer.ready(self).deliver_later
  rescue => error
    failed!
    raise
  end

  private

  def generate_zip(path)
    Zip::File.open(path, Zip::File::CREATE) do |zip|
      add_data_files(zip)
      add_attachments(zip)
    end
  end

  def add_attachments(zip)
    attachments_to_export.each do |attachment|
      # Stream directly to ZIP to avoid memory issues
      zip.get_output_stream(attachment[:path]) do |out|
        attachment[:blob].download do |chunk|
          out.write(chunk)
        end
      end
    rescue ActiveStorage::FileNotFoundError
      # Skip missing files
      Rails.logger.warn "Missing attachment: #{attachment[:path]}"
    end
  end
end
```

## Activity Detection (Entropy Prevention)

### The Problem

Auto-archiving stale cards is useful, but you don't want to archive cards with active discussion. How do you detect "activity spikes"?

### Activity Spike Detection

```ruby
# app/models/card/activity_detector.rb
class Card::ActivityDetector
  RECENT_PERIOD = 7.days
  MIN_COMMENTS = 3
  MIN_PARTICIPANTS = 2

  def initialize(card)
    @card = card
  end

  def has_activity_spike?
    return false unless @card.auto_archivable?

    multiple_recent_commenters? ||
    recently_assigned? ||
    recently_reopened?
  end

  private

  def multiple_recent_commenters?
    @card.comments
         .where(created_at: RECENT_PERIOD.ago..)
         .group(:card_id)
         .having("COUNT(*) >= ?", MIN_COMMENTS)
         .having("COUNT(DISTINCT creator_id) >= ?", MIN_PARTICIPANTS)
         .exists?
  end

  def recently_assigned?
    @card.events
         .where(action: "assigned")
         .where(created_at: RECENT_PERIOD.ago..)
         .exists?
  end

  def recently_reopened?
    @card.events
         .where(action: "reopened")
         .where(created_at: RECENT_PERIOD.ago..)
         .exists?
  end
end
```

## Configuration Patterns

### SaaS vs Self-Hosted Mode

Support different deployment modes:

```ruby
# lib/app_mode.rb
module AppMode
  def self.saas?
    return @saas if defined?(@saas)
    @saas = ENV["SAAS"] == "true" || File.exist?(Rails.root.join("tmp/saas.txt"))
  end

  def self.self_hosted?
    !saas?
  end

  def self.database_adapter
    @adapter ||= if saas?
      ENV.fetch("DATABASE_ADAPTER", "mysql")
    else
      ENV.fetch("DATABASE_ADAPTER", "sqlite")
    end
  end
end
```

### Per-User Settings

Store user preferences in a separate model:

```ruby
# app/models/user/settings.rb
class User::Settings < ApplicationRecord
  belongs_to :user

  enum :notification_frequency, {
    immediate: 0,
    hourly: 1,
    daily: 2,
    weekly: 3,
    never: 4
  }, default: :hourly

  enum :theme, { system: 0, light: 1, dark: 2 }, default: :system

  def notification_bundle_period
    case notification_frequency
    when "immediate" then 0
    when "hourly" then 1.hour
    when "daily" then 1.day
    when "weekly" then 1.week
    else nil
    end
  end
end
```

## Summary

These patterns address common challenges in production Rails applications:

1. **Multi-tenant jobs** - Automatic context serialization via GlobalID
2. **Storage ledger** - Event-sourced tracking with materialized snapshots
3. **Sharded search** - Horizontal scaling via CRC32 distribution
4. **SSRF protection** - Safe webhook delivery with IP validation
5. **Delinquency tracking** - Automatic webhook disabling after failures
6. **Notification bundling** - Time-windowed email digests
7. **Base36 UUIDs** - Shorter, URL-friendly identifiers
8. **Timezone handling** - Cookie detection + user preference
9. **Database portability** - Adapter-specific SQL helpers
10. **Async exports** - Streamed ZIP generation
11. **Activity detection** - Smart auto-archive prevention

Each pattern solves a real problem encountered when scaling Rails applications to production use with multiple tenants, high throughput, and complex business requirements.
