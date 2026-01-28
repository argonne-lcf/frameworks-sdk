# Frameworks SDK Module Build Scripts

We have build scripts for compiling the Frameworks SDK using system available
modules and libraries.

## Build Environment

The build environment assumes a user session on
`{aurora,sunspot}.alcf.anl.gov`. Builds are performed in `/tmp`.

Prior to building, most build scripts will load common modules and environment
variables using the `setup_build_env` routine in `ci-lib.sh`.

## Adding a Build Script

Build scripts are generally structured similarly.

```sh
#!/usr/bin/env bash

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../ci-lib.sh"

# 1) Pull source and gen build environment
gen_build_dir_with_git 'https://github.com/<foo>/<bar>'
setup_build_env

setup_uv_venv # pass needed dependencies (i.e. from prior builds) here

# 2) Set <library> configuration
CC="$(which gcc)"
export CC
CXX="$(which g++)"
export CXX

# 3) Build & Archive
build_bdist_wheel
```

## Wheels

We have scripts to build the following wheels:
- pytorch/
    - pytorch
    - ao[^disabled]
    - torchtune[^disabled]
- intel/
    - intel-extension-for-pytorch
    - torch-ccl
- mpi4py/mpi4py
- h5py/h5py[^disabled]

[^disabled]: not ran by CI pipeline

### Build Time(s)

|   &nbsp;   | took (hours) |
| :--------: | :----------: |
|  `torch`   |    ~ 2:00    |
|   `ipex`   |    ~ 1:00    |
| others[^1] |    < 0:30    |
| **total**  |    ~ 4:00    |


[^1]: Others:
    - `h5py/h5py` (broken ??)
    - `intel/torch-ccl`
    - `mpi4py/mpi4py`
    - `pytorch/ao`
    - `pytorch/torchaudio`
    - `pytorch/torchdata`
    - `pytorch/torchtune`
    - `pytorch/torchvision`

### IPEX Build Bugs

- [❌ TAKE 1]

    ```bash
    # [2025-07-05 @ 23:20] hung (?) (@ 92% > ~ 2 hr)
    #    [ 92%] Linking CXX shared library libxetla_gemm.so]
    ```

- [❌ TAKE 2]

    ```bash
    # [2025-07-06 @ 10:30:24] hung (?) (@ 97% )
    #     [ 97%] Built target intel-ext-pt-gpu-op-TripleOps
    # [2025-07-06 @ 11:01] ...[waiting]...
    # [2025-07-06 @ 13:00] job ended :(
    ```

- [✅ TAKE 3]

    ```bash
    # [✅ TAKE 3]
    # [2025-07-06 @ 18:00] Successfully built IPEX
    # took: 1h:05m:36s
    ```
