# syntax=docker/dockerfile:1.7
ARG REGISTRY=docker.io
FROM ${REGISTRY}/python:3.14-slim-bookworm AS python
FROM ${REGISTRY}/node:24-bookworm-slim AS node

FROM ${REGISTRY}/buildpack-deps:bookworm AS base

# Python ve Node.js ortamlarını birleştiriyoruz
COPY --from=python /usr/local/ /usr/local/
COPY --from=node /usr/local/ /usr/local/
COPY --from=node /opt/ /opt/

# Kullanıcı oluşturma ve gerekli sistem paketlerinin kurulumu
RUN set -ex \
	&& groupadd -r app --gid=999 \
	&& useradd --system --create-home --home /app --gid 999 --uid=999 --shell /bin/bash app \
	&& rm -f /usr/local/bin/docker-entrypoint.sh \
	&& python --version \
	&& pip --version \
	&& node --version \
	&& corepack enable \
	&& yarn --version \
	&& python3 -m pip install 'psycopg2-binary==2.9.10' && python3 -m pip install 'Django==5.2' \
    && echo "OK"

# --- Builder Katmanı ---
FROM base AS builder

ARG TURBO_TEAM
ARG TURBO_TOKEN
ARG TURBO_API

# Turborepo ve Next.js uyarılarını/telemetrisini kapatıyoruz
ENV TURBO_TELEMETRY_DISABLED=1
ENV NEXT_TELEMETRY_DISABLED=1
ENV TURBO_CACHE=remote:rw
ENV NODE_ENV=production

WORKDIR /app

# Projenin tamamını kopyalıyoruz
COPY --chown=app:app . /app

# Geçici .env oluşturma (Build sırasında hata almamak için)
RUN echo "# Build time .env config!" > /app/.env && \
	echo "COOKIE_SECRET=undefined" >> /app/.env && \
	echo "DATABASE_URL=undefined" >> /app/.env && \
	echo "REDIS_URL=undefined" >> /app/.env && \
	echo "FILE_FIELD_ADAPTER=local" >> /app/.env

RUN chmod +x ./bin/run_condo_domain_tests.sh

# Bağımlılıkları Kur ve Build Et
# Yarn v3+ için cache yolu: /root/.yarn/berry/cache
RUN --mount=type=cache,target=/root/.yarn/berry/cache \
    --mount=type=cache,target=/app/.turbo \
    set -ex \
    && yarn install --immutable \
    && yarn build \
    && rm -f /app/.env \
    && ls -lah /app/

# --- Runtime (Çalışma) Katmanı ---
FROM base
USER app:app
WORKDIR /app

# Sadece gerekli build çıktılarını kopyalıyoruz
COPY --from=builder --chown=app:app /app /app

# Uygulamanın başlatılması (Varsayılan komut)
# Not: Condo'nun tam çalışma komutunu Procfile veya Dokploy üzerinden override edebilirsiniz.
CMD ["yarn", "start"]
