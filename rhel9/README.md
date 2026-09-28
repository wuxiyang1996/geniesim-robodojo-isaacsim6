# Isaac Sim 6.1 on glibc < 2.35 (RHEL 9, Rocky 9, ...)

Only needed when `ldd --version` reports glibc older than 2.35. Ubuntu 22.04/24.04 do not need this.
`geniesim/install.sh` and `robodojo/install.sh` call it automatically on such hosts.

## Problem

- The `isaacsim` wheels are tagged `manylinux_2_35`, so `pip` refuses them on glibc 2.34.
- Kit needs `GLIBCXX_3.4.30`; RHEL 9's system `libstdc++` stops at 3.4.29
  (`Unable to bootstrap inner kit kernel: ... GLIBCXX_3.4.30 not found`).
- A few libraries really reference a GLIBC_2.35 symbol, e.g. `hypot@GLIBC_2.35` in
  `omni.usd.libs/.../libusd_ts.so` and kit's `libpython3.12.so`. Kit then logs
  `version 'GLIBC_2.35' not found (required by .../libusd_ts.so)`.

## Fix

1. Install the wheels with uv's platform override:
   `uv pip install --python-platform x86_64-manylinux_2_35 "isaacsim[all,extscache]==6.1.0.0" --extra-index-url https://pypi.nvidia.com`
2. `bash rhel9/patch_glibc.sh` inside the activated env:
   - installs conda-forge `libstdc++` and an `activate.d` hook that prepends a directory holding
     only that `libstdc++.so.6`/`libgcc_s.so.1` to `LD_LIBRARY_PATH`;
   - for every `.so` that references GLIBC_2.35+: backs it up, clears the version of the offending
     symbols with `patchelf --clear-symbol-version`, and marks the GLIBC_2.35 entry in
     `.gnu.version_r` weak with [`weaken_verneed.py`](weaken_verneed.py). glibc's loader treats a
     missing *weak* version requirement as non-fatal, and the unversioned symbol binds to the
     2.34 implementation. `patchelf` alone is not enough: the loader still checks `.gnu.version_r`.

On our install (Isaac Sim 6.1.0.0) six libraries needed the patch; all of them only referenced
`hypot@GLIBC_2.35` or a similar libm/libc symbol with an older equivalent.
Re-run the script after reinstalling Isaac Sim or adding packages that ship native code.

## Other things we hit on RHEL 9 / a shared cluster

- No root: `git-lfs`, `ffmpeg` come from conda-forge; CUDA toolkits from environment modules.
- Several Vulkan ICDs installed (intel, lvp, radeon, nouveau, nvidia): the run scripts pin
  `VK_ICD_FILENAMES` to the NVIDIA one, as the upstream Docker images do.
- An activated venv in the submitting shell leaks into batch jobs; `uv pip` also installs into the
  active conda env unless `VIRTUAL_ENV` is set. The install scripts unset/pin these explicitly.
