# Multi-Tenant Authentication & Authorization

This document describes architectural patterns for building SaaS applications with team/account-based multi-tenancy, passwordless authentication, and fine-grained authorization. These patterns are common in well-architected Rails applications and frameworks like BulletTrain and Jumpstart Pro.

## The Core Insight: Separate Identity from Membership

The most important architectural decision is separating **who someone is** from **their membership in a team**.

### Two Distinct Concepts

**Identity (Global)**
- Represents a unique person across the entire platform
- Tied to an email address
- Handles authentication (proving who you are)
- One Identity can belong to multiple teams/accounts
- Owns sessions, magic links, API tokens

**User (Per-Account Membership)**
- Represents a person's membership within a specific account/team
- Handles authorization (what you can do within this account)
- Has a role within the account (owner, admin, member)
- Has access permissions to specific resources
- Linked to exactly one Account and one Identity

### Why This Separation Matters

**Problem with traditional User models:**
Most Rails tutorials create a single `User` model that conflates identity and membership. This creates problems:

1. If someone is invited to a second team, do you create a duplicate user with the same email?
2. How do you handle someone switching between teams?
3. Where do authentication tokens live if a user can be in multiple accounts?

**Solution with Identity + User:**

```
Identity (email: "jane@example.com")
    │
    ├── User (account: "Acme Corp", role: owner)
    ├── User (account: "Consulting LLC", role: member)
    └── User (account: "Side Project", role: admin)
```

Jane has one identity but three team memberships. She authenticates once (via her Identity) and can switch between accounts. Each account sees her as a different User with different permissions.

### Implementation Principles

**Identity should:**
- Be the authentication target (sessions belong to Identity)
- Own API tokens and magic links
- Have minimal profile data (just email, maybe a staff flag)
- Provide a method to "join" an account (creating a User)
- Be transferable between accounts

**User should:**
- Belong to exactly one Account
- Belong to exactly one Identity (optionally, for invited-but-not-joined users)
- Have account-specific attributes (name, role, active status)
- Be the authorization target (permissions checked against User)
- Have a unique constraint on (account_id, identity_id)

## The Account/Team Model

Every SaaS application needs a concept of a team, organization, or account. This is your primary tenant in a multi-tenant system.

### Account Responsibilities

**Ownership:**
- All business resources belong to an Account (boards, projects, cards, documents)
- Users belong to Accounts (not the other way around)
- Account is the billing entity

**Identification:**
- Each Account has a unique external identifier for URLs
- This identifier should be opaque (not sequential integers that reveal business info)
- Use base36 encoding of a random or sequential number: `1a2b3c4`

**Creation:**
- Accounts should be created atomically with their first owner
- A single method like `Account.create_with_owner(account:, owner:)` ensures consistency
- The owner User is created with special role and verified status
- Consider creating a "system" user for automated actions

### Account Creation Pattern

When creating an account:

1. Generate a unique external identifier
2. Create the Account record
3. Create a system user (for automated actions, non-human)
4. Create the owner user (linked to the creating Identity)
5. Set up any default resources (templates, sample data)
6. Return the account and owner

This should happen in a transaction. The owner should be marked as verified immediately (they just proved they own their email via magic link).

## URL-Based Multi-Tenancy

The cleanest approach to multi-tenancy in Rails is URL path prefixes.

### The Pattern

```
https://app.example.com/1a2b3c4/boards/5
                        ^^^^^^^^
                        Account identifier
```

Every authenticated route is prefixed with the account identifier. This has several advantages:

1. **Explicit context**: You always know which account you're in
2. **Shareable links**: URLs can be shared and they work for anyone with access
3. **No subdomain complexity**: No wildcard DNS, no cookie scope issues
4. **Simple routing**: One application serves all accounts

### Middleware Implementation

Create middleware that runs early in the request cycle:

1. **Extract** the account identifier from the path (e.g., `/1a2b3c4/boards/5`)
2. **Look up** the Account by external identifier
3. **Set** the current account in a request-scoped location
4. **Modify** the path so Rails sees `/boards/5` (move prefix to SCRIPT_NAME)
5. **Continue** with the request

The key insight is moving the account prefix from `PATH_INFO` to `SCRIPT_NAME`. This makes Rails think the application is "mounted" at that path, so all URL helpers automatically include the prefix.

### Current Attributes Pattern

