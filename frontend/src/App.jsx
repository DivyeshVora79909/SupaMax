import { A, useNavigate } from "@solidjs/router";
import { session } from "./lib/auth";
import { supabase } from "./lib/supabase";

function App(props) {
  const navigate = useNavigate();

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate("/login");
  };

  return (
    <div class="min-h-screen bg-gray-50">
      <nav class="bg-white border-b px-6 py-4 flex justify-between items-center">
        <A href="/" class="text-xl font-bold text-blue-600">
          V42 Manager
        </A>
        <div class="space-x-4 flex items-center">
          {session() ? (
            <>
              <span class="text-sm text-gray-600">{session().user.email}</span>
              <button
                onClick={handleLogout}
                class="text-sm bg-gray-100 hover:bg-gray-200 px-3 py-1 rounded"
              >
                Logout
              </button>
            </>
          ) : (
            <A href="/login" class="text-sm font-medium">
              Login
            </A>
          )}
        </div>
      </nav>

      <main class="max-w-5xl mx-auto py-8">{props.children}</main>
    </div>
  );
}

export default App;
