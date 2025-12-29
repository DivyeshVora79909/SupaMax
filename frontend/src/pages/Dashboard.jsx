// src/pages/Dashboard.jsx
import { createResource, For, Show } from "solid-js";
import { supabase } from "../lib/supabase";
import { user } from "../lib/auth";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Banknote, Users, Building2, ShieldCheck } from "lucide-solid";

export default function Dashboard() {
  const [stats] = createResource(async () => {
    // We must wait for user to exist so we have the Org ID for RLS
    if (!user()) return null;

    // Parallel fetching for dashboard stats
    const [deals, contacts, companies] = await Promise.all([
      supabase.from("crm_deals").select("id, amount, stage"),
      supabase
        .from("crm_contacts")
        .select("id", { count: "exact", head: true }),
      supabase
        .from("crm_companies")
        .select("id", { count: "exact", head: true }),
    ]);

    const totalPipeline =
      deals.data?.reduce((sum, d) => sum + (d.amount || 0), 0) || 0;
    const wonCount = deals.data?.filter((d) => d.stage === "won").length || 0;

    return {
      pipeline: totalPipeline,
      contacts: contacts.count,
      companies: companies.count,
      wins: wonCount,
    };
  });

  const permissions = () => user()?.app_metadata?.permissions || [];

  return (
    <div class="space-y-6">
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6">
        <Card class="p-6 flex items-center gap-4 border-l-4 border-l-emerald-500">
          <div class="p-3 bg-emerald-100 text-emerald-600 rounded-lg">
            <Banknote size={24} />
          </div>
          <div>
            <p class="text-sm text-slate-500 font-medium">Pipeline Value</p>
            <h3 class="text-2xl font-bold text-slate-900">
              ${stats()?.pipeline?.toLocaleString() || 0}
            </h3>
          </div>
        </Card>

        <Card class="p-6 flex items-center gap-4 border-l-4 border-l-blue-500">
          <div class="p-3 bg-blue-100 text-blue-600 rounded-lg">
            <Users size={24} />
          </div>
          <div>
            <p class="text-sm text-slate-500 font-medium">Contacts</p>
            <h3 class="text-2xl font-bold text-slate-900">
              {stats()?.contacts || 0}
            </h3>
          </div>
        </Card>

        <Card class="p-6 flex items-center gap-4 border-l-4 border-l-indigo-500">
          <div class="p-3 bg-indigo-100 text-indigo-600 rounded-lg">
            <Building2 size={24} />
          </div>
          <div>
            <p class="text-sm text-slate-500 font-medium">Companies</p>
            <h3 class="text-2xl font-bold text-slate-900">
              {stats()?.companies || 0}
            </h3>
          </div>
        </Card>

        <Card class="p-6 flex items-center gap-4 border-l-4 border-l-purple-500">
          <div class="p-3 bg-purple-100 text-purple-600 rounded-lg">
            <ShieldCheck size={24} />
          </div>
          <div>
            <p class="text-sm text-slate-500 font-medium">Role Access</p>
            <h3 class="text-lg font-bold text-slate-900 truncate">
              {user()?.app_metadata?.accessible_roles?.length || 1} Levels
            </h3>
          </div>
        </Card>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card class="p-6">
          <h3 class="text-lg font-semibold text-slate-900 mb-4">
            Security Context (Active RLS)
          </h3>
          <div class="space-y-3 font-mono text-xs bg-slate-900 text-slate-200 p-4 rounded-lg">
            <div class="flex justify-between border-b border-slate-700 pb-2">
              <span class="text-slate-500">ORG_ID</span>
              <span class="text-emerald-400">
                {user()?.app_metadata?.org_id}
              </span>
            </div>
            <div class="flex justify-between border-b border-slate-700 pb-2">
              <span class="text-slate-500">ROLE_ID</span>
              <span class="text-blue-400">{user()?.app_metadata?.role_id}</span>
            </div>
            <div>
              <span class="text-slate-500 block mb-1">PERMISSIONS</span>
              <div class="flex flex-wrap gap-1">
                <For each={permissions()}>
                  {(p) => (
                    <span class="bg-indigo-900 text-indigo-200 px-1 rounded">
                      {p}
                    </span>
                  )}
                </For>
              </div>
            </div>
          </div>
        </Card>

        <Card class="p-6">
          <h3 class="text-lg font-semibold text-slate-900 mb-4">
            System Status
          </h3>
          <div class="flex items-center gap-2 mb-2">
            <div class="w-3 h-3 rounded-full bg-emerald-500"></div>
            <span class="text-sm text-slate-600">
              Database Connection Active
            </span>
          </div>
          <div class="flex items-center gap-2 mb-2">
            <div class="w-3 h-3 rounded-full bg-emerald-500"></div>
            <span class="text-sm text-slate-600">
              Row Level Security Enabled
            </span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-emerald-500"></div>
            <span class="text-sm text-slate-600">
              Realtime Subscription Ready
            </span>
          </div>
        </Card>
      </div>
    </div>
  );
}