Use Rails' `CurrentAttributes` to track request-scoped state:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :account
  attribute :session
  attribute :identity
  attribute :user

  # When identity is set, automatically find the user for current account
  def identity=(identity)
    super
    self.user = identity&.user_for(account)
  end
end
```

This pattern gives you:
- `Current.account` - the current tenant
- `Current.identity` - who is authenticated
- `Current.user` - their membership in current account
- `Current.session` - the active session

Set `Current.account` in middleware, set `Current.identity` in authentication, and `Current.user` is derived automatically.

## Passwordless Authentication (Magic Links)

Magic link authentication eliminates passwords entirely. Users prove their identity by clicking a link sent to their email.

### Why Passwordless?

1. **No password storage**: No bcrypt, no breach risk, no password resets
2. **Simpler UX**: No "forgot password" flows
3. **Email verification built-in**: If they click the link, they own the email
4. **Phishing resistant**: Links are time-limited and single-use

### The Flow

**Sign In:**
1. User enters their email address
2. System looks up or creates an Identity for that email
3. System generates a short code (6 characters) and stores it with expiration (15 minutes)
4. System emails the code/link to the user
5. User clicks link or enters code
6. System verifies code, creates Session, sets cookie
7. User is now authenticated

**Sign Up:**
1. Same as sign in, but after verification...
2. System creates Account with owner
3. System creates User linked to Identity and Account
4. User lands in their new account

### Magic Link Design

**The magic link record should have:**
- Reference to the Identity
- A short, unique code (6 alphanumeric characters)
- Expiration timestamp (15 minutes)
- Purpose flag (sign_in vs sign_up vs other)
- Single-use enforcement (delete after consumption)

**Security considerations:**
- Codes should be random and unpredictable
- Verify uniqueness before saving
- Rate limit magic link requests per email
- Log failed verification attempts
- Consider IP/user-agent verification for extra security

### Session Management

**Sessions should be database records:**
- Enables explicit revocation (logout everywhere)
- Tracks metadata (IP, user agent, last accessed)
- Can set expiration policies
- Survives server restarts

**Cookie design:**
- Use signed cookies (Rails' `cookies.signed`)
- Set `httponly: true` (not accessible to JavaScript)
- Set `same_site: :lax` (CSRF protection)
- Store only the session token, not user data
- Consider whether to use permanent or session cookies

**Session resumption:**
1. Read session token from cookie
2. Find session by signed token
3. Verify session is not expired
4. Set Current.session and Current.identity
5. Current.user is derived from identity + current account

## Authorization: Roles and Access

Authorization happens at the User level (not Identity), because permissions are account-specific.

### Role Hierarchy

A simple, effective role system:

| Role | Description | Capabilities |
|------|-------------|--------------|
| `system` | Automated actions | Non-human, for background jobs |
| `owner` | Account creator | All admin powers + cannot be removed |
| `admin` | Administrators | Manage users, settings, all resources |
| `member` | Regular users | Access assigned resources |

**Key authorization questions:**

```ruby
user.admin?  # Is this an owner or admin?
user.owner?  # Is this specifically the owner?
user.can_administer?(other_user)  # Can manage this user?
user.can_administer_board?(board)  # Can manage this board?
```

**Rules:**
- Owners cannot be demoted or removed by anyone (protect the account)
- Admins can manage non-owner users
- Users can always edit their own profile
- Resource creators often get special permissions on their resources

### Resource-Level Access Control

Beyond roles, you often need per-resource access control. For example, a user might only have access to certain projects or boards.

**The Access Record Pattern:**

Create an explicit join model between Users and Resources:

```
Access
  - user_id
  - board_id (or resource_id + resource_type for polymorphic)
  - account_id (for data isolation)
  - involvement (enum: access_only, watching, etc.)
  - accessed_at (for "recently accessed" sorting)
```

**Two access models:**

1. **All-access resources**: Everyone in the account can access
   - Toggle via a boolean on the resource
   - When enabled, grant access to all active users
   - New users automatically get access

2. **Selective-access resources**: Explicit grants required
   - Only users with Access records can see the resource
   - Creator automatically gets access
   - Admins can grant/revoke access

**Querying accessible resources:**

```ruby
# User's accessible boards (through Access records)
user.boards  # Returns boards where access exists

