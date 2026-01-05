import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

dotenv.config();

const supabaseUrl = 'http://127.0.0.1:54321';
const serviceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

export const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
});

export const supabaseAnon = createClient(supabaseUrl, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0', {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
});

export const createAuthenticatedClient = async (accessToken) => {
    const client = createClient(supabaseUrl, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0', {
        auth: {
            autoRefreshToken: false,
            persistSession: false
        }
    });
    await client.auth.setSession({ access_token: accessToken, refresh_token: 'none' });
    return client;
};

export const cleanup = async (email, tenantSlug) => {
    if (email) {
        await supabaseAdmin.auth.admin.deleteUser(
            (await supabaseAdmin.from('profiles').select('id').eq('email', email).single()).data?.id
        );
    }
    if (tenantSlug) {
        await supabaseAdmin.from('tenants').delete().eq('slug', tenantSlug);
    }
};
