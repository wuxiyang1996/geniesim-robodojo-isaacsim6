#!/usr/bin/env bash
# Make pip-installed Isaac Sim 6.1 load on hosts with glibc < 2.35 (RHEL 9 / Rocky 9 ship 2.34).
# Not needed on Ubuntu 22.04+ (glibc 2.35+).
#
# Isaac Sim wheels are tagged manylinux_2_35, but only a handful of libraries actually reference
# GLIBC_2.35+ symbols (e.g. hypot@GLIBC_2.35 in libusd_ts.so and kit's libpython3.12). For each such
# library this script:
#   1. backs it up to $BACKUP_DIR,
#   2. clears the version on the offending symbols (patchelf --clear-symbol-version), and
#   3. marks the GLIBC_2.35+ requirement weak (weaken_verneed.py), which glibc's loader tolerates.
# patchelf alone is not enough: the loader still checks .gnu.version_r.
#
# It also installs conda-forge libstdc++ (kit needs GLIBCXX_3.4.30; RHEL 9's stops at 3.4.29) and
# adds an activate.d hook that puts only that libstdc++/libgcc_s ahead of the system copy.
#
# Usage (inside the activated conda env that holds isaacsim):
#   bash rhel9/patch_glibc.sh            # BACKUP_DIR defaults to $CONDA_PREFIX/glibc_patch_backup
# Re-run after (re)installing isaacsim or any package that ships new .so files.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CONDA_PREFIX:?activate the conda env first}"
BACKUP_DIR=${BACKUP_DIR:-$CONDA_PREFIX/glibc_patch_backup}
SP=$(python -c 'import site; print(site.getsitepackages()[0])')

echo "[glibc] system glibc: $(ldd --version | head -1)"

# --- libstdc++ from conda-forge, exposed only on activation ------------------------------------
conda install -y -c conda-forge "libstdcxx-ng>=12" "libgcc-ng>=12" >/dev/null
mkdir -p "$CONDA_PREFIX/lib/stdcxx_only" "$CONDA_PREFIX/etc/conda/activate.d" "$CONDA_PREFIX/etc/conda/deactivate.d"
ln -sf ../libstdc++.so.6 "$CONDA_PREFIX/lib/stdcxx_only/libstdc++.so.6"
ln -sf ../libgcc_s.so.1 "$CONDA_PREFIX/lib/stdcxx_only/libgcc_s.so.1"
cat > "$CONDA_PREFIX/etc/conda/activate.d/zz_stdcxx.sh" <<'EOS'
export _STDCXX_OLD_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib/stdcxx_only${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
EOS
cat > "$CONDA_PREFIX/etc/conda/deactivate.d/zz_stdcxx.sh" <<'EOS'
export LD_LIBRARY_PATH="${_STDCXX_OLD_LD_LIBRARY_PATH:-}"
[ -z "$LD_LIBRARY_PATH" ] && unset LD_LIBRARY_PATH
unset _STDCXX_OLD_LD_LIBRARY_PATH
EOS
echo "[glibc] libstdc++ hook installed (re-activate the env to pick it up)"

# --- patch libraries that need GLIBC_2.35+ -----------------------------------------------------
python -m pip install -q patchelf
PATCHELF="$CONDA_PREFIX/bin/patchelf"
mkdir -p "$BACKUP_DIR"
LIST=$(mktemp)
find "$SP" -name '*.so*' -type f -print0 \
  | xargs -0 -P8 -n200 sh -c 'for f; do objdump -T "$f" 2>/dev/null | grep -qE "GLIBC_2\.(3[5-9]|4[0-9])" && echo "$f"; done' _ > "$LIST" || true
echo "[glibc] libraries needing GLIBC_2.35+: $(wc -l < "$LIST")"
while read -r f; do
  cp -pn "$f" "$BACKUP_DIR/$(echo "$f" | md5sum | cut -c1-8)_$(basename "$f")"
  for v in $(objdump -T "$f" | grep -oE 'GLIBC_2\.(3[5-9]|4[0-9])' | sort -u); do
    for s in $(objdump -T "$f" | awk -v v="$v" '$0 ~ v" " {print $NF}' | sort -u); do
      "$PATCHELF" --clear-symbol-version "$s" "$f"
    done
    python "$HERE/weaken_verneed.py" "$f" "$v" | sed "s|$SP/||" || true
  done
done < "$LIST"
rm -f "$LIST"
echo "[glibc] done; originals in $BACKUP_DIR"
