# The Delegated Types Pattern

This document is a general 37signals-style Rails reference. Fizzy does not currently use `delegated_type` in its domain model.

Delegated Types is an advanced Rails pattern for building content-oriented systems with diverse types that share common operational characteristics. It was introduced in Rails 6.1 and is used extensively in other 37signals applications to model everything from messages to documents to to-dos. This pattern addresses fundamental problems that arise when you need to manage many different content types with shared behaviors.

This is not a pattern you reach for on day one of a project. It's a sophisticated architectural choice that makes sense when you have specific constraints: many content types, shared operational patterns, version history requirements, and the need to scale to millions or billions of records.

## The Problem: Content Diversity at Scale

Imagine building Basecamp. You have messages, documents, to-dos, comments, files, images, schedules, and a dozen other content types. Each type has unique attributes:

- Messages have subjects and rich content
- To-dos have completion status and due dates
- Files have storage locations and MIME types
- Comments have parent relationships

But they all share operational patterns:

- All can be created, read, updated, deleted
- All can be commented on (some of them)
- All can be copied between projects (most of them)
- All can be moved to trash and restored
- All can be exported
- All have version history
- All appear in activity timelines
- All participate in caching strategies

The question: how do you model this without creating a maintenance nightmare?

## The Naive Approach: Single Table Inheritance

Your first instinct might be Single Table Inheritance:

```ruby
class Recording < ApplicationRecord
  # STI discriminator
  self.inheritance_column = 'type'
end

class Message < Recording
  # Messages need: subject, content, attachments
end

class Todo < Recording
  # To-dos need: description, completed_at, due_date
end

class Document < Recording
  # Documents need: title, body, version_number
end
```

This works at first. But it scales terribly:

**Problem 1: Schema Bloat**
Every new content type requires adding columns to the recordings table. Message needs `subject`. Todo needs `completed_at`. Document needs `version_number`. Your table ends up with hundreds of mostly-null columns.

**Problem 2: Migration Hell**
Every new feature means migrating the main table. Adding attachments to messages? Migrate the recordings table. Adding recurrence to todos? Migrate the recordings table. On a table with millions or billions of rows, these migrations are painful.

**Problem 3: Disk Inefficiency**
MySQL and PostgreSQL allocate space for every column in every row, even when NULL. A billion-row table with 200 mostly-null columns wastes enormous amounts of disk space.

**Problem 4: Query Complexity**
Querying specific types requires filtering by the type column and checking for non-null type-specific columns. The database can't optimize these queries well.

Single Table Inheritance is fine for small type hierarchies (3-5 types, minimal type-specific attributes). For content systems with dozens of types and type-specific behavior, it's the wrong tool.

## The Delegated Types Solution

Delegated Types splits your architecture into two layers:

1. **The recordings table**: Common metadata only (timestamps, creator, parent-child relationships)
2. **The recordables tables**: Type-specific data (one table per type)

```ruby
# The lean recordings table
class Recording < ApplicationRecord
  belongs_to :account
  belongs_to :creator, class_name: "User"
  belongs_to :parent, class_name: "Recording", optional: true

  # Delegated type magic
  delegated_type :recordable, types: %w[ Message Todo Document Comment File ],
                              dependent: :destroy

  # Delegate method calls to the type-specific recordable
  delegate :title, :commentable?, :copyable?, :movable?, to: :recordable
end

# Type-specific tables
class Message < ApplicationRecord
  include Recordable

  has_one :recording, as: :recordable, touch: true

  has_rich_text :content

  def title
    subject
  end

  def commentable?
    true
  end

  def copyable?
    true
  end
end

class Todo < ApplicationRecord
  include Recordable

  has_one :recording, as: :recordable, touch: true

  def title
    description
  end

  def commentable?
    true
  end

  def copyable?
    true
  end
end

class Document < ApplicationRecord
  include Recordable

  has_one :recording, as: :recordable, touch: true

  has_rich_text :body

  def commentable?
    true
  end

  def copyable?
    true
  end
end
```

