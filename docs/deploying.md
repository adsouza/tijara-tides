# Deploy the server to Render

The repository includes a multi-stage Dockerfile and a Render Blueprint for one
Free web service in Ohio, near the Neon database in AWS us-east-2. The runtime
image contains the production release and TLS certificates, runs as an
unprivileged user, and includes no desktop toolchain or local environment files.

## First deployment

1. Commit and push this repository, including `Dockerfile`, `.dockerignore`,
   `render.yaml`, and the CI workflows. Wait for CI to pass, including the
   container build and production HTTP smoke check.
2. In Render, choose **New → Blueprint**, connect the GitHub repository, and
   select the branch containing these files. Review the single Free web service
   in Ohio. No Render database or paid disk is defined.
3. Supply the two prompted secret environment variables:
   - `DATABASE_URL`: the direct Neon PostgreSQL connection string from your
     ignored `.env.local` (without shell quotes). See [database setup](database.md).
   - `SECRET_KEY_BASE`: output of `mix phx.gen.secret`. Keep the same value across
     deployments so browser and desktop sessions remain valid.
4. Create the Blueprint. Render builds the Dockerfile and starts its release.
   The initial creation deploys immediately; subsequent automatic deployments
   are configured to wait for passing CI checks.
5. Open the assigned HTTPS URL and `/healthz`, then open the lobby in two browser
   sessions. The live guest count should update in both. Enter the same HTTPS
   server URL in the native desktop client.

Render supplies `PORT` and `RENDER_EXTERNAL_HOSTNAME`. The server binds to all IPv4
interfaces and uses that hostname for its public HTTPS URL and LiveView origin
checks. For a custom domain, configure it in Render and set `PHX_HOST` to that
hostname (no scheme or path); it takes precedence over Render's hostname.
`PHX_SERVER=true` is already configured. TLS terminates at Render's proxy;
Phoenix honors `X-Forwarded-Proto` and uses secure session cookies.

The `/healthz` endpoint (also available at `/health`) returns plain `ok` without a session, redirect, database
query, or world command. It checks HTTP availability, not database readiness.
Do not add an external keep-awake monitor: the free service may sleep while idle.

## Local container check

With Docker installed:

```sh
docker build -t tijara-tides:local .
docker run --rm --name tijara-tides-local -p 127.0.0.1:10000:10000 \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e RENDER_EXTERNAL_HOSTNAME=smoke.onrender.com tijara-tides:local
```

In another terminal, run `python3 scripts/smoke_server.py 10000`. It verifies the
health response, HTTPS redirect, proxy-backed lobby, secure session cookie, and
compiled JS/CSS. The check does not need a database. Plain HTTP lobby browsing
requires a local HTTPS reverse proxy for the production secure cookie behavior.
Never pass database credentials or the production signing secret as build args.

## Current limitations

Neon connectivity is configured, but there are no game tables, migrations, or
state writes yet. The lobby's in-memory state resets on restart or redeployment.
No migration or seed command runs during image build or startup.

Keep a single service instance. Render can briefly overlap old and new processes
while deploying; before adding durable gameplay writes, implement database-backed
ownership fencing so only the current world owner can commit. Persistence must
load state at startup and transactionally store incremental changes for each
player's independent turn before acknowledging/broadcasting it. No global turn
barrier or offline simulation is intended.

Configuration fields follow the [Render Blueprint reference](https://render.com/docs/blueprint-spec).
See also [Render health checks](https://render.com/docs/health-checks) and
[free services](https://render.com/docs/free).
