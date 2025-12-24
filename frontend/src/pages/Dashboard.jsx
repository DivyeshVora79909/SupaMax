import { createResource, For } from "solid-js";
import { supabase } from "../lib/supabase";
import { user } from "../lib/auth";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Folder, CheckCircle2, Lock } from "lucide-solid";

export default function Dashboard() {
  const [stats] = createResource(async () => {
    // Parallel fetching for dashboard stats
    const [projects, tasks] = await Promise.all([
      supabase.from("projects").select("id", { count: "exact" }),
      supabase.from("tasks").select("id", { count: "exact" }),
    ]);
    return {
      projects: projects.count,
      tasks: tasks.count,
    };
  });

  const permissions = () => user()?.app_metadata?.permissions || [];

  return (
    <div class="space-y-6">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <Card class="p-6 flex items-center gap-4">
          <div class="p-3 bg-blue-100 text-blue-600 rounded-lg">
            <Folder size={24} />
          </div>
          <div>
            <p class="text-sm text-slate-500 font-medium">Total Projects</p>
            <h3 class="text-2xl font-bold text-slate-900">
              {stats()?.projects || 0}
            </h3>
          </div>
        </Card>

        <Card class="p-6 flex items-center gap-4">
          <div class="p-3 bg-emerald-100 text-emerald-600 rounded-lg">
            <CheckCircle2 size={24} />
          </div>
          <div>
            <p class="text-sm text-slate-500 font-medium">Total Tasks</p>
            <h3 class="text-2xl font-bold text-slate-900">
              {stats()?.tasks || 0}
            </h3>
          </div>
        </Card>

        <Card class="p-6 flex items-center gap-4">
          <div class="p-3 bg-indigo-100 text-indigo-600 rounded-lg">
            <Lock size={24} />
          </div>
          <div>
            <p class="text-sm text-slate-500 font-medium">Access Level</p>
            <h3 class="text-2xl font-bold text-slate-900">Pro Plan</h3>
          </div>
        </Card>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card class="p-6">
          <h3 class="text-lg font-semibold text-slate-900 mb-4">
            Your Active Permissions
          </h3>
          <p class="text-sm text-slate-500 mb-4">
            These are derived from your Role via the Auth Hook.
          </p>
          <div class="flex flex-wrap gap-2">
            <For
              each={permissions()}
              fallback={
                <span class="text-slate-400 text-sm">
                  No explicit permissions
                </span>
              }
            >
              {(perm) => (
                <Badge variant="purple" class="font-mono">
                  {perm}
                </Badge>
              )}
            </For>
          </div>
        </Card>

        <Card class="p-6">
          <h3 class="text-lg font-semibold text-slate-900 mb-4">
            Hierarchy Context
          </h3>
          <div class="space-y-2">
            <div class="flex justify-between text-sm border-b pb-2">
              <span class="text-slate-500">Org ID</span>
              <span class="font-mono text-slate-700">
                {user()?.app_metadata?.org_id}
              </span>
            </div>
            <div class="flex justify-between text-sm border-b pb-2">
              <span class="text-slate-500">Role ID</span>
              <span class="font-mono text-slate-700">
                {user()?.app_metadata?.role_id}
              </span>
            </div>
            <div class="flex justify-between text-sm">
              <span class="text-slate-500">Accessible Child Roles</span>
              <span class="font-mono text-slate-700">
                {user()?.app_metadata?.accessible_roles?.length || 0} roles
              </span>
            </div>
          </div>
        </Card>
      </div>
    </div>
  );
}
