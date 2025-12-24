import { createResource, For, Show } from "solid-js";
import { supabase } from "../lib/supabase";
import { A } from "@solidjs/router";
import { Card } from "../components/ui/Card";
import { Badge } from "../components/ui/Badge";
import { Plus, Folder, Globe, Shield, Lock } from "lucide-solid";

export default function Projects() {
  const [projects, { refetch }] = createResource(async () => {
    const { data } = await supabase
      .from("projects")
      .select("*")
      .order("created_at", { ascending: false });
    return data;
  });

  const createProject = async () => {
    const name = prompt("Project Name:");
    if (!name) return;

    // Org ID is handled by backend trigger "set_rls_metadata"
    await supabase.from("projects").insert([{ name }]);
    refetch();
  };

  const getModeIcon = (mode) => {
    switch (mode) {
      case "PUBLIC":
        return <Globe size={14} />;
      case "CONTROLLED":
        return <Shield size={14} />;
      default:
        return <Lock size={14} />;
    }
  };

  return (
    <div>
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold text-slate-900">Projects</h1>
          <p class="text-slate-500">Manage your secure resources</p>
        </div>
        <button
          onClick={createProject}
          class="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm font-medium flex items-center gap-2 transition"
        >
          <Plus size={16} /> New Project
        </button>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <For
          each={projects()}
          fallback={
            <div class="col-span-3 text-center py-12 text-slate-400">
              No projects found
            </div>
          }
        >
          {(project) => (
            <A href={`/projects/${project.id}`}>
              <Card class="p-6 hover:border-indigo-300 hover:shadow-md transition group cursor-pointer h-full flex flex-col">
                <div class="flex justify-between items-start mb-4">
                  <div class="p-2 bg-slate-100 text-slate-600 rounded-lg group-hover:bg-indigo-50 group-hover:text-indigo-600 transition">
                    <Folder size={20} />
                  </div>
                  <Badge variant="default" class="flex items-center gap-1">
                    {getModeIcon(project.enforcement_mode)}
                    {project.enforcement_mode}
                  </Badge>
                </div>

                <h3 class="text-lg font-bold text-slate-900 mb-2 group-hover:text-indigo-700 transition">
                  {project.name}
                </h3>
                <p class="text-sm text-slate-500 flex-1">
                  {project.description || "No description provided."}
                </p>

                <div class="mt-4 pt-4 border-t border-slate-100 flex items-center justify-between text-xs text-slate-400">
                  <span>
                    Created {new Date(project.created_at).toLocaleDateString()}
                  </span>
                  <span class="text-indigo-600 font-medium opacity-0 group-hover:opacity-100 transition">
                    View Details →
                  </span>
                </div>
              </Card>
            </A>
          )}
        </For>
      </div>
    </div>
  );
}
