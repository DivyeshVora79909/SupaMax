import { createResource, For, createSignal, Show } from "solid-js";
import { supabase } from "../lib/supabase";
import { user } from "../lib/auth"; // Access current user for UI logic
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Users, Shield, AlertTriangle, Check } from "lucide-solid";

export default function Team() {
  const [errorMsg, setErrorMsg] = createSignal("");
  const [successMsg, setSuccessMsg] = createSignal("");

  const [data, { refetch }] = createResource(async () => {
    // 1. Fetch Profiles
    const { data: profiles } = await supabase
      .from("profiles")
      .select("*, roles(name)"); // Join roles to show names

    // 2. Fetch Roles available in the Org
    const { data: roles } = await supabase
      .from("roles")
      .select("*")
      .eq("is_system", false); // Only custom roles usually, but fetch all if needed

    // 3. Fetch Hierarchy
    const { data: hierarchy } = await supabase
      .from("role_hierarchy")
      .select("*");

    return { profiles, roles, hierarchy };
  });

  // --- ACTION: Change Member Role ---
  // This triggers the Backend Trigger: enforce_role_assignment_subset
  const handleRoleChange = async (userId, newRoleId) => {
    setErrorMsg("");
    setSuccessMsg("");

    const { error } = await supabase
      .from("profiles")
      .update({ role_id: newRoleId })
      .eq("id", userId);

    if (error) {
      // Backend Security Trigger Message will appear here
      setErrorMsg(error.message);
    } else {
      setSuccessMsg("Role updated successfully.");
      refetch();
    }
  };

  return (
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">
          Organization Management
        </h1>
        <p class="text-slate-500">Manage members and role hierarchy</p>
      </div>

      {/* Security Feedback Area */}
      <Show when={errorMsg()}>
        <div class="p-4 bg-red-50 border border-red-200 text-red-700 rounded-lg flex items-center gap-2">
          <AlertTriangle size={18} />
          <span class="font-medium">Security Blocked:</span> {errorMsg()}
        </div>
      </Show>
      <Show when={successMsg()}>
        <div class="p-4 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-lg flex items-center gap-2">
          <Check size={18} />
          {successMsg()}
        </div>
      </Show>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* MEMBER MANAGEMENT */}
        <div class="lg:col-span-2 space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <Users size={18} class="text-indigo-600" />
            Team Members
          </h2>
          <Card class="divide-y divide-slate-100">
            <For each={data()?.profiles}>
              {(member) => (
                <div class="p-4 flex items-center justify-between">
                  <div class="flex items-center gap-4">
                    <div class="w-10 h-10 bg-slate-200 rounded-full flex items-center justify-center font-bold text-slate-500">
                      {member.full_name?.[0]}
                    </div>
                    <div>
                      <p class="font-medium text-slate-900">
                        {member.full_name}
                        {member.id === user()?.id && (
                          <span class="text-xs text-slate-400 ml-2">(You)</span>
                        )}
                      </p>
                      <p class="text-xs text-slate-500">{member.roles?.name}</p>
                    </div>
                  </div>

                  {/* Role Selector */}
                  <div class="flex items-center gap-2">
                    <select
                      class="text-sm border border-slate-300 rounded px-2 py-1 bg-white"
                      value={member.role_id}
                      onChange={(e) =>
                        handleRoleChange(member.id, e.target.value)
                      }
                      // Disable changing your own role to prevent locking yourself out (optional UI safety)
                      disabled={member.id === user()?.id}
                    >
                      <For each={data()?.roles}>
                        {(r) => <option value={r.id}>{r.name}</option>}
                      </For>
                    </select>
                  </div>
                </div>
              )}
            </For>
          </Card>
        </div>

        {/* ROLE HIERARCHY */}
        <div class="space-y-4">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <Shield size={18} class="text-emerald-600" />
            Role Hierarchy
          </h2>
          <Card class="p-4 bg-slate-50 border-dashed">
            <p class="text-xs text-slate-500 mb-4">
              Define who reports to whom. Changes here affect data visibility
              immediately via Closure Tables.
            </p>
            <div class="space-y-2">
              <For
                each={data()?.hierarchy}
                fallback={
                  <div class="text-sm text-slate-400">Flat Organization</div>
                }
              >
                {(rule) => {
                  const parentName =
                    data()?.roles?.find((r) => r.id === rule.parent_role_id)
                      ?.name || "Unknown";
                  const childName =
                    data()?.roles?.find((r) => r.id === rule.child_role_id)
                      ?.name || "Unknown";
                  return (
                    <div class="flex items-center justify-between text-sm bg-white p-2 rounded border border-slate-200 shadow-sm">
                      <span class="font-bold text-indigo-700">
                        {parentName}
                      </span>
                      <span class="text-slate-400 text-xs">manages</span>
                      <span class="font-medium text-slate-700">
                        {childName}
                      </span>
                    </div>
                  );
                }}
              </For>
            </div>

            {/* Note: Adding hierarchy editing requires another UI form, 
                omitted here to keep it concise, but the structure is ready. */}
          </Card>
        </div>
      </div>
    </div>
  );
}
