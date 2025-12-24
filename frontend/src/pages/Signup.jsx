import { createSignal } from "solid-js";
import { supabase } from "../lib/supabase";
import { useNavigate, A } from "@solidjs/router";
import {
  ShieldAlert,
  Loader2,
  Building2,
  User,
  Mail,
  Lock,
} from "lucide-solid";

export default function Signup() {
  const [fullName, setFullName] = createSignal("");
  const [companyName, setCompanyName] = createSignal("");
  const [email, setEmail] = createSignal("");
  const [password, setPassword] = createSignal("");

  const [loading, setLoading] = createSignal(false);
  const [error, setError] = createSignal("");
  const navigate = useNavigate();

  const handleSignup = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError("");

    // 1. Sign up user with metadata
    // The database trigger 'handle_new_user_signup' will read this metadata
    // to create the Organization and Roles automatically.
    const { data, error: authError } = await supabase.auth.signUp({
      email: email(),
      password: password(),
      options: {
        data: {
          full_name: fullName(),
          company_name: companyName(),
        },
      },
    });

    if (authError) {
      setError(authError.message);
      setLoading(false);
    } else {
      // If email confirmation is disabled in Supabase, this logs them in immediately
      if (data.session) {
        navigate("/");
      } else {
        // If email confirmation is enabled
        alert("Success! Please check your email to confirm your account.");
        navigate("/login");
      }
    }
  };

  return (
    <div class="min-h-screen bg-slate-50 flex items-center justify-center p-4">
      <div class="max-w-md w-full bg-white rounded-2xl shadow-xl border border-slate-100 overflow-hidden">
        <div class="p-8">
          <div class="flex flex-col items-center mb-6">
            <div class="w-12 h-12 bg-indigo-600 rounded-xl flex items-center justify-center text-white mb-4 shadow-lg shadow-indigo-200">
              <ShieldAlert size={24} />
            </div>
            <h1 class="text-2xl font-bold text-slate-900">Start for free</h1>
            <p class="text-slate-500 mt-2 text-center">
              Create your secure tenant in seconds.
            </p>
          </div>

          <form onSubmit={handleSignup} class="space-y-4">
            {error() && (
              <div class="p-3 bg-red-50 text-red-600 text-sm rounded-lg border border-red-100">
                {error()}
              </div>
            )}

            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs font-medium text-slate-700 mb-1">
                  Full Name
                </label>
                <div class="relative">
                  <User
                    size={16}
                    class="absolute left-3 top-2.5 text-slate-400"
                  />
                  <input
                    type="text"
                    required
                    value={fullName()}
                    onInput={(e) => setFullName(e.target.value)}
                    class="w-full pl-9 pr-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
                    placeholder="John Doe"
                  />
                </div>
              </div>
              <div>
                <label class="block text-xs font-medium text-slate-700 mb-1">
                  Company
                </label>
                <div class="relative">
                  <Building2
                    size={16}
                    class="absolute left-3 top-2.5 text-slate-400"
                  />
                  <input
                    type="text"
                    required
                    value={companyName()}
                    onInput={(e) => setCompanyName(e.target.value)}
                    class="w-full pl-9 pr-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
                    placeholder="Acme Inc."
                  />
                </div>
              </div>
            </div>

            <div>
              <label class="block text-xs font-medium text-slate-700 mb-1">
                Email
              </label>
              <div class="relative">
                <Mail
                  size={16}
                  class="absolute left-3 top-2.5 text-slate-400"
                />
                <input
                  type="email"
                  required
                  value={email()}
                  onInput={(e) => setEmail(e.target.value)}
                  class="w-full pl-9 pr-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
                  placeholder="you@company.com"
                />
              </div>
            </div>

            <div>
              <label class="block text-xs font-medium text-slate-700 mb-1">
                Password
              </label>
              <div class="relative">
                <Lock
                  size={16}
                  class="absolute left-3 top-2.5 text-slate-400"
                />
                <input
                  type="password"
                  required
                  minLength="6"
                  value={password()}
                  onInput={(e) => setPassword(e.target.value)}
                  class="w-full pl-9 pr-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
                  placeholder="••••••••"
                />
              </div>
            </div>

            <button
              type="submit"
              disabled={loading()}
              class="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-medium py-2.5 rounded-lg transition-colors flex items-center justify-center disabled:opacity-50 disabled:cursor-not-allowed mt-2"
            >
              {loading() ? (
                <Loader2 class="animate-spin" size={20} />
              ) : (
                "Create Organization"
              )}
            </button>
          </form>
        </div>
        <div class="bg-slate-50 p-4 text-center text-sm text-slate-500 border-t border-slate-100">
          Already have a tenant?{" "}
          <A href="/login" class="text-indigo-600 font-medium hover:underline">
            Log in
          </A>
        </div>
      </div>
    </div>
  );
}
