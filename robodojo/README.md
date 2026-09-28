# RoboDojo on Isaac Sim 6.1 (native, no Docker)

Unofficial. Runs [RoboDojo](https://github.com/RoboDojo-Benchmark/RoboDojo) on **Isaac Sim 6.1** while
keeping RoboDojo's own **Isaac Lab 2.3** (no Isaac Lab 3.0 migration, so no quaternion-convention or
API rewrite). Upstream pins Isaac Sim 5.1, which crashes in `librtx.scenedb.plugin.so` on NVIDIA
R590/R595 drivers ([RoboDojo#23](https://github.com/robodojo-benchmark/RoboDojo/issues/23),
[RoboDojo#24](https://github.com/robodojo-benchmark/RoboDojo/issues/24),
[IsaacSim#648](https://github.com/isaac-sim/IsaacSim/discussions/648)).

Tested commits (upstream's `install.sh` pulls submodules with `--remote`; we pin them):

| Repo | Commit |
| --- | --- |
| RoboDojo-Benchmark/RoboDojo | `726e9aa` |
| yuechen0614/IsaacLab (submodule, Isaac Lab 2.3.2) | `afca7b0` |
| yuechen0614/curobo (submodule, CuRobo v2) | `895c651` |
| XPolicyLab/XPolicyLab (submodule) | `d6332bf` (≥ `bb9a0b5`, the RGB channel fix) |

## Install

Requirements: NVIDIA RTX GPU (RT cores); **≥ 24 GB VRAM to run the simulator and pi0.5 on one card**
(16 GB is enough for the simulator alone, e.g. with `demo_policy`); a CUDA 13.x toolkit (`nvcc`) on
`PATH` for CuRobo; conda; `uv` for policies; ~110 GB disk (env, 39 GB assets, 12 GB pi0.5 params).

```bash
git clone https://github.com/wuxiyang1996/geniesim-robodojo-isaacsim6.git && cd geniesim-robodojo-isaacsim6
WORKDIR=$HOME/robodojo_work bash robodojo/install.sh        # env `robodojo61`, RoboDojo + patches, assets
WORKDIR=$HOME/robodojo_work bash robodojo/install_pi05.sh   # optional: XPolicyLab Pi_05 + seed-0 params
```

`install.sh` creates the conda env (Python 3.12), installs `isaacsim[all,extscache]==6.1.0.0`, clones
RoboDojo and its three submodules at the commits above, applies
[`patches/0001-robodojo-isaacsim-6.1.patch`](patches/0001-robodojo-isaacsim-6.1.patch) to RoboDojo and
[`patches/0002-isaaclab-isaacsim-6.1.patch`](patches/0002-isaaclab-isaacsim-6.1.patch) to
`third_party/IsaacLab`, installs Isaac Lab / RoboDojo / XPolicyLab / CuRobo (`[cu13]`) against a
constraints file that keeps Isaac Sim 6.1's numpy 2.3, torch 2.11+cu130 and warp 1.17, then runs the
upstream asset download. On glibc < 2.35 it uses [`../rhel9/patch_glibc.sh`](../rhel9/patch_glibc.sh).

## Run

```bash
# smoke test (RoboDojo's own criterion: exit 0 and _result.json with eval_time >= 1)
WORKDIR=$HOME/robodojo_work bash robodojo/run.sh
# pi0.5 (seed 0), 2 episodes of stack_bowls
POLICY=Pi_05 CKPT=RoboDojo-sim-arx_x5-joint-0 POLICY_ENV=uv EVAL_NUM=2 WORKDIR=$HOME/robodojo_work bash robodojo/run.sh
# two GPUs: policy on 1, simulator on 0
POLICY_GPU=1 ENV_GPU=0 POLICY=Pi_05 ... bash robodojo/run.sh
```

Any other XPolicyLab policy works the same way (`POLICY=<name>`, its checkpoint, its env).

## What we changed

### Isaac Lab 2.3 (`0002-isaaclab-isaacsim-6.1.patch`, 14 files)

| Change | Why |
| --- | --- |
| `apps/isaaclab.python.kit`: `"isaacsim.asset.importer.urdf" = {version = "2.4.31", exact = true}` → `{}` | the exact pin makes Kit fetch a 5.1-era native plugin from the registry that cannot load on 6.1 (`Failed to acquire interface: isaacsim::asset::importer::urdf::Urdf`). RoboDojo spawns robots from USD, so the bundled 3.x importer is fine |
| 12 files: `import omni.physics.tensors.impl.api as physx` → fall back to `omni.physics.tensors.api` | the `impl` package is gone in 6.1; `isaaclab_assets` / `isaaclab_tasks` failed to load |
| `assets/deformable_object/deformable_object_data.py`: `from __future__ import annotations` | an eagerly evaluated `physx.SoftBodyView` annotation (renamed `DeformableBodyView` in 6.1) broke `import isaaclab.assets` |
| `sim/utils/prims.py` `bind_physics_material`: look up `PhysxSchema.PhysxDeformableBodyAPI` with `getattr` | the API is gone in 6.1 (new deformable schema); every simulation init failed |

### RoboDojo (`0001-robodojo-isaacsim-6.1.patch`, 5 files)

| Change | Why |
| --- | --- |
| `env/environment/base_env.py`: `acquire_physx_interface()` → `get_physx_interface()` | `omni.physx` no longer exports `acquire_physx_interface`; `get_physx_interface` exists in 5.x and 6.x |
| new `env/scene_manager/objects/_isaacsim_compat.py`; `fluid.py`, `ground.py`, `table.py` import `create_mdl_material` from it | Isaac Sim 6 dropped `create_mdl_material` from `isaacsim.replicator.behavior.utils.scene_utils`; the compat module uses the original on 5.x and a verbatim copy of the 5.1 helper on 6.x |

### Environment (set by the scripts)

- Constraints keep numpy 2.3.1 / torch 2.11+cu130 / warp 1.17 / websockets 14.2 from Isaac Sim 6.1
  (Isaac Lab 2.3 asks for `numpy<2`, RoboDojo for torch cu128 and warp 1.11). `numba==0.63.*` for
  isaacsim-core's `llvmlite==0.46.0`. `omegaconf`, `hydra-core` (used by the eval client).
- CuRobo installed with the `cu13` extra. `ffmpeg` (conda-forge) for episode videos.
- `XLA_PYTHON_CLIENT_ALLOCATOR=platform` for the Pi_05 server, whose script pins a 30% memory fraction.
- `TMPDIR=<tmp>/robodojo-$USER`: Isaac Lab logs to `$TMPDIR/isaaclab/logs`; on a shared machine where
  another user already owns `/tmp/isaaclab`, environment creation fails with `PermissionError`.
- `uv` for policy envs runs with no conda env active and `VIRTUAL_ENV` pinned to the policy venv;
  otherwise `uv pip` installs openpi (torch 2.10, jax, ...) into the simulator env.

## Validation

| Check | Result |
| --- | --- |
| `demo_policy` (zero actions) on `stack_bowls`, 1 episode | exit 0, `_result.json` with `eval_time 1`, `success_rate 0.0` (expected); head/wrist videos 801 frames each, scene renders (table, three bowls, ARX X5 arms) |
| pi0.5 seed 0 on `stack_bowls`, 2 episodes | **2/2 success** (`success_rate 1.0`, `score 100`); head video shows both arms stacking the three bowls |

Hardware: RTX A4000 16 GB (demo_policy) / RTX A6000 48 GB (pi0.5), RHEL 9.8, driver 595.71.05.
Two episodes show that the policy path works on 6.1; they are not a success-rate estimate. The public
RoboDojo leaderboard reports pi0.5 only as dimension averages (overall score 11.41, success 6.91%), so a
per-task comparison is not possible; full-benchmark numbers have not been run.

## Known limitations

- **Deformable objects**: Isaac Sim 6.1 replaced the PhysX deformable schema. The patch only keeps
  imports and simulation init working; Isaac Lab's `DeformableObject` / deformable material spawners
  still reference the removed `PhysxSchema.PhysxDeformable*` APIs. Garment/cloth tasks
  (e.g. `fold_clothes`) are untested.
- Only `stack_bowls` has been run. Other tasks may hit further 5.1 → 6.1 API changes; the run log
  names the missing symbol, and most fixes follow the patterns above.
- Scores on 6.1 are not official leaderboard results (the leaderboard uses Isaac Sim 5.1).
