import { createResource, For, createSignal, Show } from "solid-js";
import { supabase } from "../../lib/supabase";
import { Badge } from "../../components/ui/Badge";
import {
  Plus,
  GripVertical,
  DollarSign,
  X,
  MessageSquare,
  Phone,
  Calendar,
} from "lucide-solid";
import { hasPermission } from "../../lib/auth";

const STAGES = ["lead", "qualified", "proposal", "negotiation", "won", "lost"];

export default function Deals() {
  const [activeDeal, setActiveDeal] = createSignal(null);

  // Fetch Deals
  const [data, { refetch }] = createResource(async () => {
    const { data } = await supabase
      .from("crm_deals")
      .select("*, crm_companies(name)")
      .order("created_at", { ascending: false });
    return data || [];
  });

  // Fetch Activities for Active Deal
  const [activities, { refetch: refetchActivities }] = createResource(
    activeDeal,
    async (deal) => {
      if (!deal) return [];
      const { data } = await supabase
        .from("crm_activities")
        .select("*")
        .eq("deal_id", deal.id)
        .order("created_at", { ascending: false });
      return data || [];
    }
  );

  // Create Activity
  const addActivity = async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    const summary = formData.get("summary");
    const type = formData.get("type");

    await supabase.from("crm_activities").insert({
      deal_id: activeDeal().id,
      type,
      summary,
    });
    e.target.reset();
    refetchActivities();
  };

  const createDeal = async () => {
    const title = prompt("Deal Title:");
    if (!title) return;
    const amount = prompt("Amount ($):");
    await supabase
      .from("crm_deals")
      .insert([{ title, amount: parseFloat(amount || 0), stage: "lead" }]);
    refetch();
  };

  // ... (Keep moveStage logic from previous snippet) ...
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
    <div class="h-full flex flex-col relative">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold text-slate-900">Deals Pipeline</h1>
          <p class="text-slate-500">Manage opportunities</p>
        </div>
        <Show when={hasPermission("crm_deals.write")}>
          <button
            onClick={createDeal}
            class="bg-indigo-600 text-white px-4 py-2 rounded-lg text-sm font-medium flex items-center gap-2"
          >
            <Plus size={16} /> New Deal
          </button>
        </Show>
      </div>

      {/* Kanban Board */}
      <div class="flex-1 overflow-x-auto pb-4">
        <div class="flex gap-4 h-full min-w-max">
          <For each={STAGES}>
            {(stage) => (
              <div class="w-80 flex flex-col h-full bg-slate-100 rounded-xl border border-slate-200">
                <div class="p-3 border-b border-slate-200 bg-slate-100 rounded-t-xl sticky top-0 font-bold capitalize text-slate-700">
                  {stage}
                </div>
                <div class="p-2 flex-1 overflow-y-auto space-y-2">
                  <For each={data()?.filter((d) => d.stage === stage)}>
                    {(deal) => (
                      <div
                        onClick={() => setActiveDeal(deal)}
                        class="bg-white p-3 rounded-lg border border-slate-200 shadow-sm hover:shadow-md cursor-pointer transition"
                      >
                        <div class="flex justify-between mb-2">
                          <h4 class="font-semibold text-slate-800 text-sm">
                            {deal.title}
                          </h4>
                          <GripVertical size={14} class="text-slate-300" />
                        </div>
                        <div class="text-emerald-600 font-bold text-sm mb-2 flex items-center">
                          <DollarSign size={12} />{" "}
                          {deal.amount?.toLocaleString()}
                        </div>
                        <div class="flex gap-2">
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              moveStage(deal.id, deal.stage, "prev");
                            }}
                            disabled={stage === "lead"}
                            class="text-xs bg-slate-50 px-2 py-1 rounded"
                          >
                            ←
                          </button>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              moveStage(deal.id, deal.stage, "next");
                            }}
                            disabled={stage === "won"}
                            class="text-xs bg-indigo-50 text-indigo-600 px-2 py-1 rounded"
                          >
                            →
                          </button>
                        </div>
                      </div>
                    )}
                  </For>
                </div>
              </div>
            )}
          </For>
        </div>
      </div>

      {/* ACTIVITY DRAWER (Overlay) */}
      <Show when={activeDeal()}>
        <div class="absolute inset-y-0 right-0 w-96 bg-white shadow-2xl border-l border-slate-200 z-50 flex flex-col transform transition-transform">
          <div class="p-4 border-b border-slate-100 flex justify-between items-center bg-slate-50">
            <div>
              <h3 class="font-bold text-slate-800">{activeDeal().title}</h3>
              <p class="text-xs text-slate-500">Activity Log</p>
            </div>
            <button
              onClick={() => setActiveDeal(null)}
              class="text-slate-400 hover:text-slate-700"
            >
              <X size={20} />
            </button>
          </div>

          {/* List Activities */}
          <div class="flex-1 overflow-y-auto p-4 space-y-4 bg-slate-50/50">
            <For
              each={activities()}
              fallback={
                <p class="text-center text-sm text-slate-400 py-4">
                  No activities yet.
                </p>
              }
            >
              {(log) => (
                <div class="flex gap-3 text-sm">
                  <div
                    class={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${
                      log.type === "call"
                        ? "bg-blue-100 text-blue-600"
                        : "bg-amber-100 text-amber-600"
                    }`}
                  >
                    {log.type === "call" ? (
                      <Phone size={14} />
                    ) : (
                      <MessageSquare size={14} />
                    )}
                  </div>
                  <div>
                    <p class="text-slate-800">{log.summary}</p>
                    <p class="text-[10px] text-slate-400">
                      {new Date(log.created_at).toLocaleString()}
                    </p>
                  </div>
                </div>
              )}
            </For>
          </div>

          {/* Add Activity Form */}
          <form
            onSubmit={addActivity}
            class="p-4 border-t border-slate-200 bg-white"
          >
            <select
              name="type"
              class="w-full mb-2 text-sm border p-2 rounded bg-slate-50"
            >
              <option value="note">Note</option>
              <option value="call">Call</option>
              <option value="email">Email</option>
              <option value="meeting">Meeting</option>
            </select>
            <textarea
              name="summary"
              required
              placeholder="Log a note..."
              class="w-full text-sm border p-2 rounded h-20 bg-slate-50 mb-2 focus:ring-2 focus:ring-indigo-500 outline-none"
            ></textarea>
            <button
              type="submit"
              class="w-full bg-indigo-600 text-white py-2 rounded text-sm font-medium"
            >
              Log Activity
            </button>
          </form>
        </div>
      </Show>
    </div>
  );
}