The recordings table stays lean:

```ruby
create_table :recordings do |t|
  t.references :account, null: false
  t.references :creator, null: false
  t.references :parent, null: true
  t.string :recordable_type, null: false
  t.references :recordable, polymorphic: true, null: false
  t.timestamps
end
```

Each recordable gets its own table with only the columns it needs:

```ruby
create_table :messages do |t|
  t.string :subject
  t.timestamps
end

create_table :todos do |t|
  t.text :description
  t.datetime :completed_at
  t.date :due_date
  t.timestamps
end

create_table :documents do |t|
  t.string :title
  t.integer :version_number
  t.timestamps
end
```

## Why This Works: The Lean Recordings Table

The genius of this pattern is keeping the recordings table intentionally lean. It stores **only** what's common across all types:

- Account reference (multi-tenancy)
- Creator reference
- Parent reference (tree structure)
- Recordable type and ID (polymorphic)
- Timestamps

No heavy content. No type-specific data. Just metadata and relationships.

This makes the recordings table:

**Fast to Query**
The table is narrow. Each row is small on disk. Indexes are compact. Queries are fast even with billions of rows.

**Easy to Paginate**
Timeline of mixed content? Just query recordings with `LIMIT` and `OFFSET`. Simple, efficient, works at scale.

**Cheap to Copy**
Copying a message 100 times? Create 100 recording rows pointing to the same message recordable. Storage efficient, operationally simple.

**Schema-Stable**
New content types don't touch the recordings table. They get their own fresh tables. The core table never changes.

## Immutability and Version History

One of the most powerful aspects of this pattern is how it enables immutable recordables:

```ruby
# Updating a message doesn't modify the message recordable
def update_message(recording, new_subject:)
  # Create a NEW message recordable
  new_message = Message.create!(subject: new_subject)

  # Point the recording to the new version
  recording.update!(recordable: new_message)

  # The original message recordable remains intact
end
```

This gives you version history for free. The old message is still in the database, unchanged. You can compare versions, restore previous versions, show edit history—all without additional version tracking infrastructure.

In practice, this looks like:

```ruby
module Message::Versioning
  extend ActiveSupport::Concern

  included do
    has_many :recordings, as: :recordable
    has_many :previous_versions, -> { order(created_at: :desc) },
             through: :recordings, source: :recordable
  end

  def update_content(new_content)
    new_version = self.class.create!(
      subject: subject,
      content: new_content
    )

    recording.update!(recordable: new_version)
  end

  def version_history
    previous_versions.where(recordable_type: self.class.name)
  end
end
```

The events table (which tracks all changes) naturally integrates with this:

```ruby
class Event < ApplicationRecord
  belongs_to :recording

  # The event points to the recording, which points to the recordable
  # If the recordable changes, events still reference the recording
  # You can traverse the history through recordings to see what changed
end
```

## Efficient Copy Operations

Copying content becomes trivial:

```ruby
# Copy a message from one project to another
def copy_message(original_recording, to_project:)
  # Create a new recording pointing to the SAME message recordable
  Recording.create!(
    account: to_project.account,
    creator: Current.user,
    parent: to_project,
    recordable: original_recording.recordable
  )
end
```

One hundred copies of a message? 100 recording rows, 1 message recordable. Storage efficient by default.

Want copy-on-write semantics instead?

```ruby
def copy_message_with_new_version(original_recording, to_project:)
  # Duplicate the message recordable
  new_message = original_recording.recordable.dup
  new_message.save!

  # Create a recording pointing to the new message
  Recording.create!(
    account: to_project.account,
    creator: Current.user,
    parent: to_project,
    recordable: new_message
  )
end
```

The pattern supports both strategies. You choose based on your domain requirements.

## Query Efficiency

Fetching a timeline of mixed content is a single query against recordings:

```ruby
# All activity in a project, newest first
project.recordings.order(created_at: :desc).limit(50)

# Filter by type
project.recordings.message.order(created_at: :desc)

# Rails generates: WHERE recordable_type = 'Message'

# Filter by multiple types
project.recordings.where(recordable_type: ['Message', 'Comment']).order(created_at: :desc)
```

