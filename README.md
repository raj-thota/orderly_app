# Closr

Closr is a Flutter CRM app for turning chat conversations into leads, follow-ups,
and orders.

## Local setup

Closr reads Supabase credentials from compile-time variables first, with a
tracked fallback file at `assets/env/default.env`.

Run the app with:

```bash
flutter run \
  --dart-define=SUPABASE_URL=your-project-url \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

For quick local-only testing, you can also fill in
`assets/env/default.env`, but `--dart-define` is the safer option because it
keeps secrets out of the repo.
