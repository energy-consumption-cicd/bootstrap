# Energy measurement instrumentation (release 5.2.0)

## Purpose

This directory is not part of the upstream Bootstrap repository. It was added
to measure the energy consumption of CI/CD pipeline commands on controlled
hardware, using Intel RAPL counters. The measured construct is the energy of
the CI commands on a controlled bench, not the energy of GitHub-hosted CI in
production.

## Non-invasiveness

No original project file is created or modified. The only additions are this
directory and `.github/workflows/energy-measurement.yml`. This branch is the upstream
tag `v5.2.0` plus one instrumentation commit; verify with:

```bash
git diff --stat v5.2.0 release-5.2.0
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

From the root of a clone of branch `release-5.2.0` (the Dockerfile copies the tree):

```bash
docker build -t bootstrap-measurement-5.2.0 -f energy-measurement/Dockerfile .
bash energy-measurement/run_pipeline.sh 1
```

The workflow runs the same script on a self-hosted runner, dispatched manually:

```bash
gh workflow run energy-measurement.yml --ref release-5.2.0 -f campaign=validation   # run 0 only
gh workflow run energy-measurement.yml --ref release-5.2.0 -f campaign=full         # warm-up + 10 runs + median
```

`full` refuses to start when `runs/` already holds a run CSV: a campaign is one
continuous session, and no earlier result is reused.

## Stages

Each stage runs in its own container from the repository root, so build
artifacts do not survive into the later stages; the image itself carries the
`node_modules` that `test` uses (D9). Commands are copied verbatim from the
upstream workflow `.github/workflows/js.yml` at tag `v5.2.0`, job `run` (`ubuntu-latest`, `env.NODE: 16`). This is a non-ML project, so there are two stages and no
`train`.

| stage | upstream steps | `js.yml` lines |
|---|---|---|
| `build` | "Install npm dependencies", "Run dist" | 30, 33 |
| `test` | "Run JS tests" | 36 |

Left out: the Coveralls step (line 39), which is an action rather than a `run:` command, and
the `checkout` and `setup-node` steps. The other CI workflows of the project are out of scope.

## Deviations from the upstream pipeline

| id | deviation | reason |
|---|---|---|
| D1 | The npm cache is populated at image build time and the measured `build` stage runs `npm ci` unchanged, resolving offline through `npm_config_cache=/npm-cache` and `npm_config_offline=true` set in the image. The lockfile pins all 872 packages with sha512 `integrity`, which `npm ci` re-verifies on install, so the pre-baked cache is self-verifying. | Measured containers run with `--network none`; RAPL has no network domain. |
| D2 | `actions/setup-node` is replaced by Node 16.16.0 (npm 8.11.0) unpacked into the image from the official tarball, pinned by sha256. | The version is the `NODE: 16` of the workflow, as the runner tool cache resolved it on the tag date; the download and cache restore leave the measured window. |
| D3 | The hosted runner's preinstalled Google Chrome is replaced by Debian 11's Chromium 103.0.5060.114 (the version of the Chrome preinstalled on the hosted runner on the tag date), with `chromium-common` and `chromium-sandbox`, installed from `.deb` files of snapshot.debian.org pinned by sha256. `CHROME_BIN` points at it and `CHROMIUM_BIN` is left unset, so `karma-detect-browsers` reports `Chrome` and the upstream `postDetection` selects `ChromeHeadless`, the same launcher and flags the hosted runner resolves. | Chrome stable does not keep older releases downloadable, which would break the reproduction package. Only the binary differs; the karma code path does not. |
| D4 | The Coveralls step is not executed. | It is an action rather than a command and needs a token. |
| D5 | `ubuntu-latest` is replaced by `debian:bullseye-20220711-slim` pinned by digest, with apt resolved from snapshot.debian.org at a fixed date, under `docker run --privileged --network none --memory=12g --memory-swap=12g`. | Dedicated bench. |
| D6 | The branch is pinned to the release tag `v5.2.0`. | The measured commit is fixed. |
| D9 | The image ships `node_modules` installed by the same `npm ci`, and the measured `build` stage reinstalls it: `npm ci` removes an existing `node_modules` before writing a new one, so the measured install is complete rather than a no-op. | Each stage runs in its own container; `test` needs the packages the upstream job had installed in the same runner. The cost is one recursive removal that the hosted runner does not pay, since `setup-node` restores the cache and never `node_modules`. |
| D10 | `/etc/nsswitch.conf` of the image resolves hosts from files only. | The `hugo-bin` postinstall of this tag downloads Hugo inside `npm ci`; offline, DNS failures would be retried with backoff (about 6 s of idle wall). With files only the download fails at once, as it fails in any case without network; no command changes. |

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
(W) subtracted in that run, repeated in every row. Host swap counters and the
package temperature (hwmon `coretemp`, `Package id 0`) are read immediately
before and after each stage's RAPL window, never inside it, into
`swap_run_NN_<stage>.txt` and `temp_run_NN_<stage>.txt`.

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