Pagination is straightforward because you're paginating a single table with a single sort order. No complex UNION queries across different tables.

Eager loading works naturally:

```ruby
# Load recordings with their recordables in two queries
project.recordings
  .includes(:recordable)
  .order(created_at: :desc)
  .limit(50)
```

Rails is smart about polymorphic eager loading. It groups recordable IDs by type and issues one query per type. Fast and efficient.

## Capability-Based Polymorphism

This is where the pattern shines for building generic systems. Instead of checking types, you check capabilities:

```ruby
# BAD: Type checking creates tight coupling
def add_comment(recording, text)
  case recording.recordable_type
  when 'Message' then recording.recordable.comments.create!(text: text)
  when 'Document' then recording.recordable.comments.create!(text: text)
  when 'File' then raise "Files can't be commented on"
  # ...
  end
end

# GOOD: Capability checking is extensible
def add_comment(recording, text)
  if recording.commentable?
    recording.comments.create!(text: text)
  else
    raise "This type doesn't support comments"
  end
end
```

Each recordable declares its capabilities:

```ruby
class Message < ApplicationRecord
  def commentable?
    true
  end

  def copyable?
    true
  end

  def movable?
    true
  end

  def exportable?
    true
  end
end

class File < ApplicationRecord
  def commentable?
    false  # Files can't be commented on
  end

  def copyable?
    true
  end

  def movable?
    true
  end

  def exportable?
    true
  end
end
```

This creates a protocol. Generic systems interact with recordings through capabilities, not types:

```ruby
class RecordingsController < ApplicationController
  def copy
    if @recording.copyable?
      @recording.copy_to(target_project)
      redirect_to @recording, notice: "Copied successfully"
    else
      redirect_to @recording, alert: "This can't be copied"
    end
  end

  def move
    if @recording.movable?
      @recording.move_to(target_project)
      redirect_to @recording, notice: "Moved successfully"
    else
      redirect_to @recording, alert: "This can't be moved"
    end
  end

  def destroy
    @recording.trash
    redirect_to recordings_path, notice: "Moved to trash"
  end

  def restore
    @recording.restore_from_trash
    redirect_to @recording, notice: "Restored"
  end
end
```

One controller handles copying, moving, trashing, and restoring for **all recordable types**. The behavior is uniform because it's defined on recordings, not on specific types.

Want to add a new capability? Define the protocol:

```ruby
# Adding "archivable" capability
class Message < ApplicationRecord
  def archivable?
    true
  end

  def archive
    update!(archived_at: Time.current)
  end
end

class File < ApplicationRecord
  def archivable?
    false  # Files can't be archived
  end
end

# Generic controller action works for all archivable types
def archive
  if @recording.archivable?
    @recording.recordable.archive
    redirect_to @recording, notice: "Archived"
  else
    redirect_to @recording, alert: "This can't be archived"
  end
end
```

New type? Just implement the capabilities:

```ruby
class Calendar < ApplicationRecord
  include Recordable

  has_one :recording, as: :recordable, touch: true

  def commentable?
    true
  end

  def copyable?
    true
  end

  def movable?
    true
  end

  def exportable?
    true
  end

  def archivable?
    false  # Calendars can't be archived
  end
end
```

No changes to controllers. No changes to services. The generic systems already know how to handle calendars because they declare their capabilities.

## Generic Controllers and Services

The capability pattern enables generic controllers that work uniformly across all types:

```ruby
class RecordingsController < ApplicationController
  def show
    @recording = current_account.recordings.find(params[:id])
    # Recording delegates title, formatted_content, etc. to its recordable
  end

  def copy
    @recording = current_account.recordings.find(params[:id])

    if @recording.copyable?
      target = current_account.recordings.find(params[:target_id])
      @new_recording = @recording.copy_to(parent: target)
      redirect_to @new_recording
    else
      redirect_to @recording, alert: "This can't be copied"
    end
  end

  def move
    @recording = current_account.recordings.find(params[:id])

    if @recording.movable?
      target = current_account.recordings.find(params[:target_id])
      @recording.move_to(parent: target)
      redirect_to @recording
    else
      redirect_to @recording, alert: "This can't be moved"
    end
  end
end
```

