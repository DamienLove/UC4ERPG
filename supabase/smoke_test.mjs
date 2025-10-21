import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const anon = process.env.SUPABASE_ANON_KEY;
if (!url || !anon) {
  console.error("Missing SUPABASE_URL or SUPABASE_ANON_KEY");
  process.exit(1);
}

const supabase = createClient(url, anon);

const { data: authData, error: authErr } = await supabase.auth.signInAnonymously();
if (authErr) { console.error("Auth error:", authErr); process.exit(1); }
console.log("Signed in anon as:", authData?.user?.id);

const text = `smoke ${new Date().toISOString()}`;
const { data: ins, error: insErr } = await supabase.from('journal_entries').insert({ text }).select('*');
if (insErr) { console.error("Insert error:", insErr); process.exit(1); }
console.log("Inserted:", ins);

const { data: rows, error: selErr } = await supabase.from('journal_entries').select('*').order('created_at', { ascending: false }).limit(3);
if (selErr) { console.error("Select error:", selErr); process.exit(1); }
console.log("Recent rows:", rows);