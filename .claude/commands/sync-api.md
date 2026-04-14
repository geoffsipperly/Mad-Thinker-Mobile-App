---
description: Fetch the latest backend API reference from Supabase into docs/
---

Fetch the live, auto-generated API reference from the Supabase backend and write it to `docs/api-reference.md` and `docs/api-reference.json`. The backend is managed by a Loveable agent, so these files can drift from the app — always re-sync before reasoning about endpoint contracts.

Run both commands:

```bash
curl -sf "https://koyegehcwcrvxpfthkxq.supabase.co/functions/v1/api-reference?format=markdown" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtveWVnZWhjd2NydnhwZnRoa3hxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3NjE3MzMsImV4cCI6MjA4OTMzNzczM30.XVjI2BRX0-XdHQFK_Vas2jc7zZN32DCXRVKtnsbQQGk" \
  -o docs/api-reference.md

curl -sf "https://koyegehcwcrvxpfthkxq.supabase.co/functions/v1/api-reference" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtveWVnZWhjd2NydnhwZnRoa3hxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3NjE3MzMsImV4cCI6MjA4OTMzNzczM30.XVjI2BRX0-XdHQFK_Vas2jc7zZN32DCXRVKtnsbQQGk" \
  -o docs/api-reference.json
```

After fetching:
1. Read the first ~10 lines of `docs/api-reference.md` and report the **Version** and **Generated** timestamp to the user.
2. If either curl fails (non-zero exit from `-f`), surface the error — do NOT leave a half-written or empty file in place. Run `git checkout docs/api-reference.md docs/api-reference.json` to restore the previous snapshot.
3. If the version is newer than what was committed, offer to show a diff of the changed endpoints.
4. Do NOT automatically commit — the user decides when to snapshot.

The `apikey` is the public Supabase anon key. Safe to commit, gated by RLS server-side.