Exporters work generically:

```ruby
class RecordingsExporter
  def initialize(recordings)
    @recordings = recordings
  end

  def export_to_json
    @recordings.map do |recording|
      {
        id: recording.id,
        type: recording.recordable_type,
        created_at: recording.created_at,
        creator: recording.creator.name,
        content: recording.recordable.export_data  # Delegated to recordable
      }
    end.to_json
  end
end

# Each recordable implements export_data
class Message < ApplicationRecord
  def export_data
    {
      subject: subject,
      content: content.to_plain_text
    }
  end
end

class Todo < ApplicationRecord
  def export_data
    {
      description: description,
      completed: completed?,
      due_date: due_date
    }
  end
end
```

Copiers work generically:

```ruby
class RecordingCopier
  def copy(recording, to_parent:)
    return unless recording.copyable?

    # Recordings handle copying themselves
    recording.copy_to(parent: to_parent)
  end

  def copy_tree(recording, to_parent:)
    return unless recording.copyable?

    new_recording = recording.copy_to(parent: to_parent)

    recording.children.each do |child|
      copy_tree(child, to_parent: new_recording)
    end

    new_recording
  end
end
```

The pattern is: generic systems query capabilities and delegate specific behavior to recordables. This keeps coupling low and extensibility high.

## Tree Structures

Recordings naturally form trees through the parent relationship:

```ruby
# Message boards contain messages
board = Recording.create!(recordable: MessageBoard.create!(...))

# Messages contain comments
message = Recording.create!(recordable: Message.create!(...), parent: board)
comment = Recording.create!(recordable: Comment.create!(...), parent: message)

# Comments contain attachments
attachment = Recording.create!(recordable: File.create!(...), parent: comment)
```

All parent-child relationships use the recordings table. This creates a uniform tree structure regardless of content types:

```ruby
class Recording < ApplicationRecord
  belongs_to :parent, class_name: "Recording", optional: true
  has_many :children, class_name: "Recording", foreign_key: :parent_id

  def ancestors
    parent ? [parent, *parent.ancestors] : []
  end

  def descendants
    children + children.flat_map(&:descendants)
  end

  def siblings
    parent ? parent.children.where.not(id: id) : Recording.none
  end
end
```

Want to show everything under a message board?

```ruby
# All descendants, ordered chronologically
board.descendants.order(created_at: :desc)

# Just direct children
board.children.order(created_at: :desc)

# Messages only (filtering by type)
board.children.message.order(created_at: :desc)
```

Want to navigate up the tree?

```ruby
# Find the board this comment belongs to
comment.ancestors.find { |a| a.recordable_type == 'MessageBoard' }

# Or with a named method
def find_board
  recording.ancestors.find(&:message_board?) || recording
end
```

This uniform tree structure means tree-walking algorithms work the same way for all content types. Exporters, copiers, archivers—they all traverse the recordings tree without caring about specific types.

## Caching Benefits

Russian-doll caching works beautifully with this pattern because everything is wrapped in recordings:

```erb
<!-- app/views/recordings/_recording.html.erb -->
<% cache recording do %>
  <div class="recording">
    <%= render recording.recordable %>
  </div>
<% end %>
```

When a recordable changes, it touches its recording. The recording's `updated_at` changes. The cache key changes. The cache expires.

When a child changes, it touches its parent recording. The parent's cache expires. The chain propagates up the tree.

```ruby
class Message < ApplicationRecord
  has_one :recording, as: :recordable, touch: true  # Touch on update

  # When content changes, the recording's updated_at changes
  # Any parent recordings get touched too
end

class Recording < ApplicationRecord
  belongs_to :parent, class_name: "Recording", optional: true, touch: true

  # When this recording changes, touch the parent
  # Cache invalidation propagates up the tree
end
```

