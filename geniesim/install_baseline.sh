#!/usr/bin/env bash
# Install the official Genie Sim pi0.5 baseline inference server (ACoT-VLA, agibot_world_challenge
# branch) and one board checkpoint from ModelScope. Runs in its own uv venv, separate from the sim env.
#
# Usage:
#   WORKDIR=/path/to/work bash geniesim/install_baseline.sh [instruction_and_robust_pi05|manipulation_pi05|spatial_pi05]
# Board -> checkpoint: instruction/robust -> instruction_and_robust_pi05, manip -> manipulation_pi05,
# spatial -> spatial_pi05 (each ~11.6 GB). run.sh defaults to instruction_and_robust_pi05.
set -euo pipefail
WORKDIR=${WORKDIR:-$PWD/geniesim_work}
CKPT=${1:-instruction_and_robust_pi05}
ACOT_COMMIT=9ded4eb   # Anonymous-694/ACoT-VLA agibot_world_challenge, 2026-07-17
mkdir -p "$WORKDIR"; cd "$WORKDIR"
export GIT_LFS_SKIP_SMUDGE=1 UV_LINK_MODE=copy
command -v uv >/dev/null || { echo "install uv first: https://docs.astral.sh/uv/"; exit 1; }
[ -d ACoT-VLA/.git ] || git clone -b agibot_world_challenge https://github.com/Anonymous-694/ACoT-VLA.git
cd ACoT-VLA
git checkout -q "$ACOT_COMMIT"
# uv installs into $VIRTUAL_ENV, else the *active conda env*, else ./.venv - pin it to ./.venv
env -u CONDA_PREFIX VIRTUAL_ENV="$PWD/.venv" uv sync
env -u CONDA_PREFIX VIRTUAL_ENV="$PWD/.venv" uv pip install modelscope
[ -d "checkpoints/$CKPT/params" ] || PATH="$PWD/.venv/bin:$PATH" bash scripts/download_checkpoint.sh "$CKPT" "$PWD/checkpoints"
echo "[baseline] ready: $WORKDIR/ACoT-VLA/checkpoints/$CKPT"
