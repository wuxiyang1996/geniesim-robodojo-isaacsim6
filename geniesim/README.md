# Genie Sim 3 benchmark on Isaac Sim 6.1 (native, no Docker)

Unofficial. Runs the [Genie Sim](https://github.com/AgibotTech/genie_sim) benchmark — the engine behind
[RoboColiseum](https://robocoliseum.ai/) — on **Isaac Sim 6.1**, installed with pip into a conda env.
Upstream runs it in a Docker image built on Isaac Sim 5.1, which crashes on NVIDIA R590/R595 drivers.

Tested upstream commit: `AgibotTech/genie_sim@6ca11c7` (main, 2026-09-07).

## Install

Requirements: NVIDIA RTX GPU (RT cores; A100/H100 cannot render), a driver that Isaac Sim 6.1 supports
(tested on 595.71.05), conda, git, ~70 GB disk (env ~25 GB, assets ~28 GB, pi0.5 checkpoint ~12 GB).

```bash
git clone https://github.com/wuxiyang1996/geniesim-robodojo-isaacsim6.git && cd geniesim-robodojo-isaacsim6
WORKDIR=$HOME/geniesim_work bash geniesim/install.sh            # env `geniesim61` + genie_sim + patch + assets
WORKDIR=$HOME/geniesim_work bash geniesim/install_baseline.sh   # optional: official pi0.5 baseline (needs uv)
```

`install.sh` creates the conda env (Python 3.12), installs `isaacsim[all,extscache]==6.1.0.0`, the extra
Python packages the benchmark needs, clones genie_sim at the tested commit, applies
[`patches/0001-isaacsim-6.1-native.patch`](patches/0001-isaacsim-6.1-native.patch), installs the
`ik_solver` cp312 wheel shipped in `3rdparty/`, and downloads `agibot-world/GenieSimAssets`.
On hosts with glibc < 2.35 (RHEL/Rocky 9) it installs Isaac Sim with uv's platform override and runs
[`../rhel9/patch_glibc.sh`](../rhel9/patch_glibc.sh).

## Run

```bash
# bring-up check: robot holds still, every episode scores 0, but the whole loop runs
TASKS="g2op_if_pick_block_color" SERVER=hold WORKDIR=$HOME/geniesim_work bash geniesim/run.sh
# official pi0.5 baseline
TASKS="g2op_if_pick_block_color" SERVER=pi05 WORKDIR=$HOME/geniesim_work bash geniesim/run.sh
# your own policy: serve the corobot protocol on 127.0.0.1:8999, then
TASKS="g2op_if_pick_block_color" SERVER=external WORKDIR=$HOME/geniesim_work bash geniesim/run.sh
```

List tasks with `GENIESIM_SKIP_AUTOBOOT=1 geniesim benchmark list` (86 configs: robust 50, if 10,
manip 10, s2r 8, spatial 8). Results go to
`$WORKDIR/genie_sim/output/benchmark/<task>/<sub_task>/evaluate_ret_*.json`, with per-episode videos.
The protocol is documented upstream in `source/geniesim_benchmark/USAGE.md`.

## What we changed

### Code (the patch, 4 files)

| File | Change | Why |
| --- | --- | --- |
| `app/geniesim.exp.kit` | comment out `omni.pip.compute`, `omni.isaac.core_archive` | 5.1 pip-archive extensions that do not exist in 6.1; the other 37 kit dependencies do (7 under `extsDeprecated`, already listed as an extension folder) |
| `utils/comm/websocket_client.py` | `ws_connect_compat` drops `ping_interval`/`ping_timeout` when `websockets.sync.client.connect` cannot take them | isaacsim-kernel 6.1 pins `websockets<15`; 14.x forwards unknown kwargs to `socket.create_connection` → `unexpected keyword argument 'ping_interval'` on every episode |
| `plugins/output_system/local_recorder.py` | `-vsync 0` → `-fps_mode passthrough` | `-vsync` was removed in ffmpeg 7; conda-forge ships 9.x. Same meaning, works on ffmpeg ≥ 5.1. Without it every video has 0 frames |
| `benchmark/subscene_override.py` | if `/geniesim_assets` does not exist, load a copy of the task scene with `@/geniesim_assets/` rewritten to the local asset root (`$GENIESIM_ASSETS_PATH` or `geniesim_assets.ASSETS_PATH`) | the pre-generated `llm_task/*/N/scene.usda` files reference the Docker mount point. Natively the table and objects silently fail to load (USD diagnostics are muted) and the robot acts in an empty room. No-op inside the Docker image |

### Environment (set by `install.sh` / `run.sh`, no code change)

- `numba==0.63.*` + `llvmlite==0.46.0`, `scikit-learn`, `h5py`, `pyarrow`: preinstalled in the NGC image,
  not in pip-installed Isaac Sim. isaacsim-core pins `llvmlite==0.46.0`; newer numba pulls 0.49.
- `ffmpeg` binary (conda-forge) for the episode recorder.
- `ROS_DISTRO=jazzy`, `RMW_IMPLEMENTATION=rmw_fastrtps_cpp`, `LD_LIBRARY_PATH += <isaacsim>/exts/isaacsim.ros2.core/jazzy/lib`:
  `app.py` imports `rclpy` at startup (ROS stays off, `app.enable_ros=false`). Isaac Sim 6.1 ships a
  Jazzy rclpy; without `ROS_DISTRO` the bridge looks for Humble and the import fails.
- `GENIESIM_SKIP_AUTOBOOT=1`: the CLI refuses to run without `geniesim_ros`, which the benchmark does not use.
- `GENIESIM_KIT_RUNTIME_DIR` / `GENIESIM_OMNI_DOCUMENTS_DIR`: default is the Docker path `/workspace`.

## Validation

| Task | Policy | Episodes | Ours (Isaac Sim 6.1) | Published (Isaac Sim 5.1) |
| --- | --- | --- | --- | --- |
| `g2op_if_pick_block_color` | pi0.5 (`instruction_and_robust_pi05`) | 100 | average **0.86**, end-to-end 0.73 | 0.87 |

Single run on an RTX A4000 16 GB (sim and pi0.5 on one card), RHEL 9.8, driver 595.71.05.
The published number is from the upstream README leaderboard; which statistic it reports is not stated
(`eval_utils.py` reports `average`, the mean of step scores, as the headline). Step scores: Follow 0.99,
PickUpOnGripper 0.73; right-arm instances 0.94 end-to-end, left-arm 0.52.
Other tasks and boards have not been validated yet.

## Gotchas

- `geniesim benchmark run` exits 0 even when `app.py` raises: read the log and `evaluate_ret_*.json`.
- USD diagnostics are muted: if objects are missing, check the episode videos, not only the log.
- pi0.5 (~7 GB) and the simulator fit on one 16 GB card with `PI05_MEM_FRACTION=0.45`.
