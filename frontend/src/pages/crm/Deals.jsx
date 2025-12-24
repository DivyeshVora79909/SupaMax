import { createResource, For, createSignal } from "solid-js";
import { supabase } from "../../lib/supabase";
import { Badge } from "../../components/ui/Badge";
import { Plus, GripVertical, DollarSign, Calendar } from "lucide-solid";

const STAGES = ["lead", "qualified", "proposal", "negotiation", "won", "lost"];

export default function Deals() {
  const [data, { refetch }] = createResource(async () => {
    const { data, error } = await supabase
      .from("crm_deals")
      .select("*, crm_companies(name), crm_contacts(first_name, last_name)")
      .order("created_at", { ascending: false });
    return data || [];
  });

  const createDeal = async () => {
    const title = prompt("Deal Title:");
    if (!title) return;
    const amount = prompt("Amount ($):");

    await supabase.from("crm_deals").insert([
      {
        title,
        amount: parseFloat(amount || 0),
        stage: "lead",
      },
    ]);
    refetch();
  };

  const moveStage = async (id, currentStage, direction) => {
    const currentIndex = STAGES.indexOf(currentStage);
    if (direction === "next" && currentIndex < STAGES.length - 1) {
      await supabase
        .from("crm_deals")
        .update({ stage: STAGES[currentIndex + 1] })
        .eq("id", id);
      refetch();
    }
    if (direction === "prev" && currentIndex > 0) {
      await supabase
        .from("crm_deals")
        .update({ stage: STAGES[currentIndex - 1] })
        .eq("id", id);
      refetch();
    }
  };

  return (
    <div class="h-full flex flex-col">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold text-slate-900">Deals Pipeline</h1>
          <p class="text-slate-500">Manage opportunities through stages</p>
        </div>
        <button
          onClick={createDeal}
          class="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm font-medium flex items-center gap-2 transition"
        >
          <Plus size={16} /> New Deal
        </button>
      </div>

      {/* Kanban Board Container */}
      <div class="flex-1 overflow-x-auto pb-4">
        <div class="flex gap-4 h-full min-w-max">
          <For each={STAGES}>
            {(stage) => (
              <div class="w-80 flex flex-col h-full bg-slate-100 rounded-xl border border-slate-200">
                {/* Column Header */}
                <div class="p-3 border-b border-slate-200 flex justify-between items-center bg-slate-100 rounded-t-xl sticky top-0">
                  <div class="flex items-center gap-2">
                    <span
                      class={`w-3 h-3 rounded-full ${
                        stage === "won"
                          ? "bg-emerald-500"
                          : stage === "lost"
                          ? "bg-red-500"
                          : "bg-indigo-500"
                      }`}
                    ></span>
                    <h3 class="font-bold text-slate-700 capitalize text-sm">
                      {stage}
                    </h3>
                  </div>
                  <span class="bg-slate-200 text-slate-600 text-xs px-2 py-0.5 rounded-full font-mono">
                    {data()?.filter((d) => d.stage === stage).length || 0}
                  </span>
                </div>

                {/* Cards Container */}
                <div class="p-2 flex-1 overflow-y-auto space-y-2 custom-scrollbar">
                  <For each={data()?.filter((d) => d.stage === stage)}>
                    {(deal) => (
                      <div class="bg-white p-3 rounded-lg border border-slate-200 shadow-sm hover:shadow-md transition group">
                        <div class="flex justify-between items-start mb-2">
                          <h4 class="font-semibold text-slate-800 text-sm">
                            {deal.title}
                          </h4>
                          <button class="text-slate-300 hover:text-slate-500 cursor-grab">
                            <GripVertical size={14} />
                          </button>
                        </div>

                        <div class="flex items-center gap-1 text-emerald-600 font-bold text-sm mb-2">
                          <DollarSign size={12} />
                          {deal.amount?.toLocaleString()}
                        </div>

                        <div class="space-y-1 mb-3">
                          {deal.crm_companies && (
                            <div class="text-xs text-slate-500 flex items-center gap-1">
                              <Building2 size={10} /> {deal.crm_companies.name}
                            </div>
                          )}
                          <div class="text-xs text-slate-400">
                            Owner: {deal.owner_role_id.substring(0, 8)}...
                          </div>
                        </div>

                        <div class="flex gap-1 mt-2 pt-2 border-t border-slate-50 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            onClick={() =>
                              moveStage(deal.id, deal.stage, "prev")
                            }
                            disabled={deal.stage === "lead"}
                            class="flex-1 bg-slate-50 hover:bg-slate-100 text-xs py-1 rounded text-slate-600 disabled:opacity-30"
                          >
                            ← Prev
                          </button>
                          <button
                            onClick={() =>
                              moveStage(deal.id, deal.stage, "next")
                            }
                            disabled={deal.stage === "lost"}
                            class="flex-1 bg-indigo-50 hover:bg-indigo-100 text-xs py-1 rounded text-indigo-600 font-medium disabled:opacity-30"
                          >
                            Next →
                          </button>
                        </div>
                      </div>
                    )}
                  </For>
                </div>

                {/* Column Footer Summary */}
                <div class="p-2 text-center text-xs text-slate-400 border-t border-slate-200">
                  Total: $
                  {data()
                    ?.filter((d) => d.stage === stage)
                    .reduce((a, b) => a + (b.amount || 0), 0)
                    .toLocaleString()}
                </div>
              </div>
            )}
          </For>
        </div>
      </div>
    </div>
  );
}
