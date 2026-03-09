# syntax=docker/dockerfile:1.7
ARG REGISTRY=docker.io
FROM ${REGISTRY}/python:3.14-slim-bookworm AS python
FROM ${REGISTRY}/node:24-bookworm-slim AS node

FROM ${REGISTRY}/buildpack-deps:bookworm AS base

COPY --from=python /usr/local/ /usr/local/
COPY --from=node /usr/local/ /usr/local/
COPY --from=node /opt/ /opt/

RUN set -ex \
    && groupadd -r app --gid=999 \
    && useradd --system --create-home --home /app --gid 999 --uid=999 --shell /bin/bash app \
    && corepack enable \
    && python3 -m pip install 'psycopg2-binary==2.9.10' 'Django==5.2'

# --- Builder Katmanı ---
FROM base AS builder

ENV TURBO_TELEMETRY_DISABLED=1
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
# Bazı karmaşık build süreçleri için RAM limitini artıralım
ENV NODE_OPTIONS="--max-old-space-size=4096"

WORKDIR /app
COPY --chown=app:app . /app

# .env hazırlığı
RUN echo "COOKIE_SECRET=placeholder\nDATABASE_URL=placeholder\nREDIS_URL=placeholder\nFILE_FIELD_ADAPTER=local" > /app/.env

# Bağımlılıkları Kur ve Build Et
RUN --mount=type=cache,target=/root/.yarn/berry/cache \
    --mount=type=cache,target=/app/.turbo \
    set -ex \
    && yarn config set nmHoistingLimits workspaces \
    && yarn install --no-immutable \
    && yarn build \
    && rm -f /app/.env

# --- Runtime Katmanı ---
FROM base
USER app:app
WORKDIR /app
COPY --from=builder --chown=app:app /app /app

CMD ["yarn", "start"]
