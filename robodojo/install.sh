#!/usr/bin/env bash
# Install RoboDojo on Isaac Sim 6.1 (native, no Docker), keeping RoboDojo's own Isaac Lab 2.3.
# Upstream pins Isaac Sim 5.1, which crashes on NVIDIA R590/R595 drivers.
#
# Usage:
#   WORKDIR=/path/to/work bash robodojo/install.sh
# Environment variables (all optional):
#   WORKDIR      where RoboDojo/ is cloned                          (default: $PWD/robodojo_work)
#   ENV_NAME     conda env to create                                (default: robodojo61)
#   SKIP_ASSETS  set to 1 to skip the ~39 GB asset download
# Needs a CUDA 13.x toolkit (nvcc) on PATH for CuRobo, matching torch 2.11+cu130 from Isaac Sim 6.1.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$HERE")"
WORKDIR=${WORKDIR:-$PWD/robodojo_work}
ENV_NAME=${ENV_NAME:-robodojo61}
ISAACSIM_VERSION=6.1.0.0
# Tested commits (upstream install.sh uses `git submodule update --remote`, i.e. whatever is latest)
ROBODOJO_COMMIT=726e9aabfaa642203722eb126f5eaf0f37f3e1ad      # robodojo-benchmark/RoboDojo main, 2026-09-20
ISAACLAB_COMMIT=afca7b09d60d8beb9c1cb28b43066499940b969b      # yuechen0614/IsaacLab (Isaac Lab 2.3.2 fork)
CUROBO_COMMIT=895c6517243f8cb091c73c018c8167192d39599a        # yuechen0614/curobo (CuRobo v2)
XPOLICYLAB_COMMIT=d6332bf10b15dda007efdd17e5f64fc5e1d3d19f    # XPolicyLab/XPolicyLab main (>= bb9a0b5 RGB fix)
mkdir -p "$WORKDIR"
export PYTHONNOUSERSITE=1 PIP_USER=0 GIT_LFS_SKIP_SMUDGE=1

# ---- 1. conda env + Isaac Sim 6.1 -------------------------------------------------------------
eval "$(conda shell.bash hook)"
conda env list | grep -q "^$ENV_NAME " || conda create -y -n "$ENV_NAME" python=3.12
conda activate "$ENV_NAME"
unset VIRTUAL_ENV
conda env config vars set PYTHONNOUSERSITE=1 >/dev/null
conda install -y -c conda-forge git-lfs ffmpeg      # ffmpeg: utils/save_file.py writes episode videos
GLIBC=$(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+$')
if python -m pip show isaacsim 2>/dev/null | grep -q "^Version: $ISAACSIM_VERSION"; then
  echo "[install] isaacsim $ISAACSIM_VERSION already installed"
elif awk -v g="$GLIBC" 'BEGIN{exit !(g >= 2.35)}'; then
  python -m pip install "isaacsim[all,extscache]==$ISAACSIM_VERSION" --extra-index-url https://pypi.nvidia.com
else
  echo "[install] glibc $GLIBC < 2.35: installing with uv --python-platform x86_64-manylinux_2_35"
  python -m pip install -q uv
  uv pip install --python "$CONDA_PREFIX/bin/python" --python-platform x86_64-manylinux_2_35 \
    --extra-index-url https://pypi.nvidia.com --index-strategy unsafe-best-match \
    "isaacsim[all,extscache]==$ISAACSIM_VERSION"
  bash "$REPO_ROOT/rhel9/patch_glibc.sh"
  conda deactivate; conda activate "$ENV_NAME"
fi

# Keep Isaac Sim 6.1's stack: Isaac Lab 2.3 asks for numpy<2, RoboDojo for torch cu128 / warp 1.11.
CONS="$WORKDIR/isaacsim61_constraints.txt"
python - > "$CONS" <<'PY'
from importlib.metadata import version
for p in ["numpy", "torch", "torchvision", "warp-lang", "websockets", "pillow", "llvmlite", "isaacsim"]:
    try: print(f"{p}=={version(p)}")
    except Exception: pass
PY
PIP="python -m pip install -c $CONS"

# ---- 2. RoboDojo + submodules at the tested commits + our patches ----------------------------
cd "$WORKDIR"
[ -d RoboDojo/.git ] || git clone https://github.com/RoboDojo-Benchmark/RoboDojo.git
cd RoboDojo
git checkout -q "$ROBODOJO_COMMIT"
git submodule update --init third_party/IsaacLab third_party/curobo XPolicyLab
git -C third_party/IsaacLab fetch -q origin "$ISAACLAB_COMMIT" && git -C third_party/IsaacLab checkout -q "$ISAACLAB_COMMIT"
git -C third_party/curobo fetch -q origin "$CUROBO_COMMIT" && git -C third_party/curobo checkout -q "$CUROBO_COMMIT"
git -C XPolicyLab fetch -q origin "$XPOLICYLAB_COMMIT" && git -C XPolicyLab checkout -q "$XPOLICYLAB_COMMIT"
apply() { if git -C "$1" apply --check "$2" 2>/dev/null; then git -C "$1" apply "$2"; echo "[install] applied $(basename "$2")"; else echo "[install] $(basename "$2") already applied (or does not apply; check git status in $1)"; fi; }
apply . "$HERE/patches/0001-robodojo-isaacsim-6.1.patch"
apply third_party/IsaacLab "$HERE/patches/0002-isaaclab-isaacsim-6.1.patch"

# ---- 3. Python deps ------------------------------------------------------------------------
# Isaac Lab 2.3 setup.py requirements (minus numpy<2 / torch pins) + RoboDojo requirements.
$PIP onnx prettytable==3.3.0 toml hidapi gymnasium==1.2.1 trimesh "pyglet<2" transformers==4.57.6 einops \
     starlette flatdict==4.0.0 packaging tensorboard "protobuf>=4.25.8,!=5.26.0" "numba==0.63.*" \
     huggingface_hub transforms3d open3d msgpack-numpy scikit-learn h5py omegaconf hydra-core
$PIP --no-deps $(for p in isaaclab isaaclab_assets isaaclab_contrib isaaclab_mimic isaaclab_rl isaaclab_tasks; do printf -- "-e third_party/IsaacLab/source/%s " "$p"; done)
$PIP --no-deps -e XPolicyLab
# CuRobo v2 with the CUDA 13 extra (Isaac Sim 6.1 brings torch 2.11+cu130)
export TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST:-"8.6;8.9"} FORCE_CUDA=1
( cd third_party/curobo && $PIP -e ".[cu13]" --no-build-isolation )

# ---- 4. assets (~39 GB) ----------------------------------------------------------------------
if [ "${SKIP_ASSETS:-0}" != 1 ]; then
  bash scripts/init_assets.sh
  python utils/update_embodiment_config_path.py
fi
echo "[install] done. Smoke test: WORKDIR=$WORKDIR bash $HERE/run.sh"
