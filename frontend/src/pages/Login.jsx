import { createSignal } from "solid-js";
import { supabase } from "../lib/supabase";
import { useNavigate, A } from "@solidjs/router";
import { ShieldAlert, Loader2 } from "lucide-solid";

export default function Login() {
  const [email, setEmail] = createSignal("");
  const [password, setPassword] = createSignal("");
  const [loading, setLoading] = createSignal(false);
  const [error, setError] = createSignal("");
  const navigate = useNavigate();

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError("");

    const { error: authError } = await supabase.auth.signInWithPassword({
      email: email(),
      password: password(),
    });

    if (!authError) {
      navigate("/");
    } else {
      setError(authError.message);
      setLoading(false);
    }
  };

  return (
    <div class="min-h-screen bg-slate-50 flex items-center justify-center p-4">
      <div class="max-w-md w-full bg-white rounded-2xl shadow-xl border border-slate-100 overflow-hidden">
        <div class="p-8">
          <div class="flex flex-col items-center mb-8">
            <div class="w-12 h-12 bg-indigo-600 rounded-xl flex items-center justify-center text-white mb-4 shadow-lg shadow-indigo-200">
              <ShieldAlert size={24} />
            </div>
            <h1 class="text-2xl font-bold text-slate-900">Welcome back</h1>
            <p class="text-slate-500 mt-2">Sign in to your organization</p>
          </div>

          <form onSubmit={handleLogin} class="space-y-4">
            {error() && (
              <div class="p-3 bg-red-50 text-red-600 text-sm rounded-lg border border-red-100">
                {error()}
              </div>
            )}

            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">
                Email
              </label>
              <input
                type="email"
                required
                value={email()}
                onInput={(e) => setEmail(e.target.value)}
                class="w-full px-4 py-2 bg-slate-50 border border-slate-200 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none transition-all"
                placeholder="name@company.com"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">
                Password
              </label>
              <input
                type="password"
                required
                value={password()}
                onInput={(e) => setPassword(e.target.value)}
                class="w-full px-4 py-2 bg-slate-50 border border-slate-200 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none transition-all"
                placeholder="••••••••"
              />
            </div>

            <button
              type="submit"
              disabled={loading()}
              class="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-medium py-2.5 rounded-lg transition-colors flex items-center justify-center disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading() ? (
                <Loader2 class="animate-spin" size={20} />
              ) : (
                "Sign In"
              )}
            </button>
          </form>
        </div>
        <div class="bg-slate-50 p-4 text-center text-sm text-slate-500 border-t border-slate-100">
          Don't have an account?{" "}
          <A href="/signup" class="text-indigo-600 font-medium hover:underline">
            Sign up
          </A>
        </div>
      </div>
    </div>
  );
}
