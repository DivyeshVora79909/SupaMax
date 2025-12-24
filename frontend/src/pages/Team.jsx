import { createResource, For } from "solid-js";
import { supabase } from "../lib/supabase";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Users, GitCommit, Shield } from "lucide-solid";

export default function Team() {
  const [data] = createResource(async () => {
    // Parallel fetch of org structure
    const [roles, profiles, permissions] = await Promise.all([
      supabase.from("roles").select("*, role_permissions(permissions(code))"),
      supabase.from("profiles").select("*"),
      supabase.from("role_hierarchy").select("*"),
    ]);
    return {
      roles: roles.data,
      profiles: profiles.data,
      hierarchy: permissions.data,
    };
  });

  return (
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">
          Organization Structure
        </h1>
        <p class="text-slate-500">Visualize Roles, Hierarchy, and Members</p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Roles List */}
        <div class="space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <Shield size={18} class="text-indigo-600" />
            Roles & Permissions
          </h2>
          <For each={data()?.roles}>
            {(role) => (
              <Card class="p-4 border-l-4 border-l-indigo-500">
                <div class="flex justify-between items-start">
                  <div>
                    <h3 class="font-bold text-slate-800">{role.name}</h3>
                    <p class="text-xs text-slate-400 font-mono mb-2">
                      {role.id}
                    </p>
                    <p class="text-sm text-slate-600 mb-3">
                      {role.description}
                    </p>
                  </div>
                  <Badge>
                    {
                      data()?.profiles?.filter((p) => p.role_id === role.id)
                        .length
                    }{" "}
                    Members
                  </Badge>
                </div>

                <div class="flex flex-wrap gap-1 mt-2">
                  <For each={role.role_permissions}>
                    {(rp) => (
                      <span class="px-2 py-1 bg-indigo-50 text-indigo-700 text-[10px] font-mono rounded border border-indigo-100">
                        {rp.permissions.code}
                      </span>
                    )}
                  </For>
                  {role.role_permissions.length === 0 && (
                    <span class="text-xs text-slate-400 italic">
                      No explicit permissions
                    </span>
                  )}
                </div>
              </Card>
            )}
          </For>
        </div>

        {/* Members List */}
        <div class="space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <Users size={18} class="text-emerald-600" />
            Members
          </h2>
          <Card class="divide-y divide-slate-100">
            <For each={data()?.profiles}>
              {(profile) => (
                <div class="p-4 flex items-center gap-4">
                  <div class="w-10 h-10 bg-slate-200 rounded-full flex items-center justify-center text-slate-500 font-bold">
                    {profile.full_name ? profile.full_name[0] : "?"}
                  </div>
                  <div>
                    <p class="font-medium text-slate-900">
                      {profile.full_name || "Unnamed User"}
                    </p>
                    <p class="text-xs text-slate-500">
                      Role:{" "}
                      {data()?.roles?.find((r) => r.id === profile.role_id)
                        ?.name || "Unknown"}
                    </p>
                  </div>
                </div>
              )}
            </For>
          </Card>

          {/* Hierarchy Visualization (Simple List) */}
          <div class="mt-8">
            <h2 class="text-lg font-semibold flex items-center gap-2 mb-4">
              <GitCommit size={18} class="text-amber-600" />
              Hierarchy Rules
            </h2>
            <Card class="p-4 bg-slate-50">
              <For
                each={data()?.hierarchy}
                fallback={
                  <p class="text-sm text-slate-500">
                    No hierarchy defined (Flat structure)
                  </p>
                }
              >
                {(rule) => {
                  const parent = data()?.roles?.find(
                    (r) => r.id === rule.parent_role_id
                  )?.name;
                  const child = data()?.roles?.find(
                    (r) => r.id === rule.child_role_id
                  )?.name;
                  return (
                    <div class="flex items-center gap-2 text-sm text-slate-700 py-1">
                      <span class="font-bold">{parent}</span>
                      <span class="text-slate-400">→ manages →</span>
                      <span class="font-bold">{child}</span>
                    </div>
                  );
                }}
              </For>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
