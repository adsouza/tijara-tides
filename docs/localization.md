# Localization

English is the default; Arabic is available from the Language selector in the
account menu or before signing in. The account stores the preference, so the web
client and the game embedded in the desktop client use the same language on
subsequent visits. Before signing in, a signed browser session stores the choice;
the first request falls back to the browser's preferred language.

`TijaraTides.Localization` is a presentation boundary. The domain and application
layers keep identifiers, amounts in cents, quantities, and timestamps unchanged.
They do not depend on Gettext or a request's locale. Each LiveView sets its own
process locale from the authenticated account; mail rendering scopes and restores
the locale for each recipient. Invitation mail uses the inviter's language until
the recipient has their own account.

New notices store a stable `code` and named `arguments`. The localization renderer
maps these to complete catalog messages, translating only known labels and leaving
player-provided names intact. Existing English notice rows remain readable. The
migration preserves them and enforces that each notice has either legacy text or
a structured message. Message arguments must never include credentials.

Gettext catalogs live in `priv/gettext`; Arabic includes all six plural forms.
Use whole messages with named placeholders rather than concatenating translated
fragments. Add new cargo/class labels to `Localization.Names`. Keep numeric input
values machine-readable; format displayed USD amounts through the shared CLDR
formatter. Currency remains USD regardless of language. Arabic number-format data
is bundled in `priv/cldr/locales` for reproducible builds.

Arabic sets the document to RTL, including portrait navigation. Geographic map
coordinates and routes are unchanged. Email addresses, tokens and numeric inputs
remain LTR. Port, harbor and region names and all 25 port descriptions have Arabic display
translations. Port identifiers remain unchanged in commands, routes and storage.
Company and ship names supplied by players are retained. The native desktop
server-selection window and some legacy operational reason strings may still
fall back to English.

When changing messages, run `mix gettext.extract`, update the Arabic catalog,
and run `python3 scripts/test-game-db.py`. Translation changes need linguistic
review as well as tests. The database migration runs through the normal deployment
migration mechanism; no separate locale database or currency migration is needed.