This creates automatic, correct cache invalidation:

- Update a comment → touches comment recording → touches message recording → touches board recording
- All cached fragments expire correctly
- No manual cache clearing needed

The pattern is uniform across all types. You don't need type-specific cache keys or invalidation logic.

## The Trade-offs

This pattern is powerful, but it's not simple. You need to understand the costs:

### Higher Learning Curve

New developers struggle with delegated types. The indirection isn't intuitive:

- Why are there two tables?
- Why don't I update the message directly?
- Where does this method actually live?

It takes time to internalize the pattern. You need to invest in documentation and code reviews to help people understand it.

### Recordables Become "Dumb"

Recordables are mostly data holders. The interesting behavior lives on recordings or in generic services:

```ruby
# Recordables: mostly data
class Message < ApplicationRecord
  has_rich_text :content

  def title
    subject
  end
end

# Recordings: behavior
class Recording < ApplicationRecord
  def copy_to(parent:)
    return unless copyable?

    # Implementation here
  end

  def trash
    update!(trashed_at: Time.current)
  end
end

# Generic services: operations
class RecordingsExporter
  # Implementation here
end
```

This feels backward to developers used to putting behavior on domain models. The message isn't "smart" anymore. It's just data with a few formatting methods.

### Behavior Is Abstract

Finding where behavior lives requires understanding the abstraction:

```ruby
# Where does "copy" live? Not on Message, on Recording
message_recording.copy_to(parent: board)

# Where does "export" live? In the exporter service
RecordingsExporter.new(recordings).export_to_json

# Where does the title come from? Delegated from recording to message
message_recording.title  # -> message.title -> message.subject
```

This makes the codebase harder to navigate at first. Command-click on `title` in your editor and you end up in the wrong place.

### Non-Obvious Code Paths

Delegation creates indirection. You're calling methods on recordings that execute on recordables. Callbacks can fire in surprising places. The flow isn't linear:

```ruby
# Simple-looking code
recording.update!(recordable: new_message)

# Actually triggers:
# 1. Recording update
# 2. Touch on old message (via callback)
# 3. Touch on new message (via callback)
# 4. Parent recording touched (via callback)
# 5. Cache expiration (via touch)
# 6. Possibly background jobs (via after_commit)
```

Debugging this requires understanding the full callback chain.

### Steeper On-Ramp, Faster Highway

The pattern pays off over time, not immediately:

- **Week 1**: "Why is this so complicated?"
- **Month 1**: "I think I understand the structure now"
- **Month 3**: "Adding a new type is easy once you know the pattern"
- **Month 6**: "We just added calendars in two days. This is amazing."

The return on investment comes when you're building your 10th content type, not your first. If you only have 3-4 types and don't expect growth, the pattern is overkill.

## When to Use This Pattern

Use delegated types when:

1. **You have many content types** (or expect to)
2. **Types share operational patterns** (commenting, copying, moving, trashing)
3. **Types have significantly different data** (not just 1-2 varying columns)
4. **You need version history**
5. **You expect to scale** (millions of rows)
6. **You're building a content-oriented system** (CMS, project management, email, documents)

Don't use delegated types when:

1. **You have 2-3 types** (STI is simpler)
2. **Types are similar** (shared columns outnumber type-specific ones)
3. **You don't need version history**
4. **The types have fundamentally different lifecycles** (not shared operations)
5. **You're building a simple CRUD app** (overkill for basic forms)

## Implementation Guide

### Step 1: Identify the Common Abstraction

What do your content types have in common? In Basecamp:

- All belong to an account
- All have a creator
- All have timestamps
- All can have children (tree structure)

This becomes your recordings table.

### Step 2: Identify Type-Specific Data

What makes each type unique? In Basecamp:

- Messages have subjects and content
- To-dos have descriptions and completion status
- Documents have titles and bodies
- Files have storage references

This becomes your recordables tables.

### Step 3: Create the Schema