# User's accessible cards (through accessible boards)
user.accessible_cards  # Cards in boards user can access
```

### Cleaning Up on Access Revocation

When a user loses access to a resource, clean up related data:
- Remove mentions of that user in the resource
- Remove notifications about the resource
- Remove "watching" status
- This prevents information leakage and stale data

## The Signup Flow

A well-designed signup flow creates Account, Identity, and User atomically.

### Two-Phase Signup

**Phase 1: Email Verification**
1. User enters email
2. Create or find Identity
3. Send magic link with "signup" purpose
4. Wait for verification

**Phase 2: Account Creation**
1. Magic link verified
2. Collect additional info (name, account name)
3. Create Account with owner User
4. Set up default resources (templates, sample projects)
5. Redirect into the new account

### The Signup Object

Encapsulate signup logic in a plain Ruby object:

```ruby
class Signup
  attr_accessor :email, :name, :account_name

  def create_identity
    # Find or create identity, send magic link
  end

  def complete
    # Create account with owner, set up defaults
  end
end
```

This keeps controllers thin and makes the flow testable.

### Account Name Generation

If you don't require an account name upfront, generate one:
- Use the owner's name + "'s Account"
- Or use the email domain: "example.com Account"
- Let users rename later

## Controller Patterns

### Authentication Concern

Create a concern that handles authentication for all controllers:

```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_account
    before_action :require_authentication
  end

  private
    def require_account
      # Ensure Current.account is set (from middleware)
      # Redirect to account selector if not
    end

    def require_authentication
      resume_session || authenticate_by_token || request_authentication
    end

    def resume_session
      # Try to load session from cookie
    end

    def request_authentication
      # Redirect to login
    end
end
```

**Skipping authentication:**
- `skip_before_action :require_authentication` for public pages
- Still call `resume_session` to load existing sessions
- Use `allow_unauthenticated_access` helper

### Authorization Concern

Separate authorization checks:

```ruby
module Authorization
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_access_account
  end

  private
    def ensure_can_access_account
      return unless Current.user
      redirect_to inactive_path unless Current.user.active?
    end
end
```

### Resource Scoping

Always load resources through the current user's accessible scope:

```ruby
def set_board
  @board = Current.user.boards.find(params[:id])
end

def set_card
  @card = Current.user.accessible_cards.find(params[:id])
end
```

This prevents users from accessing resources they shouldn't see, even if they guess the ID.

## Multi-Tenant Mode Toggle

Support both single-tenant and multi-tenant deployments:

```ruby
Account.multi_tenant = ENV["MULTI_TENANT"] == "true"

def self.accepting_signups?
  multi_tenant || Account.none?
end
```

- **Multi-tenant**: Anyone can create accounts (SaaS mode)
- **Single-tenant**: Only first setup creates account, then invite-only

## Background Jobs and Current Context

When jobs run, they need account context:

1. **Serialize context**: Store account_id in job arguments
2. **Restore context**: Set Current.account when job runs
3. **Consider**: Create a job mixin that handles this automatically

```ruby
module AccountContext
  extend ActiveSupport::Concern

  included do
    attr_accessor :account_id

    before_perform do
      Current.account = Account.find(account_id)
    end
  end
end
```

## Summary: The Complete Picture

**Request Flow:**

```
1. Request arrives: GET /1a2b3c4/boards/5
2. Middleware extracts account ID, sets Current.account
3. Authentication loads session from cookie
4. Current.identity set from session
5. Current.user derived from identity + account
6. Authorization checks user is active
7. Controller loads board through user.boards
8. User sees only what they have access to
```

**Data Model:**

```
Identity (global, email-based)
    │
    └── Session (authentication state)
    └── MagicLink (passwordless auth)
    └── AccessToken (API auth)

Account (tenant)
    │
    └── User (membership, role, permissions)
           │
           └── Access (per-resource permissions)

    └── Board/Project/Resource
           │
           └── Card/Task/Item
```

**Key Principles:**

1. **Separate identity from membership** - Authentication is global, authorization is per-account
2. **URL-based multi-tenancy** - Simple, explicit, shareable
3. **Passwordless by default** - Simpler and more secure
4. **Explicit access records** - Fine-grained resource permissions
5. **Current attributes pattern** - Clean request-scoped context
6. **Middleware for tenant extraction** - Keep controllers clean
7. **Always scope queries** - Load resources through user's accessible scope

These patterns scale from small teams to large enterprises, support multiple accounts per person, and provide clear separation of concerns between authentication and authorization.
