import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const credentialsPath = path.join(__dirname, 'test_credentials.json');
let credentials = {};

if (fs.existsSync(credentialsPath)) {
    credentials = JSON.parse(fs.readFileSync(credentialsPath, 'utf8'));
}

export const supabaseUrl = process.env.SUPABASE_URL || credentials.SUPABASE_URL || 'http://127.0.0.1:54321';
export const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || credentials.SUPABASE_ANON_KEY;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || credentials.SUPABASE_SERVICE_ROLE_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
export const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
});

export const createTestUser = async (email, password, metadata = {}) => {
    const { data, error } = await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: metadata
    });
    if (error) throw error;
    return data.user;
};

export const deleteTestUser = async (userId) => {
    const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (error) throw error;
};

export const loginUser = async (email, password) => {
    const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password
    });
    if (error) throw error;
    return data.session;
};
