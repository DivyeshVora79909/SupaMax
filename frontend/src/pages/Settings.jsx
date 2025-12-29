import { createResource, createSignal, Show } from "solid-js";
import { supabase } from "../lib/supabase";
import { user } from "../lib/auth";
import { Card } from "../components/ui/Card";
import { Loader2, Save, User, Building } from "lucide-solid";

export default function Settings() {
  const [saving, setSaving] = createSignal(false);
  const [msg, setMsg] = createSignal("");

  const [profile, { refetch }] = createResource(async () => {
    const { data } = await supabase
      .from("profiles")
      .select("*, organizations(name, plan)")
      .eq("id", user()?.id)
      .single();
    return data;
  });

  const handleUpdate = async (e) => {
    e.preventDefault();
    setSaving(true);
    setMsg("");

    const formData = new FormData(e.target);
    const full_name = formData.get("full_name");

    const { error } = await supabase
      .from("profiles")
      .update({ full_name })
      .eq("id", user()?.id);

    if (error) setMsg("Error updating profile");
    else {
      setMsg("Profile updated successfully");
      refetch();
    }
    setSaving(false);
  };

  return (
    <div class="max-w-2xl mx-auto space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">Settings</h1>
        <p class="text-slate-500">Manage your account and preferences</p>
      </div>

      <Show when={profile()} fallback={<Loader2 class="animate-spin" />}>
        <Card class="p-6">
          <form onSubmit={handleUpdate} class="space-y-4">
            <div class="flex items-center gap-4 mb-6 pb-6 border-b border-slate-100">
              <div class="w-16 h-16 bg-indigo-100 text-indigo-600 rounded-full flex items-center justify-center text-xl font-bold">
                {profile()?.full_name?.[0] || "?"}
              </div>
              <div>
                <h3 class="font-bold text-slate-900">
                  {profile()?.organizations?.name}
                </h3>
                <span class="text-xs uppercase font-bold tracking-wider text-indigo-600 bg-indigo-50 px-2 py-1 rounded">
                  {profile()?.organizations?.plan} PLAN
                </span>
              </div>
            </div>

            <div class="grid grid-cols-1 gap-4">
              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1">
                  Full Name
                </label>
                <div class="relative">
                  <User
                    class="absolute left-3 top-2.5 text-slate-400"
                    size={16}
                  />
                  <input
                    name="full_name"
                    type="text"
                    value={profile()?.full_name || ""}
                    class="w-full pl-10 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-lg outline-none focus:border-indigo-500"
                  />
                </div>
              </div>

              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1">
                  Email (Read Only)
                </label>
                <input
                  disabled
                  type="text"
                  value={user()?.email}
                  class="w-full px-4 py-2 bg-slate-100 border border-slate-200 rounded-lg text-slate-500 cursor-not-allowed"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1">
                  Role ID
                </label>
                <code class="block w-full px-4 py-2 bg-slate-100 border border-slate-200 rounded-lg text-xs font-mono text-slate-600">
                  {profile()?.role_id}
                </code>
              </div>
            </div>

            <div class="pt-4 flex items-center justify-between">
              <span
                class={`text-sm ${
                  msg().includes("Error") ? "text-red-500" : "text-emerald-600"
                }`}
              >
                {msg()}
              </span>
              <button
                type="submit"
                disabled={saving()}
                class="bg-slate-900 hover:bg-slate-800 text-white px-4 py-2 rounded-lg font-medium flex items-center gap-2 disabled:opacity-50"
              >
                {saving() ? (
                  <Loader2 class="animate-spin" size={16} />
                ) : (
                  <Save size={16} />
                )}
                Save Changes
              </button>
            </div>
          </form>
        </Card>
      </Show>
    </div>
  );
}
