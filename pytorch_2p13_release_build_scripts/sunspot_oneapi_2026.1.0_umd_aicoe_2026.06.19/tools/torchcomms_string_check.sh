#!/bin/bash
TC=/lus/tegu/projects/datasets/software/26.181.0/wheelforge/envs/conda_envs/RP1_RC4_torchcomms_0.3.1_rc1_python_3.12.12/lib/python3.12/site-packages/torchcomms
D=/opt/aurora/26.181.0/spack/unified/1.1.1/install/linux-x86_64/gcc-14.3.0-siitp7a/lib64
for f in "$TC"/*.so; do printf '%-52s %s\n' "${f##*/}" \
    "$(readelf -d "$f" | awk -F'[][]' '/RUNPATH|RPATH/{print $2; exit}')"; done
#
echo "=== ORDER AND SPACK HASH ==="
ls -d "$D" || echo "MISSING on this node"
comm -12 <(ls "$D" 2>/dev/null | sort -u) \
       <(ls "$TC" "$TC/../torch/lib" 2>/dev/null | sort -u)
#
# injector check
echo "=== INJECTOR CHECK ==="
env | grep -E 'LDFLAGS|LD_RUN_PATH|LIBRARY_PATH'
icpx -### -shared -o /tmp/x.so -xc /dev/null 2>&1 | tr ' ' '\n' | grep -i rpath
