#!/usr/bin/env bash
# Evaluate a policy on one RoboDojo task on Isaac Sim 6.1 (wraps `scripts/robodojo.sh eval`).
#
# Usage:
#   WORKDIR=/path/to/work bash robodojo/run.sh                      # demo_policy smoke test on stack_bowls
#   POLICY=Pi_05 CKPT=RoboDojo-sim-arx_x5-joint-0 POLICY_ENV=uv EVAL_NUM=2 WORKDIR=... bash robodojo/run.sh
# Environment variables:
#   TASK (stack_bowls), POLICY (demo_policy), CKPT (demo), POLICY_ENV (the sim env; `uv` for Pi_05),
#   EVAL_NUM (1), WORKDIR ($PWD/robodojo_work), ENV_NAME (robodojo61),
#   POLICY_GPU / ENV_GPU (0 / 0): put pi0.5 and the simulator on different GPUs when one card has < 24 GB
# Success criterion (RoboDojo's own): exit 0 and a _result.json with eval_time >= 1.
set -euo pipefail
WORKDIR=${WORKDIR:-$PWD/robodojo_work}
ENV_NAME=${ENV_NAME:-robodojo61}
TASK=${TASK:-stack_bowls}; POLICY=${POLICY:-demo_policy}; CKPT=${CKPT:-demo}
POLICY_ENV=${POLICY_ENV:-$ENV_NAME}; EVAL_NUM=${EVAL_NUM:-1}; POLICY_GPU=${POLICY_GPU:-0}; ENV_GPU=${ENV_GPU:-0}

eval "$(conda shell.bash hook)"
conda activate "$ENV_NAME"
unset VIRTUAL_ENV
export OMNI_KIT_ACCEPT_EULA=YES ACCEPT_EULA=Y PRIVACY_CONSENT=Y
# Pin the NVIDIA Vulkan ICD when several ICDs are installed (as the upstream Docker image does).
if [ -z "${VK_ICD_FILENAMES:-}" ]; then
  for icd in /usr/share/vulkan/icd.d/nvidia_icd.x86_64.json /usr/share/vulkan/icd.d/nvidia_icd.json /etc/vulkan/icd.d/nvidia_icd.json; do
    [ -f "$icd" ] && export VK_ICD_FILENAMES=$icd VK_DRIVER_FILES=$icd && break
  done
fi
# XPolicyLab's Pi_05 server pins XLA_PYTHON_CLIENT_MEM_FRACTION=0.3, too small for pi0.5 on cards
# below ~24 GB, so allocate on demand instead. RoboDojo rendering + pi0.5 did not fit on one 16 GB
# card (Vulkan ERROR_OUT_OF_DEVICE_MEMORY); use a >= 24 GB card or POLICY_GPU/ENV_GPU on two GPUs.
export XLA_PYTHON_CLIENT_ALLOCATOR=${XLA_PYTHON_CLIENT_ALLOCATOR:-platform}
# Isaac Lab writes logs under $TMPDIR/isaaclab/logs; on shared machines /tmp/isaaclab may belong to
# another user (PermissionError during env creation), so use a per-user temp dir.
export TMPDIR="${TMPDIR:-/tmp}/robodojo-$USER"; mkdir -p "$TMPDIR"

cd "$WORKDIR/RoboDojo"
START=$(date +%s)
bash scripts/robodojo.sh eval --policy-dir "XPolicyLab/policy/$POLICY" --task "$TASK" \
  --ckpt "$CKPT" --policy-env "$POLICY_ENV" --eval-env "$ENV_NAME" --action-type joint --eval-num "$EVAL_NUM" \
  --policy-gpu "$POLICY_GPU" --env-gpu "$ENV_GPU"
RJ=$(find "eval_result/RoboDojo/$TASK/$POLICY" -name _result.json -newermt "@$START" 2>/dev/null | sort | tail -1)
[ -n "$RJ" ] || { echo "no _result.json produced"; exit 1; }
echo "result: $RJ"; cat "$RJ"