```ruby
# Recordings: the common abstraction
create_table :recordings do |t|
  t.references :account, null: false, foreign_key: true
  t.references :creator, null: false, foreign_key: { to_table: :users }
  t.references :parent, foreign_key: { to_table: :recordings }

  t.string :recordable_type, null: false
  t.bigint :recordable_id, null: false

  t.datetime :trashed_at
  t.timestamps

  t.index [:recordable_type, :recordable_id]
  t.index [:account_id, :created_at]
  t.index [:parent_id, :created_at]
end

# Recordables: type-specific data
create_table :messages do |t|
  t.string :subject
  t.timestamps
end

create_table :todos do |t|
  t.text :description
  t.datetime :completed_at
  t.date :due_date
  t.timestamps
end

create_table :documents do |t|
  t.string :title
  t.integer :version_number
  t.timestamps
end
```

### Step 4: Define the Models

```ruby
class Recording < ApplicationRecord
  belongs_to :account
  belongs_to :creator, class_name: "User"
  belongs_to :parent, class_name: "Recording", optional: true, touch: true
  has_many :children, class_name: "Recording", foreign_key: :parent_id

  delegated_type :recordable, types: %w[ Message Todo Document ],
                              dependent: :destroy

  # Delegate common methods to recordables
  delegate :title, :copyable?, :commentable?, to: :recordable

  scope :not_trashed, -> { where(trashed_at: nil) }
  scope :chronologically, -> { order(created_at: :desc) }

  def trash
    update!(trashed_at: Time.current)
  end

  def restore_from_trash
    update!(trashed_at: nil)
  end

  def trashed?
    trashed_at.present?
  end
end

# Recordables concern for shared behavior
module Recordable
  extend ActiveSupport::Concern

  included do
    has_one :recording, as: :recordable, touch: true
  end

  def title
    raise NotImplementedError, "#{self.class.name} must implement #title"
  end

  def copyable?
    false
  end

  def commentable?
    false
  end
end

class Message < ApplicationRecord
  include Recordable

  has_rich_text :content

  def title
    subject
  end

  def copyable?
    true
  end

  def commentable?
    true
  end
end

class Todo < ApplicationRecord
  include Recordable

  def title
    description
  end

  def copyable?
    true
  end

  def commentable?
    true
  end

  def complete
    update!(completed_at: Time.current)
  end

  def incomplete
    update!(completed_at: nil)
  end

  def completed?
    completed_at.present?
  end
end

class Document < ApplicationRecord
  include Recordable

  has_rich_text :body

  def copyable?
    true
  end

  def commentable?
    true
  end
end
```

### Step 5: Build Generic Controllers

```ruby
class RecordingsController < ApplicationController
  before_action :set_recording, only: [:show, :edit, :update, :destroy]

  def show
    # Render delegates to the recordable's partial
    # app/views/messages/_message.html.erb
    # app/views/todos/_todo.html.erb
    # etc.
  end

  def copy
    @recording = current_account.recordings.find(params[:id])
    @target = current_account.recordings.find(params[:target_id])

    if @recording.copyable?
      @new_recording = @recording.copy_to(parent: @target)
      redirect_to @new_recording
    else
      redirect_to @recording, alert: "Can't copy this type"
    end
  end

  def destroy
    @recording.trash
    redirect_to recordings_path, notice: "Moved to trash"
  end

  private
    def set_recording
      @recording = current_account.recordings.find(params[:id])
    end
end
```

### Step 6: Implement Type-Specific Controllers When Needed

```ruby
class MessagesController < ApplicationController
  def new
    @message = Message.new
  end

  def create
    @message = Message.new(message_params)

    if @message.save
      @recording = Recording.create!(
        account: current_account,
        creator: current_user,
        parent: parent_recording,
        recordable: @message
      )

      redirect_to @recording
    else
      render :new
    end
  end

  private
    def message_params
      params.require(:message).permit(:subject, :content)
    end

    def parent_recording
      current_account.recordings.find(params[:parent_id])
    end
end
```

