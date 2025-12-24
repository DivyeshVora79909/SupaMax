import { createResource, For } from "solid-js";
import { supabase } from "../../lib/supabase";
import { Card } from "../../components/ui/Card";
import { Badge } from "../../components/ui/Badge";
import { Plus, Globe, Building2 } from "lucide-solid";

export default function Companies() {
  const [companies, { refetch }] = createResource(async () => {
    const { data } = await supabase
      .from("crm_companies")
      .select("*")
      .order("created_at", { ascending: false });
    return data || [];
  });

  const addCompany = async () => {
    const name = prompt("Company Name:");
    if (!name) return;
    const industry = prompt("Industry:");

    await supabase.from("crm_companies").insert([{ name, industry }]);
    refetch();
  };

  return (
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-2xl font-bold text-slate-900">Companies</h1>
          <p class="text-slate-500">B2B accounts and organizations</p>
        </div>
        <button
          onClick={addCompany}
          class="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm font-medium flex items-center gap-2"
        >
          <Plus size={16} /> Add Company
        </button>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <For each={companies()}>
          {(comp) => (
            <Card class="p-6 hover:shadow-md transition border-l-4 border-l-transparent hover:border-l-indigo-500 group">
              <div class="flex justify-between items-start mb-4">
                <div class="w-12 h-12 bg-slate-100 rounded-lg flex items-center justify-center text-slate-500 group-hover:bg-indigo-50 group-hover:text-indigo-600 transition">
                  <Building2 size={24} />
                </div>
                <Badge variant="default" class="text-[10px]">
                  {comp.enforcement_mode}
                </Badge>
              </div>

              <h3 class="text-lg font-bold text-slate-900 mb-1">{comp.name}</h3>
              <p class="text-sm text-slate-500 mb-4">
                {comp.industry || "Unknown Industry"}
              </p>

              <div class="pt-4 border-t border-slate-100 flex items-center gap-2 text-sm text-indigo-600">
                <Globe size={14} />
                <a href="#" class="hover:underline">
                  {comp.website || "No website"}
                </a>
              </div>
            </Card>
          )}
        </For>
      </div>
    </div>
  );
}
