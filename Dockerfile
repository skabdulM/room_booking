# syntax=docker/dockerfile:1.4

# ─────────────────────────────────────────────────────────────────
# Build args — CI passes these via --build-arg.
# Defaults here are for local manual builds only.
# ─────────────────────────────────────────────────────────────────
ARG PYTHON_VERSION=3.12.7
ARG NODE_VERSION=18.20.4
ARG DEBIAN_BASE=bookworm
ARG FRAPPE_PATH=https://github.com/frappe/frappe
ARG FRAPPE_BRANCH=version-15
ARG APPS_JSON_BASE64
ARG WKHTMLTOPDF_VERSION=0.12.6.1-3
ARG WKHTMLTOPDF_DISTRO=bookworm


# ═════════════════════════════════════════════════════════════════
# STAGE 1: base
# Slim Python image with ONLY runtime dependencies.
# No compiler, no build headers, no NVM cache.
# This is what the final image is built from — keep it lean.
# ═════════════════════════════════════════════════════════════════
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base

ARG NODE_VERSION
ARG WKHTMLTOPDF_VERSION
ARG WKHTMLTOPDF_DISTRO

ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}

COPY resources/nginx-template.conf /templates/nginx/frappe.conf.template
COPY resources/*.sh /usr/local/bin/

RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
        curl \
        git \
        vim \
        nginx \
        gettext-base \
        mime-support \
        # WeasyPrint runtime (PDF generation)
        libpango-1.0-0 \
        libharfbuzz0b \
        libpangoft2-1.0-0 \
        libpangocairo-1.0-0 \
        # Fonts
        fonts-noto-cjk \
        # DB clients — runtime only, NOT dev headers (those stay in builder)
        mariadb-client \
        libpq5 \
        postgresql-client \
        # Healthcheck / utilities
        wait-for-it \
        jq \
    # ── Node via NVM ─────────────────────────────────────────────
    && mkdir -p ${NVM_DIR} \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash \
    && . ${NVM_DIR}/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm use v${NODE_VERSION} \
    && npm install -g yarn \
    && nvm alias default v${NODE_VERSION} \
    # Remove NVM download cache — not needed at runtime
    && rm -rf ${NVM_DIR}/.cache \
    # ── wkhtmltopdf ──────────────────────────────────────────────
    && if [ "$(uname -m)" = "aarch64" ]; then ARCH=arm64; else ARCH=amd64; fi \
    && DEB=wkhtmltox_${WKHTMLTOPDF_VERSION}.${WKHTMLTOPDF_DISTRO}_${ARCH}.deb \
    && curl -sLO https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}/${DEB} \
    && apt-get install -y ./${DEB} \
    && rm ${DEB} \
    # ── frappe-bench CLI ─────────────────────────────────────────
    && pip3 install --no-cache-dir frappe-bench \
    # ── nginx non-root setup ─────────────────────────────────────
    && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /run/nginx.pid \
    && chown -R frappe:frappe \
        /etc/nginx/conf.d \
        /etc/nginx/nginx.conf \
        /var/log/nginx \
        /var/lib/nginx \
        /run/nginx.pid \
    && chmod 755 /usr/local/bin/*.sh \
    && chmod 644 /templates/nginx/frappe.conf.template \
    # ── final cleanup ─────────────────────────────────────────────
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default


# ═════════════════════════════════════════════════════════════════
# STAGE 2: builder
# Inherits base + adds build-only packages.
# Only /home/frappe/frappe-bench is copied to final — everything
# else in this stage is discarded automatically by Docker.
# ═════════════════════════════════════════════════════════════════
FROM base AS builder

ARG FRAPPE_PATH
ARG FRAPPE_BRANCH
ARG PYTHON_VERSION
ARG APPS_JSON_BASE64

USER root

# Build tools — compiler, headers for native Python extensions.
# These are NOT in the final image (they stay in this stage only).
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        wget \
        gcc \
        build-essential \
        libbz2-dev \
        libffi-dev \
        liblcms2-dev \
        libldap2-dev \
        libsasl2-dev \
        libtiff5-dev \
        libwebp-dev \
        # Needed to compile mysqlclient / psycopg2 from source
        libpq-dev \
        libmariadb-dev \
        redis-tools \
        rlwrap \
        tk8.6-dev \
    && rm -rf /var/lib/apt/lists/*

# Write apps.json before switching to frappe user (no write access to /opt)
RUN if [ -n "${APPS_JSON_BASE64}" ]; then \
        mkdir -p /opt/frappe && \
        echo "${APPS_JSON_BASE64}" | base64 -d > /opt/frappe/apps.json; \
    fi

USER frappe

# bench init clones frappe + all apps in one pass via --apps_path.
# Note: "bench install apps" does NOT exist — apps_path is the correct way.
RUN export APP_INSTALL_ARGS="" && \
    if [ -n "${APPS_JSON_BASE64}" ]; then \
        export APP_INSTALL_ARGS="--apps_path=/opt/frappe/apps.json"; \
    fi && \
    bench init ${APP_INSTALL_ARGS} \
        --frappe-path=${FRAPPE_PATH} \
        --frappe-branch=${FRAPPE_BRANCH} \
        --python=python${PYTHON_VERSION%.*} \
        --no-procfile \
        --no-backups \
        --skip-redis-config-generation \
        --verbose \
        /home/frappe/frappe-bench \
    # ── Shrink the bench before copying to final stage ───────────
    # .git dirs: 300-500MB on multi-app builds
    && find /home/frappe/frappe-bench/apps -mindepth 1 -name ".git" -type d \
       | xargs rm -rf \
    # __pycache__ in virtualenv
    && find /home/frappe/frappe-bench/env -name "__pycache__" -type d \
       | xargs rm -rf \
    # pip itself inside the venv (not needed at runtime)
    && find /home/frappe/frappe-bench/env/lib -name "pip" -type d \
       | xargs rm -rf \
    && echo "{}" > /home/frappe/frappe-bench/sites/common_site_config.json


# ═════════════════════════════════════════════════════════════════
# STAGE 3: final (backend)
# Clean base image + only the built bench copied across.
# Result: slim runtime image with no compiler or build headers.
# ═════════════════════════════════════════════════════════════════
FROM base AS backend

USER frappe

COPY --from=builder --chown=frappe:frappe \
    /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

VOLUME [ \
    "/home/frappe/frappe-bench/sites", \
    "/home/frappe/frappe-bench/logs" \
]

# ── Healthcheck ───────────────────────────────────────────────────
# Check TCP port is open — NOT HTTP status code.
#
# Why NOT "curl -f http://localhost:8000":
#   With no Frappe site yet, gunicorn returns 404/500 → curl -f exits 1
#   → Docker marks unhealthy → kills container → "Complete" in Swarm logs
#   → site creation never happens (exactly what you saw).
#
# Why TCP check works:
#   The port is open as soon as gunicorn binds, regardless of site state.
#   start-period=180s covers slow first boot + --preload worker startup.
# HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
#     CMD bash -c 'cat /dev/null > /dev/tcp/localhost/8000' || exit 1

CMD [ \
    "/home/frappe/frappe-bench/env/bin/gunicorn", \
    "--chdir=/home/frappe/frappe-bench/sites", \
    "--bind=0.0.0.0:8000", \
    "--threads=4", \
    "--workers=2", \
    "--worker-class=gthread", \
    "--worker-tmp-dir=/dev/shm", \
    "--timeout=120", \
    "--preload", \
    "frappe.app:application" \
]