## Real-World Example: Adding Comments

Let's walk through adding comments to our system using delegated types:

```ruby
# 1. Create the comment recordable
class Comment < ApplicationRecord
  include Recordable

  has_rich_text :body

  def title
    "Comment by #{recording.creator.name}"
  end

  def copyable?
    false  # Comments aren't copyable
  end

  def commentable?
    false  # Comments can't be commented on (no nested comments)
  end
end

# 2. Add comments relationship to recordings
class Recording < ApplicationRecord
  has_many :comments, -> { comment.chronologically },
           class_name: "Recording",
           foreign_key: :parent_id

  def commentable?
    recordable.commentable?  # Delegate to the recordable
  end
end

# 3. Create a controller for creating comments
class CommentsController < ApplicationController
  def create
    @parent = current_account.recordings.find(params[:recording_id])

    unless @parent.commentable?
      redirect_to @parent, alert: "This can't be commented on"
      return
    end

    @comment = Comment.new(comment_params)

    if @comment.save
      @recording = Recording.create!(
        account: current_account,
        creator: current_user,
        parent: @parent,
        recordable: @comment
      )

      redirect_to @parent
    else
      render :new
    end
  end

  private
    def comment_params
      params.require(:comment).permit(:body)
    end
end
```

Notice what happened:

1. We created a new recordable type (Comment)
2. We declared its capabilities (not copyable, not commentable)
3. We added a relationship to recordings (has_many :comments)
4. We created a type-specific controller for creating comments

We **didn't** modify:

- The recordings table schema
- Generic controllers (RecordingsController)
- Other recordable types
- Export, copy, or trash functionality

The new type integrates seamlessly with existing generic systems.

## Performance Considerations

### The Extra Join

Delegated types require joining recordings to recordables:

```sql
SELECT recordings.*, messages.*
FROM recordings
INNER JOIN messages ON messages.id = recordings.recordable_id
WHERE recordings.recordable_type = 'Message'
  AND recordings.account_id = 1
ORDER BY recordings.created_at DESC
LIMIT 50
```

This is an extra join compared to STI. But it's a simple join on a primary key, which is very fast.

The trade-off is worth it because:

1. The recordings table is lean (fast scans)
2. Type-specific tables have only relevant columns (no waste)
3. Indexes are smaller and more effective
4. The database can optimize queries better

### Eager Loading

Use `includes(:recordable)` to avoid N+1 queries:

```ruby
# Bad: N+1 queries
recordings = account.recordings.limit(50)
recordings.each { |r| puts r.title }  # Queries each recordable

# Good: Eager load recordables
recordings = account.recordings.includes(:recordable).limit(50)
recordings.each { |r| puts r.title }  # No additional queries
```

Rails is smart about polymorphic eager loading. It groups IDs by type and issues one query per type.

### Pagination

Paginating through recordings is simple and efficient:

```ruby
# Page 1
account.recordings.limit(50).offset(0)

# Page 2
account.recordings.limit(50).offset(50)
```

This is much simpler than paginating across multiple tables with a UNION.

### Counting

Counting recordings is fast because it's a single table:

```ruby
account.recordings.count
account.recordings.message.count
account.recordings.where(recordable_type: ['Message', 'Comment']).count
```

### Caching

The delegation pattern plays well with Rails caching:

```ruby
# Fragment caching
<% cache recording do %>
  <%= render recording.recordable %>
<% end %>

# Russian-doll caching
<% cache board_recording do %>
  <% board_recording.children.each do |message_recording| %>
    <% cache message_recording do %>
      <%= render message_recording.recordable %>

      <% message_recording.comments.each do |comment_recording| %>
        <% cache comment_recording do %>
          <%= render comment_recording.recordable %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

Because recordables touch their recordings on update, cache keys automatically stay correct.

## Testing Strategies

### Test Capabilities, Not Types

```ruby
class RecordingTest < ActiveSupport::TestCase
  test "commentable recordings allow comments" do
    message = recordings(:message_one)
    assert message.commentable?

    comment = Comment.create!(body: "Test")
    comment_recording = Recording.create!(
      account: message.account,
      creator: message.creator,
      parent: message,
      recordable: comment
    )

    assert_includes message.comments, comment_recording
  end

  test "non-commentable recordings don't allow comments" do
    file = recordings(:file_one)
    refute file.commentable?
  end
