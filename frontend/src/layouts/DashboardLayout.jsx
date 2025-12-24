import { A, useLocation, useNavigate } from "@solidjs/router";
import {
  LayoutDashboard,
  Building2,
  Users,
  Banknote,
  Settings,
  LogOut,
  ShieldAlert,
  Briefcase,
} from "lucide-solid";
import { user } from "../lib/auth";
import { supabase } from "../lib/supabase";
import { Show } from "solid-js";

export default function DashboardLayout(props) {
  const location = useLocation();
  const navigate = useNavigate();

  const activeClass = "bg-indigo-600 text-white shadow-lg shadow-indigo-500/30";
  const inactiveClass = "text-slate-400 hover:text-white hover:bg-slate-800/50";

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate("/login");
  };

  const NavItem = (p) => (
    <A
      href={p.href}
      class={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all ${
        location.pathname === p.href ||
        (p.href !== "/" && location.pathname.includes(p.href))
          ? activeClass
          : inactiveClass
      }`}
    >
      {p.icon}
      {p.label}
    </A>
  );

  return (
    <div class="flex h-screen w-full bg-slate-50 font-sans">
      {/* Sidebar */}
      <aside class="w-64 flex-shrink-0 bg-slate-900 flex flex-col border-r border-slate-800">
        <div class="h-16 flex items-center px-6 border-b border-slate-800 bg-slate-900">
          <div class="flex items-center gap-2 text-indigo-500">
            <ShieldAlert size={24} />
            <span class="text-xl font-bold text-white tracking-tight">
              Nexus CRM
            </span>
          </div>
        </div>

        <nav class="flex-1 px-4 py-6 space-y-1">
          <div class="px-3 mb-2 text-xs font-semibold text-slate-500 uppercase tracking-wider">
            Menu
          </div>
          <NavItem
            href="/"
            icon={<LayoutDashboard size={18} />}
            label="Overview"
          />
          <NavItem
            href="/deals"
            icon={<Banknote size={18} />}
            label="Deals Pipeline"
          />
          <NavItem
            href="/contacts"
            icon={<Users size={18} />}
            label="Contacts"
          />
          <NavItem
            href="/companies"
            icon={<Building2 size={18} />}
            label="Companies"
          />

          <div class="px-3 mt-8 mb-2 text-xs font-semibold text-slate-500 uppercase tracking-wider">
            System
          </div>
          <NavItem
            href="/team"
            icon={<Briefcase size={18} />}
            label="Organization"
          />
          <NavItem
            href="/settings"
            icon={<Settings size={18} />}
            label="Settings"
          />
        </nav>

        <div class="p-4 border-t border-slate-800 bg-slate-950">
          <div class="flex items-center gap-3 px-3 py-3 rounded-lg bg-slate-800/50 border border-slate-800">
            <div class="w-9 h-9 rounded-full bg-indigo-500 flex items-center justify-center text-white text-sm font-bold shadow-md">
              {user()?.email?.substring(0, 2).toUpperCase()}
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-white truncate">
                {user()?.user_metadata?.full_name || "User"}
              </p>
              <p class="text-xs text-slate-400 truncate">
                {user()?.app_metadata?.role_id?.split("-")[0] || "Member"}
              </p>
            </div>
            <button
              onClick={handleLogout}
              class="text-slate-400 hover:text-red-400 transition-colors"
              title="Logout"
            >
              <LogOut size={16} />
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content */}
      <main class="flex-1 overflow-hidden flex flex-col">
        <header class="h-16 bg-white border-b border-slate-200 flex items-center justify-between px-8 flex-shrink-0">
          <div class="flex items-center gap-4">
            <h2 class="text-xl font-bold text-slate-800 capitalize">
              {location.pathname === "/"
                ? "Dashboard"
                : location.pathname.split("/")[1]}
            </h2>
          </div>

          <div class="flex items-center gap-4">
            <Show when={user()?.app_metadata?.role_id}>
              <span class="flex items-center gap-2 text-xs font-mono bg-indigo-50 text-indigo-700 px-3 py-1.5 rounded-full border border-indigo-100">
                <span class="w-2 h-2 bg-indigo-500 rounded-full animate-pulse"></span>
                Role: {user()?.app_metadata?.role_id}
              </span>
            </Show>
          </div>
        </header>

        <div class="flex-1 overflow-y-auto p-8">
          <div class="max-w-7xl mx-auto h-full">{props.children}</div>
        </div>
      </main>
    </div>
  );
}
