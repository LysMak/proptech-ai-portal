// ============================================================
// PropTech Real Estate AI Analytics Portal — runtime config
//
// This is the ONLY file you need to edit before the app works.
// Both values below are PUBLIC by design (the "anon" key is meant
// to be shipped to the browser) — access is restricted server-side
// by the Row Level Security policy defined in schema.sql, which
// only allows SELECT (read) queries. Never put a service_role key
// here.
//
// Where to find these values:
//   Supabase Dashboard -> Project Settings -> API
//     - "Project URL"       -> SUPABASE_URL
//     - "anon public" key   -> SUPABASE_ANON_KEY
// ============================================================

const SUPABASE_URL = "https://ntntugrvwdecmnacniwn.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im50bnR1Z3J2d2RlY21uYWNuaXduIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxMDk3NzAsImV4cCI6MjEwNTY4NTc3MH0.CpXdWY3SHBcALmpBTDCHbVuaTDu0hGZujTtbZwQ1vLA";
