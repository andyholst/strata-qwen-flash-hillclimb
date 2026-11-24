# Hardware measurements

Taken on 2026-11-24 with the Strata server stopped, so the GPU was empty.
The CPU frequency governor was `powersave` (`intel_pstate`). It was left there.
The laptop was on AC power (battery full, status "Not charging").

| Quantity | Result | How |
|---|---:|---|
| GPU | RTX 4090 Laptop, sm 8.9, 16026 MiB CUDA / 16376 MiB nvidia-smi | `cudaGetDeviceProperties`, driver 615.78.08 |
| Power cap | 175 W | `nvidia-smi` `power.max_limit` |
| Sustained clocks under FP16 GEMM | 2310 MHz SM, 9001 MHz memory, about 129 W | `nvidia-smi -l 1` during the 8192 GEMM |
| VRAM read | 563.45 GB/s median (12 reps, 561.72 to 563.75) | 1 GiB `float4` read kernel |
| Device-to-device copy | 253.3 GB/s median | 1 GiB `cudaMemcpy` D2D. This is the copy engine, not the decode ceiling |
| Host-to-device, pinned | 12.25 GB/s median (12.22 to 12.29) | 1 GiB pinned `cudaMemcpy` H2D |
| FP16 GEMM, 4096, one shot | 74.06 TFLOPS, result checked | cuBLAS `GemmEx`, FP16 in, FP32 accumulate, tensor op |
| FP16 GEMM, 8192, 300 reps | 86.49 TFLOPS median, 12.71 ms | same, after clocks came up. First reps were 76 TFLOPS |
| Host copy, 1 thread, 1 GiB | 15.8 GB/s median | `memcpy` |
| Host copy, 16 threads, 4 GiB | 22.3 GB/s median (16.1 to 23.1) | 16 `memcpy`s |
| Weight file, direct read | 3.6 GB/s | `dd` of 512 MiB, `iflag=direct`, from the first GGUF shard |
| CPU | 13th Gen i9-13980HX, 24 cores, 62 GiB RAM | `lscpu`, `free` |

GB/s here is decimal (bytes / 1e9 / seconds).

The same boot of Strata, after these runs, measured host-to-device again at 12.5 GB/s
(best of 12.5, 12.3, 12.3, 12.3) and loaded 39.97 GiB of expert weights at 3.71 GiB/s.

`ceiling.json` is the input to `scripts/ceiling.py`. `ceiling.txt` is the script output.
The prefill row uses an estimated active-parameter count. See `THEORY.md`.
