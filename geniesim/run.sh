#!/usr/bin/env bash
# Run Genie Sim benchmark tasks headless on Isaac Sim 6.1 against an inference server.
#
# Usage:
#   TASKS="g2op_if_pick_block_color" SERVER=pi05 WORKDIR=/path/to/work bash geniesim/run.sh
# Environment variables:
#   TASKS     space-separated benchmark configs (see `geniesim benchmark list`)   [required]
#   SERVER    hold     - tools' hold_server.py, keeps the robot still (bring-up check, score 0)
#             pi05     - the official pi0.5 baseline (run geniesim/install_baseline.sh first)
#             external - you already serve the corobot protocol on 127.0.0.1:$PORT
#   WORKDIR   same as for install.sh                        (default: $PWD/geniesim_work)
#   ENV_NAME  conda env from install.sh                     (default: geniesim61)
#   PORT      inference server port                         (default: 8999)
#   EPISODES  --benchmark.num_episode                       (default: 1, the upstream task default)
#   PI05_MEM_FRACTION  XLA memory cap for the pi05 server   (default: 0.45; sim + pi05 fit on 16 GB)
#   PI05_CONFIG / PI05_CKPT_DIR  board checkpoint           (default: instruction/robust board)
# Results: $WORKDIR/genie_sim/output/benchmark/<task_name>/<sub_task>/evaluate_ret_*.json + videos.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR=${WORKDIR:-$PWD/geniesim_work}
ENV_NAME=${ENV_NAME:-geniesim61}
PORT=${PORT:-8999}
EPISODES=${EPISODES:-1}
SERVER=${SERVER:-hold}
: "${TASKS:?set TASKS, e.g. TASKS=g2op_if_pick_block_color}"
mkdir -p "$WORKDIR/logs"

eval "$(conda shell.bash hook)"
conda activate "$ENV_NAME"
unset VIRTUAL_ENV

export OMNI_KIT_ACCEPT_EULA=YES ACCEPT_EULA=Y PRIVACY_CONSENT=Y
# The benchmark does not need geniesim_ros (RT Engine); skip the CLI's bootstrap check.
export GENIESIM_SKIP_AUTOBOOT=1
# Upstream defaults to the docker bind mount /workspace for kit caches/logs.
export GENIESIM_KIT_RUNTIME_DIR=${GENIESIM_KIT_RUNTIME_DIR:-$WORKDIR/kit_runtime}
export GENIESIM_OMNI_DOCUMENTS_DIR=${GENIESIM_OMNI_DOCUMENTS_DIR:-$WORKDIR/kit_runtime/Documents}
# app.py imports rclpy at startup: use the ROS 2 Jazzy that ships inside Isaac Sim 6.1.
ROS2_CORE="$CONDA_PREFIX/lib/python3.12/site-packages/isaacsim/exts/isaacsim.ros2.core/jazzy"
export ROS_DISTRO=jazzy RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$ROS2_CORE/lib"
# Pin the NVIDIA Vulkan ICD when several ICDs are installed (as the upstream image does).
if [ -z "${VK_ICD_FILENAMES:-}" ]; then
  for icd in /usr/share/vulkan/icd.d/nvidia_icd.x86_64.json /usr/share/vulkan/icd.d/nvidia_icd.json /etc/vulkan/icd.d/nvidia_icd.json; do
    [ -f "$icd" ] && export VK_ICD_FILENAMES=$icd && break
  done
fi

wait_port() { for _ in $(seq 180); do python -c "import socket;socket.create_connection(('127.0.0.1',$PORT),1)" 2>/dev/null && return 0; kill -0 "$1" 2>/dev/null || return 1; sleep 5; done; return 1; }
SPID=""
trap '[ -n "$SPID" ] && kill $SPID 2>/dev/null || true' EXIT
case "$SERVER" in
  hold)
    python "$HERE/hold_server.py" --port "$PORT" > "$WORKDIR/logs/hold_server.log" 2>&1 & SPID=$!
    wait_port $SPID || { echo "hold server did not start"; cat "$WORKDIR/logs/hold_server.log"; exit 1; } ;;
  pi05)
    R="$WORKDIR/ACoT-VLA"
    ( cd "$R" && env -u CONDA_PREFIX -u LD_LIBRARY_PATH VIRTUAL_ENV="$R/.venv" \
        XLA_PYTHON_CLIENT_MEM_FRACTION="${PI05_MEM_FRACTION:-0.45}" XLA_PYTHON_CLIENT_PREALLOCATE=false \
        XLA_PYTHON_CLIENT_ALLOCATOR=platform XLA_FLAGS="--xla_gpu_autotune_level=0" \
        "$R/.venv/bin/python" scripts/serve_policy.py --host 127.0.0.1 --port "$PORT" policy:checkpoint \
          --policy.config "${PI05_CONFIG:-pi05_genie_sim_instruction_and_robust_20260526}" \
          --policy.dir "${PI05_CKPT_DIR:-./checkpoints/instruction_and_robust_pi05}" ) \
      > "$WORKDIR/logs/pi05_server.log" 2>&1 & SPID=$!
    wait_port $SPID || { echo "pi05 server did not start"; tail -30 "$WORKDIR/logs/pi05_server.log"; exit 1; } ;;
  external) ;;
  *) echo "unknown SERVER=$SERVER"; exit 1 ;;
esac

cd "$WORKDIR/genie_sim"
for T in $TASKS; do
  echo "=== $T  $(date)"
  # NOTE: `geniesim benchmark run` exits 0 even when app.py raises; read the log / evaluate_ret_*.json.
  geniesim benchmark run "$T" --infer-host=127.0.0.1:$PORT \
    --app.headless=true --benchmark.record=true --benchmark.num_episode="$EPISODES" --benchmark.seed=0 \
    2>&1 | tee "$WORKDIR/logs/run_${T}.log"
done
