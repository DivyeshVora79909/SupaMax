import { createResource, For } from "solid-js";
import { supabase } from "../../lib/supabase";
import { Card } from "../../components/ui/Card";
import { Badge } from "../../components/ui/Badge";
import { Plus, Search, Mail, Phone, Building } from "lucide-solid";

export default function Contacts() {
  const [contacts, { refetch }] = createResource(async () => {
    const { data } = await supabase
      .from("crm_contacts")
      .select("*, crm_companies(name)")
      .order("created_at", { ascending: false });
    return data || [];
  });

  const addContact = async () => {
    const first_name = prompt("First Name:");
    if (!first_name) return;
    const last_name = prompt("Last Name:");
    const email = prompt("Email:");

    await supabase
      .from("crm_contacts")
      .insert([{ first_name, last_name, email }]);
    refetch();
  };

  return (
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-2xl font-bold text-slate-900">Contacts</h1>
          <p class="text-slate-500">People associated with your deals</p>
        </div>
        <button
          onClick={addContact}
          class="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm font-medium flex items-center gap-2"
        >
          <Plus size={16} /> Add Contact
        </button>
      </div>

      <Card class="overflow-hidden border-0 shadow-md">
        <div class="p-4 bg-white border-b border-slate-100 flex gap-4">
          <div class="relative flex-1">
            <Search size={18} class="absolute left-3 top-2.5 text-slate-400" />
            <input
              type="text"
              placeholder="Search contacts..."
              class="w-full pl-10 pr-4 py-2 bg-slate-50 border-none rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 outline-none"
            />
          </div>
        </div>
        <table class="w-full text-left text-sm text-slate-600">
          <thead class="bg-slate-50 text-slate-900 font-semibold border-b border-slate-200">
            <tr>
              <th class="px-6 py-4">Name</th>
              <th class="px-6 py-4">Contact Info</th>
              <th class="px-6 py-4">Company</th>
              <th class="px-6 py-4">Owner (Role)</th>
              <th class="px-6 py-4 text-right">Access</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <For each={contacts()}>
              {(contact) => (
                <tr class="hover:bg-slate-50 transition-colors group">
                  <td class="px-6 py-4">
                    <div class="flex items-center gap-3">
                      <div class="w-8 h-8 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-bold text-xs">
                        {contact.first_name[0]}
                        {contact.last_name?.[0]}
                      </div>
                      <div>
                        <div class="font-medium text-slate-900">
                          {contact.first_name} {contact.last_name}
                        </div>
                        <div class="text-xs text-slate-400">
                          Added{" "}
                          {new Date(contact.created_at).toLocaleDateString()}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td class="px-6 py-4 space-y-1">
                    <div class="flex items-center gap-2 text-xs">
                      <Mail size={12} class="text-slate-400" />{" "}
                      {contact.email || "-"}
                    </div>
                    <div class="flex items-center gap-2 text-xs">
                      <Phone size={12} class="text-slate-400" />{" "}
                      {contact.phone || "-"}
                    </div>
                  </td>
                  <td class="px-6 py-4">
                    {contact.crm_companies ? (
                      <span class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium bg-slate-100 text-slate-700">
                        <Building size={12} />
                        {contact.crm_companies.name}
                      </span>
                    ) : (
                      <span class="text-slate-400">-</span>
                    )}
                  </td>
                  <td class="px-6 py-4 font-mono text-xs text-slate-500">
                    {contact.owner_role_id.split("-")[0]}...
                  </td>
                  <td class="px-6 py-4 text-right">
                    <Badge variant="default" class="text-[10px]">
                      {contact.enforcement_mode}
                    </Badge>
                  </td>
                </tr>
              )}
            </For>
            {contacts()?.length === 0 && (
              <tr>
                <td colspan="5" class="px-6 py-12 text-center text-slate-400">
                  No contacts found. Try adding one.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </Card>
    </div>
  );
}
