import { createResource, For, createSignal } from "solid-js";
import { useParams } from "@solidjs/router";
import { supabase } from "../lib/supabase";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { CheckCircle2, Circle, Plus, User } from "lucide-solid";

export default function ProjectDetail() {
  const params = useParams();
  const [newTask, setNewTask] = createSignal("");

  const [data, { refetch }] = createResource(async () => {
    const [projectRes, tasksRes] = await Promise.all([
      supabase.from("projects").select("*").eq("id", params.id).single(),
      supabase
        .from("tasks")
        .select("*")
        .eq("project_id", params.id)
        .order("created_at"),
    ]);
    return { project: projectRes.data, tasks: tasksRes.data };
  });

  const handleAddTask = async (e) => {
    e.preventDefault();
    if (!newTask()) return;

    await supabase
      .from("tasks")
      .insert([{ title: newTask(), project_id: params.id }]);
    setNewTask("");
    refetch();
  };

  const toggleStatus = async (task) => {
    const status = task.status === "completed" ? "todo" : "completed";
    // Optimistic update could go here, but simple await for now
    await supabase.from("tasks").update({ status }).eq("id", task.id);
    refetch();
  };

  return (
    <div class="max-w-4xl mx-auto">
      <div class="mb-8">
        <div class="flex items-center gap-3 mb-2">
          <h1 class="text-3xl font-bold text-slate-900">
            {data()?.project?.name}
          </h1>
          <Badge variant="blue">{data()?.project?.enforcement_mode}</Badge>
        </div>
        <p class="text-slate-500">{data()?.project?.description}</p>
      </div>

      <Card class="overflow-hidden">
        <div class="p-4 bg-slate-50 border-b border-slate-200 flex justify-between items-center">
          <h3 class="font-semibold text-slate-700">Tasks</h3>
          <span class="text-xs text-slate-500">
            {data()?.tasks?.filter((t) => t.status === "completed").length} /{" "}
            {data()?.tasks?.length} completed
          </span>
        </div>

        <div class="divide-y divide-slate-100">
          <For each={data()?.tasks}>
            {(task) => (
              <div class="p-4 hover:bg-slate-50 transition flex items-center gap-4 group">
                <button
                  onClick={() => toggleStatus(task)}
                  class={`flex-shrink-0 transition-colors ${
                    task.status === "completed"
                      ? "text-emerald-500"
                      : "text-slate-300 hover:text-slate-400"
                  }`}
                >
                  {task.status === "completed" ? <CheckCircle2 /> : <Circle />}
                </button>

                <div class="flex-1">
                  <p
                    class={`text-sm font-medium transition-all ${
                      task.status === "completed"
                        ? "text-slate-400 line-through"
                        : "text-slate-700"
                    }`}
                  >
                    {task.title}
                  </p>
                  <div class="flex gap-2 mt-1">
                    <span class="text-[10px] bg-slate-100 text-slate-500 px-1.5 py-0.5 rounded flex items-center gap-1">
                      <User size={10} /> {task.owner_role_id.split("-")[0]}...
                    </span>
                  </div>
                </div>

                <Badge
                  variant={
                    task.enforcement_mode === "PUBLIC" ? "warning" : "default"
                  }
                  class="text-[10px]"
                >
                  {task.enforcement_mode}
                </Badge>
              </div>
            )}
          </For>

          <form onSubmit={handleAddTask} class="p-4 bg-slate-50/50">
            <div class="flex gap-2">
              <input
                type="text"
                value={newTask()}
                onInput={(e) => setNewTask(e.target.value)}
                placeholder="Add a new task..."
                class="flex-1 bg-white border border-slate-300 text-sm rounded-lg px-3 py-2 outline-none focus:border-indigo-500"
              />
              <button
                type="submit"
                class="bg-indigo-600 hover:bg-indigo-700 text-white p-2 rounded-lg"
              >
                <Plus size={18} />
              </button>
            </div>
          </form>
        </div>
      </Card>
    </div>
  );
}
