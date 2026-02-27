# syntax=docker/dockerfile:1.4

# ─────────────────────────────────────────────────────────────────
# Build args — CI passes these via --build-arg.
# Defaults here are for local manual builds only.
#
# NOTE: Python 3.12 and Node 18 are intentionally pinned for
#       Frappe version-15 compatibility.
#       Frappe v16 uses Python 3.14 / Node 24 — do NOT upgrade
#       these until you migrate to version-16.
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
# No compiler, no build headers, no NVM build cache.
# This is the foundation for both the builder and final stages —
# keep it as lean as possible.
#
# Changes vs previous:
#   + chromium-headless-shell  (Chromium PDF alongside wkhtmltopdf)
#   + restic + gpg             (built-in backup capability)
#   + file                     (MIME-type detection at runtime)
#   + media-types              (replaces mime-support — updated pkg)
#   + less                     (pager utility, expected by bench CLI)
#   + NVM .bashrc entries      (nvm works in interactive shells too)
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
        # Core utilities
        curl \
        git \
        vim \
        less \
        file \
        # Web server
        nginx \
        gettext-base \
        # MIME type detection (replaces mime-support)
        media-types \
        # WeasyPrint runtime (PDF via HTML/CSS renderer)
        libpango-1.0-0 \
        libharfbuzz0b \
        libpangoft2-1.0-0 \
        libpangocairo-1.0-0 \
        # CJK font support
        fonts-noto-cjk \
        # Chromium PDF (alternative to wkhtmltopdf for newer Frappe)
        chromium \
        # Backup tooling
        restic \
        gpg \
        # DB clients — runtime libs only (no dev headers; those stay in build stage)
        mariadb-client \
        libpq5 \
        postgresql-client \
        # Healthcheck / process utilities
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
    # Make nvm available in interactive shells (bash / bench exec sessions)
    && echo 'export NVM_DIR="/home/frappe/.nvm"'                                           >>/home/frappe/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'                            >>/home/frappe/.bashrc \
    && echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'          >>/home/frappe/.bashrc \
    # ── wkhtmltopdf (patched Qt — required for Frappe v15 PDF) ───
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
    # ── cleanup ───────────────────────────────────────────────────
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default


# ═════════════════════════════════════════════════════════════════
# STAGE 2: build
# base + apt build-only packages.
#
# WHY a separate stage from builder?
#   Separating "install apt build tools" from "run bench init"
#   gives Docker a stable cached layer for the apt step.
#   When only your app code changes, the apt layer is a cache hit
#   and only bench init re-runs — saving several minutes per CI build.
#
#   This is the key structural improvement from Frappe's v16 approach.
#   Nothing in this stage reaches the final image.
# ═════════════════════════════════════════════════════════════════
FROM base AS build

USER root

# Build tools — compiler + headers for native Python extensions.
# libpq-dev   → compile psycopg2 from source
# libmariadb-dev → compile mysqlclient from source
# All of these are DISCARDED after builder stage — NOT in final image.
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
        libpq-dev \
        libmariadb-dev \
        pkg-config \
        redis-tools \
        rlwrap \
        tk8.6-dev \
        cron \
    && rm -rf /var/lib/apt/lists/*

USER frappe


# ═════════════════════════════════════════════════════════════════
# STAGE 3: builder
# Inherits build (apt tools already cached) + runs bench init.
# Only /home/frappe/frappe-bench is copied to the final stage —
# everything else here is discarded by Docker automatically.
# ═════════════════════════════════════════════════════════════════
FROM build AS builder

ARG FRAPPE_PATH
ARG FRAPPE_BRANCH
ARG PYTHON_VERSION
ARG APPS_JSON_BASE64

USER root

# Decode apps.json as root before switching to frappe user.
# (frappe user has no write access to /opt)
RUN if [ -n "${APPS_JSON_BASE64}" ]; then \
        mkdir -p /opt/frappe && \
        echo "${APPS_JSON_BASE64}" | base64 -d > /opt/frappe/apps.json; \
    fi

USER frappe

# bench init clones frappe + all custom apps in one pass via --apps_path.
#
# --python flag is REQUIRED for Frappe v15 to select the correct venv binary.
# (Frappe v16 dropped this requirement — do not remove it until you upgrade.)
#
# After init, aggressively shrink the bench before the COPY to final:
#   .git dirs       → 300–500 MB on multi-app builds, useless at runtime
#   __pycache__     → regenerated on first import anyway
#   pip in venv     → pip is a build tool, not needed at runtime
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
    && find /home/frappe/frappe-bench/apps -mindepth 1 -name ".git" -type d \
       | xargs rm -rf \
    && find /home/frappe/frappe-bench/env -name "__pycache__" -type d \
       | xargs rm -rf \
    && find /home/frappe/frappe-bench/env/lib -name "pip" -type d \
       | xargs rm -rf \
    && echo "{}" > /home/frappe/frappe-bench/sites/common_site_config.json


# ═════════════════════════════════════════════════════════════════
# STAGE 4: backend (final)
# Clean base image + only the built bench copied from builder.
# Result: slim runtime image — no compiler, no build headers,
#         no .git history, no pip tooling.
# ═════════════════════════════════════════════════════════════════
FROM base AS backend

USER frappe

# Discourage exec-ing into production containers for ad-hoc changes.
# Mirrors Frappe's v16 convention; harmless but a good reminder.
RUN echo 'echo "Commands restricted in production container. Read the FAQ before proceeding."' \
    >> /home/frappe/.bashrc

COPY --from=builder --chown=frappe:frappe \
    /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

# sites       — shared volume for site files, configs, private uploads
# sites/assets — static asset bundle (served by nginx; separate for clarity)
# logs        — bench + gunicorn + worker logs
VOLUME [ \
    "/home/frappe/frappe-bench/sites", \
    "/home/frappe/frappe-bench/sites/assets", \
    "/home/frappe/frappe-bench/logs" \
]

# ── Healthcheck ───────────────────────────────────────────────────
# TCP port check — NOT HTTP status code.
#
# DO NOT use "curl -f http://localhost:8000":
#   Before a site is created, gunicorn returns 404/500 → curl -f exits 1
#   → Docker marks unhealthy → kills container before site creation runs.
#
# TCP check: port is open as soon as gunicorn binds, regardless of site state.
# start-period=180s covers slow first boot and --preload worker startup time.
#
# Uncomment once your deployment is stable and sites are pre-created:
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
