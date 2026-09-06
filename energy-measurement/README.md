# Energy measurement instrumentation

## Purpose

This directory is not part of the upstream Bootstrap repository. It was added
to measure the energy consumption of CI/CD pipeline commands on controlled
hardware, using Intel RAPL counters. The measured construct is the energy of
the CI commands on a controlled bench, not the energy of GitHub-hosted CI in
production.

## Non-invasiveness

No original project file is created or modified. The only additions are this
directory and `.github/workflows/energy-measurement.yml`. Verify against the
upstream commit this fork is instrumented on:

```bash
git diff --stat 12cb8b902d175a0d612f1280f58b386a09921a16
```

## What is measured

Energy is read from the Intel RAPL counters under
`/sys/class/powercap/intel-rapl`, for four domains: package (`pkg`), cores,
uncore (reported as `gpu`, structurally zero on this bench) and DRAM (`ram`).
Counter deltas are overflow-corrected against `max_energy_range_uj`, read from
sysfs at run time rather than hardcoded.

Each run measures a 120 s idle baseline first and derives a per-second rate per
domain. Reported energy per stage is

```
net = max(raw_delta - baseline_rate * wall_time_s, 0)
```

The clamp at zero prevents a negative DRAM figure on light memory workloads;
the unclamped DRAM value is kept as the diagnostic column
`energy_ram_liquid_raw_j`. The baseline rate used in the subtraction is recorded
in every row (`baseline_rate_*_w`).

`wall_time_s` covers the whole `docker run --rm` lifecycle, including container
setup and teardown, because the RAPL reading window covers the same interval.

Per-stage CPU time is captured inside the container: file descriptor 3
preserves the workload's stderr while `time` writes to `/timing`, so the CPU
time of child processes is attributed to the stage instead of to the host
`docker` client.

The exit code of each stage container is written to
`runs/exit_codes_run_NN.txt`. It is the only rejection criterion for a run; the
measurement is kept either way.

## How to run

```bash
docker build -t bootstrap-medicao -f energy-measurement/Dockerfile .
bash energy-measurement/run_pipeline.sh 1
```

The workflow runs the same script on a self-hosted runner, dispatched manually:

```bash
gh workflow run energy-measurement.yml -f campaign=validation   # run 0 only
gh workflow run energy-measurement.yml -f campaign=full         # warm-up + 10 runs + median
```

`full` refuses to start when `runs/` already holds a run CSV: a campaign is one
continuous session, and no earlier result is reused.

## Stages

Each stage runs in its own container from the repository root, so build
artifacts do not survive into the later stages; the image itself carries the
`node_modules` that `test` uses (D9). Commands are copied verbatim from the
upstream workflow `.github/workflows/js.yml`, job `run` (`ubuntu-latest`, Node
from `.nvmrc`). This is a non-ML project, so there are two stages and no
`train`.

| stage | upstream steps | `js.yml` lines |
|---|---|---|
| `build` | "Install npm dependencies", "Run dist" | 38, 41 |
| `test` | "Run JS tests" | 44 |

Left out: the Coveralls step (46-51), which is an action rather than a `run:`
command and is already disabled on forks upstream, and the `checkout` and
`setup-node` steps (26-35). The other CI workflows of the project are out of
scope: `css.yml`, `lint.yml`, `docs.yml`, `cspell.yml`, `linkinator.yml`,
`node-sass.yml`, and the two that require external credentials,
`bundlewatch.yml` and `browserstack.yml`.

## Deviations from the upstream pipeline

| id | deviation | reason |
|---|---|---|
| D1 | The npm cache is populated at image build time and the measured `build` stage runs `npm ci` unchanged, resolving offline through `npm_config_cache=/npm-cache` and `npm_config_offline=true` set in the image. The lockfile pins all 1519 packages with sha512 `integrity`, which `npm ci` re-verifies on install, so the pre-baked cache is self-verifying. | Measured containers run with `--network none`; RAPL has no network domain. |
| D2 | `actions/setup-node` with `node-version-file: .nvmrc` and `cache: npm` is replaced by Node 24.18.0 unpacked into the image from the official tarball, pinned by sha256. | The version is the one `.nvmrc` declares; the download and cache restore leave the measured window. |
| D3 | The hosted runner's preinstalled Google Chrome is replaced by Debian bookworm's Chromium 152.0.7977.82, installed from `.deb` files pinned by sha256. `CHROME_BIN` points at it and `CHROMIUM_BIN` is left unset, so `karma-detect-browsers` reports `Chrome` and the upstream `postDetection` selects `ChromeHeadless`, the same launcher and flags the hosted runner resolves. | Chrome stable does not keep older releases downloadable, which would break the reproduction package. Only the binary differs; the karma code path does not. |
| D4 | The Coveralls step is not executed. | It is an action rather than a command, and `js.yml:48` already disables it on forks. |
| D5 | `ubuntu-latest` is replaced by `debian:bookworm-slim` pinned by digest, under `docker run --privileged --network none --memory=12g --memory-swap=12g`. | Dedicated bench. |
| D6 | The fork is pinned to `main`; upstream is migrating the JS test job to Playwright on `v6-dev`. | The measured commit is fixed, so the measurement is well defined; the divergence is recorded rather than tracked. |
| D9 | The image ships `node_modules` installed by the same `npm ci`, and the measured `build` stage reinstalls it: `npm ci` removes an existing `node_modules` before writing a new one, so the measured install is complete rather than a no-op. | Each stage runs in its own container; `test` needs the packages the upstream job had installed in the same runner. The cost is one recursive removal that the hosted runner does not pay, since `setup-node` restores the cache and never `node_modules`. |

Every stage container runs as the non-root user `runner`, because the Chromium
sandbox refuses to start as root and `karma-chrome-launcher` passes no
`--no-sandbox` to fall back on. With the `chromium-sandbox` package installed,
the real sandbox starts and no browser flag is added.

## Output schema

One CSV per run, one row per stage plus a `total` row:

```
run, stage, energy_pkg_j, energy_cores_j, energy_gpu_j, energy_ram_j,
wall_time_s, user_time_s, sys_time_s, energy_ram_liquid_raw_j,
wall_time_container_s, baseline_rate_pkg_w, baseline_rate_cores_w,
baseline_rate_ram_w
```

The first nine columns are the official schema shared by every project in the
study; the remaining five are diagnostic. `baseline_rate_*_w` is the idle rate
(W) subtracted in that run, repeated in every row.

## Reproducibility notes

Bench: Intel Core i7-9700 (8 cores, no SMT), 16 GB RAM, Crucial BX500 SATA SSD,
Ubuntu 24.04 LTS, kernel 6.8.0, Docker 29.x.

Container flags: `--rm --privileged --network none --memory=12g --memory-swap=12g`.

Both stages inherit the upstream parallelism settings without override. Every
fan-out is a fixed literal in `package.json` rather than a function of the core
count: `npm-run-all --parallel` over 4 then 3 tasks in `build`, and over 4 tasks
in `test`, with one headless browser per Karma instance. The bench resolves the
same numbers a GitHub-hosted runner does, so no parallelism divergence is
introduced.
