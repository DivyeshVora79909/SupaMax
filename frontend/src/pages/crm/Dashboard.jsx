import { createResource, Show } from "solid-js";
import { supabase } from "../lib/supabase";
import { Card } from "../components/ui/Card";
import { Banknote, Users, Building2, TrendingUp } from "lucide-solid";

export default function Dashboard() {
  const [metrics] = createResource(async () => {
    // Parallel fetching for dashboard stats
    const [deals, contacts, companies] = await Promise.all([
      supabase.from("crm_deals").select("amount, stage"),
      supabase.from("crm_contacts").select("id", { count: "exact" }),
      supabase.from("crm_companies").select("id", { count: "exact" }),
    ]);

    const totalPipeline =
      deals.data?.reduce((sum, d) => sum + (d.amount || 0), 0) || 0;
    const wonDeals = deals.data?.filter((d) => d.stage === "won").length || 0;

    return {
      contacts: contacts.count,
      companies: companies.count,
      pipelineValue: totalPipeline,
      dealsCount: deals.data?.length || 0,
      wonDeals,
    };
  });

  const StatCard = (props) => (
    <Card class="p-6 relative overflow-hidden group">
      <div
        class={`absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity ${props.color}`}
      >
        {props.iconBig}
      </div>
      <div class="relative z-10">
        <div
          class={`w-12 h-12 rounded-lg flex items-center justify-center mb-4 ${props.bg} ${props.textColor}`}
        >
          {props.icon}
        </div>
        <p class="text-sm font-medium text-slate-500">{props.label}</p>
        <h3 class="text-2xl font-bold text-slate-900 mt-1">{props.value}</h3>
      </div>
    </Card>
  );

  return (
    <div class="space-y-8">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">Dashboard</h1>
        <p class="text-slate-500">
          Overview of your organization's performance
        </p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard
          label="Pipeline Value"
          value={`$${metrics()?.pipelineValue?.toLocaleString() || "0"}`}
          icon={<Banknote size={24} />}
          iconBig={<Banknote size={96} />}
          bg="bg-emerald-100"
          textColor="text-emerald-600"
          color="text-emerald-500"
        />
        <StatCard
          label="Active Deals"
          value={metrics()?.dealsCount || 0}
          icon={<TrendingUp size={24} />}
          iconBig={<TrendingUp size={96} />}
          bg="bg-blue-100"
          textColor="text-blue-600"
          color="text-blue-500"
        />
        <StatCard
          label="Total Contacts"
          value={metrics()?.contacts || 0}
          icon={<Users size={24} />}
          iconBig={<Users size={96} />}
          bg="bg-indigo-100"
          textColor="text-indigo-600"
          color="text-indigo-500"
        />
        <StatCard
          label="Companies"
          value={metrics()?.companies || 0}
          icon={<Building2 size={24} />}
          iconBig={<Building2 size={96} />}
          bg="bg-amber-100"
          textColor="text-amber-600"
          color="text-amber-500"
        />
      </div>

      {/* RLS Info Section */}
      <div class="bg-indigo-900 rounded-2xl p-8 text-white relative overflow-hidden">
        <div class="relative z-10 max-w-2xl">
          <h3 class="text-2xl font-bold mb-2">Secure Multi-Tenancy Active</h3>
          <p class="text-indigo-200 mb-6">
            You are currently viewing data scoped to your Organization via Row
            Level Security. Your Role Hierarchy determines if you can see data
            owned by others.
          </p>
          <div class="flex gap-4">
            <div class="bg-indigo-800/50 backdrop-blur px-4 py-2 rounded-lg border border-indigo-700">
              <span class="text-xs text-indigo-300 uppercase block">
                Security Mode
              </span>
              <span class="font-mono font-bold">RBAC + HIERARCHY</span>
            </div>
          </div>
        </div>

        {/* Decorative Circles */}
        <div class="absolute -top-24 -right-24 w-64 h-64 bg-indigo-500 rounded-full blur-3xl opacity-20"></div>
        <div class="absolute -bottom-24 -right-0 w-64 h-64 bg-blue-500 rounded-full blur-3xl opacity-20"></div>
      </div>
    </div>
  );
}
