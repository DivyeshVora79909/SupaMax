import { A, useLocation, useNavigate } from "@solidjs/router";
import {
  LayoutDashboard,
  FolderKanban,
  Users,
  Settings,
  LogOut,
  ShieldAlert,
} from "lucide-solid";
import { user, session } from "../lib/auth";
import { supabase } from "../lib/supabase";
import { Show } from "solid-js";

export default function DashboardLayout(props) {
  const location = useLocation();
  const navigate = useNavigate();

  const activeClass = "bg-slate-800 text-white";
  const inactiveClass = "text-slate-400 hover:text-white hover:bg-slate-800/50";

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate("/login");
  };

  return (
    <div class="flex h-screen w-full bg-slate-50">
      {/* Sidebar */}
      <aside class="w-64 flex-shrink-0 bg-slate-900 flex flex-col border-r border-slate-800">
        <div class="h-16 flex items-center px-6 border-b border-slate-800">
          <div class="flex items-center gap-2 text-indigo-500">
            <ShieldAlert size={24} />
            <span class="text-xl font-bold text-white tracking-tight">
              V42 Secure
            </span>
          </div>
        </div>

        <nav class="flex-1 px-4 py-6 space-y-1">
          <A
            href="/"
            class={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
              location.pathname === "/" ? activeClass : inactiveClass
            }`}
          >
            <LayoutDashboard size={18} />
            Overview
          </A>
          <A
            href="/projects"
            class={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
              location.pathname.includes("/projects")
                ? activeClass
                : inactiveClass
            }`}
          >
            <FolderKanban size={18} />
            Projects
          </A>
          <A
            href="/team"
            class={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
              location.pathname.includes("/team") ? activeClass : inactiveClass
            }`}
          >
            <Users size={18} />
            Organization & Roles
          </A>
          <A
            href="/settings"
            class={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
              location.pathname.includes("/settings")
                ? activeClass
                : inactiveClass
            }`}
          >
            <Settings size={18} />
            Settings
          </A>
        </nav>

        <div class="p-4 border-t border-slate-800">
          <div class="flex items-center gap-3 px-3 py-3 rounded-lg bg-slate-800/50">
            <div class="w-8 h-8 rounded-full bg-indigo-500 flex items-center justify-center text-white text-xs font-bold">
              {user()?.email?.substring(0, 2).toUpperCase()}
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-white truncate">
                {user()?.email}
              </p>
              <p class="text-xs text-slate-400 truncate">
                Org: {user()?.app_metadata?.org_id?.substring(0, 8)}...
              </p>
            </div>
            <button
              onClick={handleLogout}
              class="text-slate-400 hover:text-white"
              title="Logout"
            >
              <LogOut size={16} />
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content */}
      <main class="flex-1 overflow-y-auto">
        <header class="h-16 bg-white border-b border-slate-200 flex items-center justify-between px-8 sticky top-0 z-10">
          <h2 class="text-lg font-semibold text-slate-800 capitalize">
            {location.pathname === "/"
              ? "Overview"
              : location.pathname.split("/")[1]}
          </h2>

          <Show when={user()?.app_metadata?.role_id}>
            <span class="text-xs font-mono bg-slate-100 text-slate-600 px-2 py-1 rounded">
              Current Role ID: {user()?.app_metadata?.role_id}
            </span>
          </Show>
        </header>
        <div class="p-8 max-w-7xl mx-auto">{props.children}</div>
      </main>
    </div>
  );
}
