# The npm cache and node_modules are populated at image build time so the
# measured stages can run with --network none.
FROM debian@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

ARG NODE_VERSION=24.18.0
ARG NODE_SHA256=55aa7153f9d88f28d765fcdad5ae6945b5c0f98a36881703817e4c450fa76742
ARG CHROMIUM_DEB=chromium_152.0.7977.82-1~deb12u1_amd64.deb
ARG CHROMIUM_SHA256=a95a8ff7db26ab9ddc69354dd99e89ba006f40b694f7cf643b82a0dcb38c0cb1
ARG SANDBOX_DEB=chromium-sandbox_152.0.7977.82-1~deb12u1_amd64.deb
ARG SANDBOX_SHA256=bb8e7023f138cbbfe0d451e10f8f6aceda799d28e51ded090203f140bac7b778

# chromium-sandbox ships the SUID helper; without it the browser refuses to
# start and karma-chrome-launcher passes no --no-sandbox to fall back on.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl xz-utils; \
    base=http://security.debian.org/debian-security/pool/updates/main/c/chromium; \
    curl -fsSLO "$base/${CHROMIUM_DEB}"; \
    curl -fsSLO "$base/${SANDBOX_DEB}"; \
    echo "${CHROMIUM_SHA256}  ${CHROMIUM_DEB}" | sha256sum -c -; \
    echo "${SANDBOX_SHA256}  ${SANDBOX_DEB}" | sha256sum -c -; \
    apt-get install -y --no-install-recommends "./${CHROMIUM_DEB}" "./${SANDBOX_DEB}"; \
    rm -f "${CHROMIUM_DEB}" "${SANDBOX_DEB}"; \
    rm -rf /var/lib/apt/lists/*

# Node pinned to the version the upstream job reads from .nvmrc.
RUN set -eux; \
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    echo "${NODE_SHA256}  node-v${NODE_VERSION}-linux-x64.tar.xz" | sha256sum -c -; \
    tar -xJf "node-v${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f "node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    node --version; npm --version

# The Chromium sandbox refuses to run as root, so every stage runs as this user.
RUN useradd -m -u 1000 runner && mkdir -p /npm-cache && chown runner:runner /npm-cache

COPY --chown=runner:runner . /workspace
WORKDIR /workspace
USER runner

ENV npm_config_cache=/npm-cache

# Populates the cache and leaves node_modules in the image: each stage runs in
# its own container, so the test stage cannot see what the build stage installs.
RUN npm ci

# The measured build stage runs the upstream commands unchanged, resolving only
# from the local cache.
ENV npm_config_offline=true

# Selects the ChromeHeadless launcher, the same one the hosted runner resolves;
# CHROMIUM_BIN is deliberately left unset to avoid a second launcher path.
ENV CHROME_BIN=/usr/bin/chromium
