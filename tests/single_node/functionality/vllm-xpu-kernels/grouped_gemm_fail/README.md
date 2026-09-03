# XE2 grouped-GEMM D-store test

This standalone SYCL test exercises the native XE2 output-store path used by
the FP16 grouped-GEMM kernel. It initializes a 4x512 output with NaNs, stores
one to every element, and fails if any element is missing or incorrect.

## Default environment

Build and run with the default toolchain:

```bash
./build_repro_xe2_store_sycl.sh
./repro_xe2_store_sycl
```

The expected exit status is `1`.

## Intel AICOE GPU UMD

Build and run with the alternate UMD module loaded:

```bash
module load intel_gpu_umd_aicoe/2026.06.19
./build_repro_xe2_store_sycl.sh
./repro_xe2_store_sycl
```

The expected exit status is `0`.
