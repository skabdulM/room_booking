# syntax=docker/dockerfile:1.4

# ─────────────────────────────────────────────────────────────────
# Build args — values are passed by CI via --build-arg.
# Defaults here are fallbacks for local manual builds only.
# In CI these come from ci/build.env sourced in the workflow.
# ─────────────────────────────────────────────────────────────────
ARG FRAPPE_PATH=https://github.com/frappe/frappe
ARG FRAPPE_BRANCH=version-15
ARG PYTHON_VERSION=3.12.7
ARG NODE_VERSION=18.20.4
ARG APPS_JSON_BASE64


# ─────────────────────────────────────────────────────────────────
# STAGE 1: builder
# frappe/bench:latest has bench, python, node pre-installed.
# We use it to clone and build all apps, then copy the result.
# ─────────────────────────────────────────────────────────────────
FROM frappe/bench:latest AS builder

# Re-declare ARGs after FROM — Docker scoping requires this
ARG FRAPPE_PATH
ARG FRAPPE_BRANCH
ARG PYTHON_VERSION
ARG NODE_VERSION
ARG APPS_JSON_BASE64

USER root

# Write apps.json before switching to frappe user (no write access to /opt as frappe)
RUN if [ -n "${APPS_JSON_BASE64}" ]; then \
      mkdir -p /opt/frappe && \
      echo "${APPS_JSON_BASE64}" | base64 -d > /opt/frappe/apps.json; \
    fi

USER frappe

WORKDIR /home/frappe

# bench init clones frappe + all apps from apps.json in one step.
# --apps_path is the correct way to install extra apps at init time.
# Do NOT use a separate "bench install apps" — that command does not exist.
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
      /home/frappe/frappe-bench && \
    cd /home/frappe/frappe-bench && \
    echo "{}" > sites/common_site_config.json && \
    # Remove .git dirs to slim the image
    find apps -mindepth 1 -path "*/.git" | xargs rm -fr


# ─────────────────────────────────────────────────────────────────
# STAGE 2: final
# Same base image — has all runtime deps (nginx, python, node).
# We copy the fully built bench from the builder stage.
# We do NOT use frappe/erpnext:v15 as final because it already
# contains its own /home/frappe/frappe-bench which would conflict.
# ─────────────────────────────────────────────────────────────────
FROM frappe/bench:latest AS backend

USER root

COPY --chown=frappe:frappe resources/nginx-template.conf /templates/nginx/frappe.conf.template
COPY --chown=frappe:frappe resources/nginx-entrypoint.sh /usr/local/bin/nginx-entrypoint.sh
RUN chmod +x /usr/local/bin/nginx-entrypoint.sh

USER frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

VOLUME [ \
  "/home/frappe/frappe-bench/sites", \
  "/home/frappe/frappe-bench/logs" \
]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000 || exit 1

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
