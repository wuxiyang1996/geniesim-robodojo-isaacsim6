#!/usr/bin/env bash
# Install XPolicyLab's Pi_05 policy server for RoboDojo and the official RoboDojo pi0.5 checkpoint
# (seed 0, inference params only: ~11.6 GB instead of ~65 GB for all seeds + train_state).
# The policy runs in its own uv venv (XPolicyLab/policy/Pi_05/openpi/.venv), not in the sim env.
#
# Usage:  WORKDIR=/path/to/work bash robodojo/install_pi05.sh
set -euo pipefail
WORKDIR=${WORKDIR:-$PWD/robodojo_work}
ENV_NAME=${ENV_NAME:-robodojo61}
PI=$WORKDIR/RoboDojo/XPolicyLab/policy/Pi_05
command -v uv >/dev/null || { echo "install uv first: https://docs.astral.sh/uv/"; exit 1; }

# uv installs into $VIRTUAL_ENV, else the *active conda env*, else ./.venv. Run the upstream
# install.sh with no conda env active and VIRTUAL_ENV pinned to the policy venv, otherwise openpi's
# dependencies (torch, jax, ...) land in the simulator env.
( cd "$PI" && env -u CONDA_PREFIX -u CONDA_DEFAULT_ENV VIRTUAL_ENV="$PI/openpi/.venv" bash install.sh )

eval "$(conda shell.bash hook)"; conda activate "$ENV_NAME"
python - <<PY
from huggingface_hub import snapshot_download
run = "ckpt/RoboDojo/Pi_05/RoboDojo-sim-arx_x5-joint-0/59999"
snapshot_download("RoboDojo-Benchmark/RoboDojo", repo_type="dataset",
                  local_dir="$WORKDIR/RoboDojo/.cache/robodojo_ckpt_repo",
                  allow_patterns=[f"{run}/params/**", f"{run}/assets/**", f"{run}/_CHECKPOINT_METADATA"])
PY
[ -e "$PI/checkpoints" ] || ln -s "$WORKDIR/RoboDojo/.cache/robodojo_ckpt_repo/ckpt/RoboDojo/Pi_05" "$PI/checkpoints"
echo "[pi05] ready. Run: POLICY=Pi_05 CKPT=RoboDojo-sim-arx_x5-joint-0 POLICY_ENV=uv WORKDIR=$WORKDIR bash robodojo/run.sh"
