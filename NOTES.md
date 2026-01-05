Database Tables: Define your columns and data types (Schema).
RLS Policies: Write the security rules (Who can see/edit what).
SQL Functions/Triggers: Logic for internal automation (e.g., auto-creating profiles).
Edge Functions: Logic for external tasks (e.g., Emails, Stripe, 3rd party APIs).
Storage Buckets: Create the containers for your files.
Views: Define your read-only views (e.g., Student List).

supabase status
supabase stop
supabase start
supabase db reset

| Service              | Container name               | Command to view logs                        |
| -------------------- | ---------------------------- | ------------------------------------------- |
| API gateway (Kong)   | `supabase_kong_SupaMax`      | `docker logs -f supabase_kong_SupaMax`      |
| PostgREST (REST API) | `supabase_rest_SupaMax`      | `docker logs -f supabase_rest_SupaMax`      |
| Auth                 | `supabase_auth_SupaMax`      | `docker logs -f supabase_auth_SupaMax`      |
| Postgres DB          | `supabase_db_SupaMax`        | `docker logs -f supabase_db_SupaMax`        |
| Realtime             | `supabase_realtime_SupaMax`  | `docker logs -f supabase_realtime_SupaMax`  |
| Storage API          | `supabase_storage_SupaMax`   | `docker logs -f supabase_storage_SupaMax`   |
| Studio (web UI)      | `supabase_studio_SupaMax`    | `docker logs -f supabase_studio_SupaMax`    |
| Analytics / Logflare | `supabase_analytics_SupaMax` | `docker logs -f supabase_analytics_SupaMax` |
| Vector / search      | `supabase_vector_SupaMax`    | `docker logs -f supabase_vector_SupaMax`    |
| Mail / SMTP          | `supabase_inbucket_SupaMax`  | `docker logs -f supabase_inbucket_SupaMax`  |
