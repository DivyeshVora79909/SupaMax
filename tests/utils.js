import { createClient } from '@supabase/supabase-js';
import { supabaseUrl, supabaseAnonKey } from './config.js';

export const getClient = (accessToken) => {
    return createClient(supabaseUrl, supabaseAnonKey, {
        global: {
            headers: {
                Authorization: `Bearer ${accessToken}`
            }
        }
    });
};

export const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));
