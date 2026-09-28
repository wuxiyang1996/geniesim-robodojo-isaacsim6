"""Hold-still inference server for Genie Sim benchmark smoke tests.

Speaks the corobot wire protocol (msgpack JSON-RPC over websocket, see
geniesim_benchmark/benchmark/policy/corobotpolicy.py): for every "infer" request it
returns a JOINT_ABS chunk that repeats the current arm/gripper state, so the robot
stays put. Checks simulator bring-up, rendering and the policy link, not skill.
"""
import argparse
import asyncio
import time

import msgpack
from websockets.asyncio.server import serve

CHUNK = 10


def hold_action(params):
    states = params.get("states", {})
    arm = list(states.get("arm_joint_states", []))
    grip = list(states.get("gripper_states", [0.0, 0.0]))
    half = len(arm) // 2
    left, right = arm[:half], arm[half:]
    return {
        "left_arm": {"kind": "JOINT_ABS", "values": [left] * CHUNK},
        "right_arm": {"kind": "JOINT_ABS", "values": [right] * CHUNK},
        "left_effector": [[grip[0]]] * CHUNK,
        "right_effector": [[grip[1] if len(grip) > 1 else 0.0]] * CHUNK,
    }


async def handler(ws):
    n = 0
    async for message in ws:
        req = msgpack.unpackb(message, raw=False)
        params = req.get("params", {})
        images = params.get("images", {})
        n += 1
        if n <= 3 or n % 20 == 0:
            sizes = {k: (v.get("width"), v.get("height"), len(v.get("image_data", b""))) for k, v in images.items() if isinstance(v, dict)}
            print(f"[hold] req {n} method={req.get('method')} prompt={str(params.get('prompt', ''))[:60]!r} "
                  f"arm_dim={len(params.get('states', {}).get('arm_joint_states', []))} images={sizes}", flush=True)
        await ws.send(msgpack.packb({"result": hold_action(params)}))


async def main(host, port):
    async with serve(handler, host, port, max_size=None, compression=None):
        print(f"[hold] listening on ws://{host}:{port} at {time.ctime()}", flush=True)
        await asyncio.Future()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8999)
    a = ap.parse_args()
    asyncio.run(main(a.host, a.port))
