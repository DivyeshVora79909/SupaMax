// ==========================================
// 🔴 SUPABASE AUTH & STORAGE (Managed by System)
// ==========================================

TableGroup "Supabase_System_Auth" [color: #d35400] {
  "auth"."users"
  "auth"."identities"
  "auth"."sessions"
}

TableGroup "Supabase_System_Storage" [color: #2980b9] {
  "storage"."buckets"
  "storage"."objects"
}

// ------------------------------------------
// Auth Schema
// ------------------------------------------

Table "auth"."users" {
  id uuid [pk, note: "The central Supabase User ID"]
  email varchar
  encrypted_password varchar
  email_confirmed_at timestamp
  last_sign_in_at timestamp
  raw_user_meta_data jsonb
  created_at timestamp
  updated_at timestamp
  // Note: There are more internal columns, but these are the ones you care about
}

Table "auth"."identities" {
  id text [pk]
  user_id uuid
  provider text [note: "google, github, email"]
  identity_data jsonb
  created_at timestamp
}

Table "auth"."sessions" {
  id uuid [pk]
  user_id uuid
  created_at timestamp
}

// ------------------------------------------
// Storage Schema
// ------------------------------------------

Table "storage"."buckets" {
  id text [pk, note: "e.g. 'avatars', 'documents'"]
  name text
  public boolean
  file_size_limit bigint
  allowed_mime_types text[]
}

Table "storage"."objects" {
  id uuid [pk]
  bucket_id text
  name text [note: "File path/name"]
  owner uuid [note: "Links to auth.users.id"]
  metadata jsonb [note: "mimetype, size, cacheControl"]
  created_at timestamp
  updated_at timestamp
}

// ==========================================
// 🟢 YOUR MULTI-TENANT CRM (Public Schema)
// ==========================================

// Enums make the diagram cleaner and stricter
Enum app_role {
  admin
  member
  viewer
}

Enum deal_stage_status {
  open
  won
  lost
}

// ------------------------------------------
// Tenant & Access Control
// ------------------------------------------

TableGroup "App_Access_Control" [color: #27ae60] {
  tenants
  profiles
}

Table tenants {
  id uuid [pk, default: `gen_random_uuid()`]
  name text
  subscription_tier text [note: "free, pro, enterprise"]
  billing_status text
  settings jsonb [note: "Feature flags, UI themes"]
  created_at timestamptz [default: `now()`]
}

Table profiles {
  id uuid [pk, note: "1:1 Match with auth.users"]
  tenant_id uuid
  display_name text
  email text [note: "Synced from auth.users"]
  role app_role [default: "viewer"]
  avatar_object_id uuid
  created_at timestamptz
}

// ------------------------------------------
// Core CRM Data
// ------------------------------------------

TableGroup "App_Core_CRM" [color: #8e44ad] {
  accounts
  contacts
  deals
  deal_stages
}

Table accounts {
  id uuid [pk]
  tenant_id uuid
  name text
  website text
  industry text
  logo_object_id uuid
  created_at timestamptz
}

Table contacts {
  id uuid [pk]
  tenant_id uuid
  account_id uuid
  first_name text
  last_name text
  email text
  phone text
  position text
  created_at timestamptz
}

Table deal_stages {
  id uuid [pk]
  tenant_id uuid
  name text [note: "Lead, Negotiation, Contract"]
  sort_order int
}

Table deals {
  id uuid [pk]
  tenant_id uuid
  account_id uuid
  primary_contact_id uuid
  title text
  amount numeric(15, 2)
  currency char(3) [default: "USD"]
  stage_id uuid
  status deal_stage_status
  close_date date
  owner_id uuid [note: "Sales rep"]
  created_at timestamptz
}

// ------------------------------------------
// Operations & Activities
// ------------------------------------------

TableGroup "App_Operations" [color: #f39c12] {
  tasks
  task_statuses
  activities
  activity_types
  crm_attachments
}

Table task_statuses {
  id int [pk, increment]
  name text [note: "To Do, In Progress, Done"]
}

Table tasks {
  id uuid [pk]
  tenant_id uuid
  title text
  description text
  due_date date
  priority text
  
  status_id int
  assignee_id uuid
  created_by uuid
  
  // Relations
  account_id uuid
  contact_id uuid
  deal_id uuid
  
  created_at timestamptz
}

Table activity_types {
  id int [pk, increment]
  name text [note: "Call, Email, Meeting"]
  icon text
}

Table activities {
  id uuid [pk]
  tenant_id uuid
  
  type_id int
  actor_id uuid [note: "Who did it?"]
  occurred_at timestamptz
  
  content text [note: "Call notes, email body"]
  
  // Relations
  account_id uuid
  contact_id uuid
  deal_id uuid
}

// ------------------------------------------
// Bridge Table: App <-> Storage
// ------------------------------------------

Table crm_attachments {
  id uuid [pk]
  tenant_id uuid
  
  // Link to physical file
  storage_object_id uuid
  
  // Metadata
  file_name text
  file_size int
  uploaded_by uuid
  
  // Polymorphic Relations (Which entity owns this file?)
  deal_id uuid
  task_id uuid
  activity_id uuid
  
  created_at timestamptz
}

// ==========================================
// 🔗 RELATIONSHIPS (The Wiring)
// ==========================================

// 1. SYSTEM INTEGRATIONS (Auth & Storage)
Ref: "auth"."identities".user_id > "auth"."users".id [delete: cascade]
Ref: "auth"."sessions".user_id > "auth"."users".id [delete: cascade]
Ref: "storage"."objects".bucket_id > "storage"."buckets".id
Ref: "storage"."objects".owner > "auth"."users".id

// 2. AUTH -> PUBLIC (The critical security link)
Ref: profiles.id - "auth"."users".id [delete: cascade] // Profile auto-created via Triggers on Auth

// 3. STORAGE -> PUBLIC (File linking)
Ref: profiles.avatar_object_id - "storage"."objects".id
Ref: accounts.logo_object_id - "storage"."objects".id
Ref: crm_attachments.storage_object_id - "storage"."objects".id

// 4. TENANCY (Data Isolation)
Ref: profiles.tenant_id > tenants.id
Ref: accounts.tenant_id > tenants.id
Ref: contacts.tenant_id > tenants.id
Ref: deals.tenant_id > tenants.id
Ref: deal_stages.tenant_id > tenants.id
Ref: tasks.tenant_id > tenants.id
Ref: activities.tenant_id > tenants.id
Ref: crm_attachments.tenant_id > tenants.id

// 5. CRM HIERARCHY
Ref: contacts.account_id > accounts.id [delete: cascade]
Ref: deals.account_id > accounts.id [delete: cascade]
Ref: deals.primary_contact_id > contacts.id
Ref: deals.stage_id > deal_stages.id
Ref: deals.owner_id > profiles.id

// 6. ACTIVITIES & TASKS
Ref: activities.type_id > activity_types.id
Ref: activities.actor_id > profiles.id
Ref: activities.account_id > accounts.id
Ref: activities.contact_id > contacts.id
Ref: activities.deal_id > deals.id

Ref: tasks.status_id > task_statuses.id
Ref: tasks.assignee_id > profiles.id
Ref: tasks.created_by > profiles.id
Ref: tasks.account_id > accounts.id
Ref: tasks.contact_id > contacts.id
Ref: tasks.deal_id > deals.id

// 7. ATTACHMENTS (Polymorphic)
Ref: crm_attachments.uploaded_by > profiles.id
Ref: crm_attachments.deal_id > deals.id
Ref: crm_attachments.task_id > tasks.id
Ref: crm_attachments.activity_id > activities.id