# Genie Sim (RoboColiseum) and RoboDojo on Isaac Sim 6.1

**Unofficial** install scripts and small patches that run two Isaac Sim–based robot-manipulation
benchmarks on **Isaac Sim 6.1**, natively (pip + conda, no Docker):

- [Genie Sim 3](https://github.com/AgibotTech/genie_sim) benchmark — the engine behind
  [RoboColiseum](https://robocoliseum.ai/) — see [`geniesim/`](geniesim/)
- [RoboDojo](https://github.com/RoboDojo-Benchmark/RoboDojo) with its own Isaac Lab 2.3 — see [`robodojo/`](robodojo/)

## Why

Both benchmarks pin **Isaac Sim 5.1**, which crashes in `librtx.scenedb.plugin.so` right after
"app ready" on NVIDIA **R590/R595** drivers — even on an empty stage, headless or not
([IsaacSim#648](https://github.com/isaac-sim/IsaacSim/discussions/648),
[RoboDojo#23](https://github.com/robodojo-benchmark/RoboDojo/issues/23),
[RoboDojo#24](https://github.com/robodojo-benchmark/RoboDojo/issues/24)).
If you cannot downgrade the driver (shared clusters, Blackwell GPUs), Isaac Sim 6.1 renders fine on
595.x, but neither benchmark runs on it out of the box. This repo closes that gap.

It does **not** redistribute upstream code, Isaac Sim, assets or checkpoints: the scripts clone the
upstream repositories at tested commits and apply the patches in this repo.

## Status

| Benchmark | Code changes | Validation on Isaac Sim 6.1 |
| --- | --- | --- |
| Genie Sim 3 (`geniesim/`) | 4 files | pi0.5 baseline, `g2op_if_pick_block_color`, 100 episodes: **0.86** vs **0.87** published (Isaac Sim 5.1) |
| RoboDojo (`robodojo/`) | 5 RoboDojo files + 14 Isaac Lab files | `demo_policy` smoke test passes (RoboDojo's criterion); pi0.5 seed 0 stacks the bowls in 2/2 `stack_bowls` episodes (pipeline check, not a benchmark number) |

Each subdirectory's README lists every change and why it is needed, the validation details, and the
known limitations (e.g. deformable objects in RoboDojo). Only the tasks listed there have been run.

## Quick start

```bash
git clone https://github.com/wuxiyang1996/geniesim-robodojo-isaacsim6.git && cd geniesim-robodojo-isaacsim6

# Genie Sim (RoboColiseum tasks)
WORKDIR=$HOME/geniesim_work bash geniesim/install.sh
WORKDIR=$HOME/geniesim_work bash geniesim/install_baseline.sh          # optional pi0.5 baseline
TASKS=g2op_if_pick_block_color SERVER=pi05 WORKDIR=$HOME/geniesim_work bash geniesim/run.sh

# RoboDojo
WORKDIR=$HOME/robodojo_work bash robodojo/install.sh
WORKDIR=$HOME/robodojo_work bash robodojo/run.sh                        # demo_policy smoke test
```

## Symptoms this repo fixes

Error messages we hit, verbatim, and where the fix lives. If you landed here by searching one of
them, the linked README explains the change.

**Isaac Sim 5.1 on NVIDIA R590/R595 drivers** (the reason to move to 6.1; no fix within 5.1).
Crash right after `app ready`, headless or not, even with an empty stage:
```
[Fatal] [carb.crashreporter-breakpad.plugin] 001: librtx.scenedb.plugin.so!void std::vector<std::tuple<char const*, float, float, unsigned int, unsigned int, unsigned int>, ...
[Fatal] [carb.crashreporter-breakpad.plugin] 004: librtx.scenedb.plugin.so!carbOnPluginStartup+0x3b4de (??:?)
Segmentation fault (core dumped)
```

**Genie Sim benchmark on Isaac Sim 6.1** → [`geniesim/`](geniesim/README.md#what-we-changed)
```
ModuleNotFoundError: No module named 'rclpy'
RuntimeError: rclpy still not available
RMW was not loaded
ModuleNotFoundError: No module named 'numba'
isaacsim-core 6.1.0.0 requires llvmlite==0.46.0, but you have llvmlite 0.49.0 which is incompatible.
FileNotFoundError: [Errno 2] No such file or directory: 'ffmpeg'
Unhandled exception in episode: create_connection() got an unexpected keyword argument 'ping_interval'
Unrecognized option 'vsync'.
[local_recorder] ffmpeg pipe broken for head
[local_recorder] stopped episode 0 → ... (0 frames across 3 cameras, ...)
```
Also silent: the table and objects are missing from the scene (robot moves in an empty room) because
`llm_task/*/scene.usda` reference `@/geniesim_assets/...`, the Docker mount point.

**RoboDojo (Isaac Lab 2.3) on Isaac Sim 6.1** → [`robodojo/`](robodojo/README.md#what-we-changed)
```
[Error] [omni.ext.plugin] [ext: isaacsim.asset.importer.urdf-2.4.31] failed to load native plugin
RuntimeError: Failed to acquire interface: isaacsim::asset::importer::urdf::Urdf (pluginName: nullptr)
ModuleNotFoundError: No module named 'omni.physics.tensors.impl'
ImportError: cannot import name 'acquire_physx_interface' from 'omni.physx'
ImportError: cannot import name 'create_mdl_material' from 'isaacsim.replicator.behavior.utils.scene_utils'
AttributeError: module 'pxr.PhysxSchema' has no attribute 'PhysxDeformableBodyAPI'
ModuleNotFoundError: No module named 'omegaconf'
PermissionError: [Errno 13] Permission denied: '/tmp/isaaclab/logs/isaaclab_....log'
[Error] [omni.rtx] VkResult: ERROR_OUT_OF_DEVICE_MEMORY      (simulator + pi0.5 on one 16 GB GPU)
```

**Isaac Sim 6.1 on glibc < 2.35 (RHEL/Rocky 9)** → [`rhel9/`](rhel9/README.md)
```
Unable to bootstrap inner kit kernel: /lib64/libstdc++.so.6: version `GLIBCXX_3.4.30' not found
Could not load the dynamic library from .../omni.usd.libs-.../bin/libusd_ts.so. Error: /lib64/libm.so.6: version `GLIBC_2.35' not found
```

## Layout

```
geniesim/   install.sh, install_baseline.sh, run.sh, hold_server.py, patches/, README.md
robodojo/   install.sh, install_pi05.sh, run.sh, patches/ (RoboDojo + Isaac Lab), README.md
rhel9/      patch_glibc.sh, weaken_verneed.py, README.md  (only for glibc < 2.35, e.g. RHEL/Rocky 9)
```

## Tested on

RHEL 9.8 (glibc 2.34), NVIDIA driver 595.71.05, RTX A4000 16 GB and RTX A6000 48 GB, conda,
Isaac Sim `6.1.0.0` from pypi.nvidia.com (Python 3.12, torch 2.11+cu130).
Ubuntu 22.04/24.04 (glibc ≥ 2.35) take the plain `pip install isaacsim` path in the scripts; that path
has not been tested by us. Issues and PRs welcome.

## Notes

- Scores obtained on Isaac Sim 6.1 are not official leaderboard results; the official
  RoboColiseum / RoboDojo boards use Isaac Sim 5.1.
- Other simulators that do not use Omniverse RTX (e.g. RoboTwin 2.0 on SAPIEN) run on R595 drivers
  without changes.
- License: MIT for the scripts and docs here. Patched upstream code stays under its upstream license.
  Not affiliated with AgiBot, the RoboDojo team, or NVIDIA.
