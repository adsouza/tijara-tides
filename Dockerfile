# Keep builder and runner on the same Debian release for ERTS/NIF compatibility.
ARG DEBIAN_VERSION=trixie-20260713-slim
FROM hexpm/elixir:1.20.2-erlang-29.0.4-debian-trixie-20260713-slim AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod --check-locked
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile
RUN mix assets.setup
COPY lib lib
COPY priv priv
COPY assets assets
COPY config/runtime.exs config/runtime.exs
# The release step compiles, minifies, and digests assets itself.
RUN mix release

FROM debian:${DEBIAN_VERSION} AS runner
RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=10000 \
    RELEASE_DISTRIBUTION=none
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/tijara_tides ./
USER nobody
EXPOSE 10000
ENTRYPOINT ["/usr/bin/tini", "--"]
# Free Render services have no pre-deploy command. Fail closed before the
# application starts if migration fails; exec preserves signal handling.
CMD ["/bin/sh", "-c", "/app/bin/tijara_tides eval 'TijaraTides.Release.migrate_if_configured()' && exec /app/bin/tijara_tides start"]
