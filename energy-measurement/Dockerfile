# The npm cache and node_modules are populated at image build time so the
# measured stages can run with --network none.
# debian:bullseye-20220711-slim (linux/amd64): the Chromium packages of the tag
# date are Debian 11 builds and depend on Debian 11 libraries.
FROM debian@sha256:f52f9aebdd310d504e0995601346735bb14da077c5d014e9f14017dadc915fe5

# Debian 11 is resolved from snapshot.debian.org at a fixed date; the archived
# Release files are past Valid-Until.
ARG DEBIAN_SNAPSHOT=20220719T000000Z
RUN set -eux; \
    printf 'deb http://snapshot.debian.org/archive/debian/%s bullseye main\ndeb http://snapshot.debian.org/archive/debian-security/%s bullseye-security main\n' \
      "$DEBIAN_SNAPSHOT" "$DEBIAN_SNAPSHOT" > /etc/apt/sources.list; \
    apt-get -o Acquire::Check-Valid-Until=false update; \
    apt-get install -y --no-install-recommends ca-certificates curl xz-utils; \
    rm -rf /var/lib/apt/lists/*

# The Chromium sandbox refuses to run as root, so every stage runs as this user.
RUN useradd -m -u 1000 runner && mkdir -p /npm-cache && chown runner:runner /npm-cache

ARG CHROMIUM_VERSION=103.0.5060.114-1~deb11u1
ARG CHROMIUM_POOL=http://snapshot.debian.org/archive/debian-security/20220711T174901Z/pool/updates/main/c/chromium
ARG CHROMIUM_SHA256=fc5b2a51df4cdd4bd641b8fb5a761c714683b7eda951b630ce5c1a349aef6cfd
ARG COMMON_SHA256=616212cc185e52e42c5b394a7a58770cdd14b1079819c0c41f539930745c959a
ARG SANDBOX_SHA256=5b0d03f3d662ad2486b8079788fbf1f95da499689a492744a6b73c35dc61e10d

# chromium-sandbox ships the SUID helper; without it the browser refuses to
# start and karma-chrome-launcher passes no --no-sandbox to fall back on.
RUN set -eux; \
    for p in chromium chromium-common chromium-sandbox; do \
      curl -fsSL -o "${p}.deb" "${CHROMIUM_POOL}/${p}_${CHROMIUM_VERSION}_amd64.deb"; \
    done; \
    echo "${CHROMIUM_SHA256}  chromium.deb" | sha256sum -c -; \
    echo "${COMMON_SHA256}  chromium-common.deb" | sha256sum -c -; \
    echo "${SANDBOX_SHA256}  chromium-sandbox.deb" | sha256sum -c -; \
    apt-get -o Acquire::Check-Valid-Until=false update; \
    apt-get install -y --no-install-recommends ./chromium.deb ./chromium-common.deb ./chromium-sandbox.deb; \
    rm -f chromium.deb chromium-common.deb chromium-sandbox.deb; \
    rm -rf /var/lib/apt/lists/*

# Node pinned to the version setup-node resolved for `node-version: 16` at the
# tag date (runner tool cache, ubuntu20/20220710.1 and 20220717.1).
ARG NODE_VERSION=16.16.0
ARG NODE_SHA256=edcb6e9bb049ae365611aa209fc03c4bfc7e0295dbcc5b2f1e710ac70384a8ec
RUN set -eux; \
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    echo "${NODE_SHA256}  node-v${NODE_VERSION}-linux-x64.tar.xz" | sha256sum -c -; \
    tar -xJf "node-v${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f "node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    node --version; npm --version

COPY --chown=runner:runner . /workspace
WORKDIR /workspace
USER runner

ENV npm_config_cache=/npm-cache

# Populates the cache and leaves node_modules in the image: each stage runs in
# its own container, so the test stage cannot see what the build stage installs.
RUN npm ci

# Name lookups fail at once offline; the hugo-bin postinstall of the tag would otherwise
# back off on EAI_AGAIN for about 6 s inside the measured npm ci.
USER root
RUN sed -i 's/^hosts:.*/hosts: files/' /etc/nsswitch.conf
USER runner

# The measured build stage runs the upstream commands unchanged, resolving only
# from the local cache.
ENV npm_config_offline=true

# Selects the ChromeHeadless launcher, the same one the hosted runner resolves;
# CHROMIUM_BIN is deliberately left unset to avoid a second launcher path.
ENV CHROME_BIN=/usr/bin/chromium
