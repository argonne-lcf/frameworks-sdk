def sanity_check():
    import torch, intel_extension_for_pytorch as ipex, oneccl_bindings_for_pytorch as oneccl
    import torch.distributed

    device_count = torch.xpu.device_count()

    print(torch.__file__)
    print(*torch.__config__.show().split("\n"), sep="\n")

    print(f"PyTorch: {torch.__version__=}")
    print(f"XPU: {torch.xpu.is_available()=} ({device_count=})")
    print(f"XCCL: {torch.distributed.is_xccl_available()=}")

    print(f"IPEX: {ipex.__version__=}")
    print(f"oneCCL: {oneccl.__version__=}")

    for i in range(device_count):
        print(
            f"torch.xpu.get_device_properties({i}): {torch.xpu.get_device_properties(i)}"
        )