end
```

### Test Type-Specific Behavior on Recordables

```ruby
class MessageTest < ActiveSupport::TestCase
  test "title returns subject" do
    message = Message.create!(subject: "Hello")
    assert_equal "Hello", message.title
  end

  test "messages are commentable" do
    message = Message.new
    assert message.commentable?
  end

  test "messages are copyable" do
    message = Message.new
    assert message.copyable?
  end
end
```

### Test Generic Operations on Recordings

```ruby
class RecordingsControllerTest < ActionDispatch::IntegrationTest
  test "copying a copyable recording succeeds" do
    message = recordings(:message_one)
    target = recordings(:board_one)

    assert message.copyable?

    post copy_recording_path(message), params: { target_id: target.id }

    assert_response :redirect
    new_recording = Recording.last
    assert_equal target, new_recording.parent
    assert_equal message.recordable, new_recording.recordable
  end

  test "trashing a recording marks it as trashed" do
    message = recordings(:message_one)

    delete recording_path(message)

    assert message.reload.trashed?
  end
end
```

## Migration Path

If you're considering moving to delegated types from another pattern, here's how to approach it:

### From STI

1. Create recordables tables with type-specific columns
2. Create recordings table with common columns
3. Migrate data in batches:

```ruby
class MigrateToRecordings < ActiveRecord::Migration[7.0]
  def up
    Message.find_each do |old_message|
      new_message = NewMessage.create!(
        subject: old_message.subject
        # other message-specific fields
      )

      Recording.create!(
        account_id: old_message.account_id,
        creator_id: old_message.creator_id,
        parent_id: map_parent_id(old_message.parent_id),
        recordable: new_message,
        created_at: old_message.created_at,
        updated_at: old_message.updated_at
      )
    end
  end

  def map_parent_id(old_parent_id)
    # Map old parent IDs to new recording IDs
    # Store mapping in a hash or temporary table
  end
end
```

4. Update foreign keys to point to recordings instead of old table
5. Remove old STI table

### From Separate Tables

If you have separate tables with no common abstraction:

1. Identify what they share (account, creator, timestamps, parent)
2. Create recordings table
3. Rename existing tables to be recordables (or create new ones)
4. Migrate data to create recording rows
5. Update foreign keys

## The Philosophy

Delegated types is about separation of concerns at the data level:

- **Recordings**: Shared structure, relationships, timeline
- **Recordables**: Type-specific data
- **Generic systems**: Operate on capabilities, not types

This separation enables:

- Adding types without schema changes to core tables
- Generic operations that work uniformly
- Efficient storage (only store what's needed)
- Natural version history
- Scale to billions of rows

The trade-off is indirection and abstraction. You're giving up simplicity for power. That's the right choice when you're building a content-oriented system that needs to scale and evolve. It's the wrong choice for a simple CRUD app with a handful of models.

## Conclusion

Delegated types is a powerful pattern for content-oriented systems. It solves real problems that emerge when you have diverse content types with shared operational patterns. Basecamp and HEY use it extensively because it lets them add new content types rapidly without touching core tables or rewriting generic systems.

But it's not a pattern you reach for reflexively. It has costs: complexity, indirection, a learning curve. Use it when those costs are justified by the benefits: many content types, shared operations, version history, scale.

When you do use it, embrace the pattern fully. Build generic controllers. Use capability-based polymorphism. Keep recordables focused on data. Put shared behavior on recordings or in generic services. Test capabilities, not types.

Done well, delegated types creates a system that accelerates feature development. "Build features that should take months in weeks" isn't hyperbole when your architecture supports adding new content types without touching existing code.

That's the power of the pattern. Use it wisely.
