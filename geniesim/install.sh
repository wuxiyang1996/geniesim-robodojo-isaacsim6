#!/usr/bin/env bash
# Install the Genie Sim 3 benchmark (the engine behind RoboColiseum) on Isaac Sim 6.1, natively
# (no Docker). Upstream runs it on Isaac Sim 5.1 in Docker; 5.1 crashes on NVIDIA R590/R595 drivers.
#
# Usage:
#   WORKDIR=/path/to/work bash geniesim/install.sh
# Environment variables (all optional):
#   WORKDIR      where genie_sim/ and GenieSimAssets/ are placed      (default: $PWD/geniesim_work)
#   ENV_NAME     conda env to create                                   (default: geniesim61)
#   SKIP_ASSETS  set to 1 to skip the ~28 GB asset download
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$HERE")"
WORKDIR=${WORKDIR:-$PWD/geniesim_work}
ENV_NAME=${ENV_NAME:-geniesim61}
GENIESIM_COMMIT=6ca11c7593ecf6b7dae58c28fd19f4a789a0dd46   # AgibotTech/genie_sim main, 2026-09-07
ISAACSIM_VERSION=6.1.0.0
mkdir -p "$WORKDIR"
export PYTHONNOUSERSITE=1 PIP_USER=0 GIT_LFS_SKIP_SMUDGE=1

# ---- 1. conda env + Isaac Sim 6.1 -------------------------------------------------------------
eval "$(conda shell.bash hook)"
conda env list | grep -q "^$ENV_NAME " || conda create -y -n "$ENV_NAME" python=3.12
conda activate "$ENV_NAME"
unset VIRTUAL_ENV   # an inherited venv would otherwise receive the packages
conda env config vars set PYTHONNOUSERSITE=1 >/dev/null
# git-lfs: the genie_sim repo uses LFS for a few files; ffmpeg: the episode recorder needs the binary
conda install -y -c conda-forge git-lfs ffmpeg

GLIBC=$(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+$')
if python -m pip show isaacsim 2>/dev/null | grep -q "^Version: $ISAACSIM_VERSION"; then
  echo "[install] isaacsim $ISAACSIM_VERSION already installed"
elif awk -v g="$GLIBC" 'BEGIN{exit !(g >= 2.35)}'; then
  python -m pip install "isaacsim[all,extscache]==$ISAACSIM_VERSION" --extra-index-url https://pypi.nvidia.com
else
  # glibc < 2.35 (RHEL/Rocky 9): pip refuses the manylinux_2_35 wheels; install them with uv's
  # platform override, then patch the few libraries that really need newer glibc.
  echo "[install] glibc $GLIBC < 2.35: installing with uv --python-platform x86_64-manylinux_2_35"
  python -m pip install -q uv
  uv pip install --python "$CONDA_PREFIX/bin/python" --python-platform x86_64-manylinux_2_35 \
    --extra-index-url https://pypi.nvidia.com --index-strategy unsafe-best-match \
    "isaacsim[all,extscache]==$ISAACSIM_VERSION"
  bash "$REPO_ROOT/rhel9/patch_glibc.sh"
  conda deactivate; conda activate "$ENV_NAME"   # pick up the libstdc++ hook
fi

# ---- 2. Python deps ------------------------------------------------------------------------
# The NGC isaac-sim image preinstalls numba/sklearn/h5py/pyarrow; pip-installed isaacsim does not.
# numba must match isaacsim-core's llvmlite==0.46.0 pin; keep numpy/websockets as isaacsim ships them.
NUMPY=$(python -c 'import numpy; print(numpy.__version__)')
WEBSOCKETS=$(python -c 'from importlib.metadata import version; print(version("websockets"))')
python -m pip install colorama cv-bridge future grasp_nms huggingface_hub msgpack msgpack-numpy openai \
  pyyaml shapely trimesh "numba==0.63.*" "llvmlite==0.46.0" scikit-learn h5py pyarrow \
  "numpy==$NUMPY" "websockets==$WEBSOCKETS"

# ---- 3. genie_sim at the tested commit + our patch -------------------------------------------
cd "$WORKDIR"
if [ ! -d genie_sim/.git ]; then
  git clone https://github.com/AgibotTech/genie_sim.git
fi
cd genie_sim
git checkout -q "$GENIESIM_COMMIT"
if git apply --check "$HERE/patches/0001-isaacsim-6.1-native.patch" 2>/dev/null; then
  git apply "$HERE/patches/0001-isaacsim-6.1-native.patch"
  echo "[install] applied 0001-isaacsim-6.1-native.patch"
else
  echo "[install] patch already applied (or does not apply; check 'git status')"
fi
python -m pip install 3rdparty/ik_solver-0.4.3-cp312-cp312-linux_x86_64.whl
python -m pip install --no-deps -e source/geniesim_cli -e source/geniesim_benchmark

# ---- 4. assets (~28 GB) --------------------------------------------------------------------
if [ "${SKIP_ASSETS:-0}" != 1 ]; then
  python - <<PY
from huggingface_hub import snapshot_download
snapshot_download("agibot-world/GenieSimAssets", repo_type="dataset",
                  local_dir="$WORKDIR/GenieSimAssets", max_workers=8)
PY
  python -m pip install --no-deps -e "$WORKDIR/GenieSimAssets"
fi

echo "[install] done. Check with:"
echo "  conda activate $ENV_NAME && GENIESIM_SKIP_AUTOBOOT=1 geniesim benchmark list"
