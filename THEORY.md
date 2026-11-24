# Theory

The decode ceiling uses the measured VRAM read bandwidth, 563.45 GB/s, not the
datasheet. A device-to-device copy on this GPU only reaches 253 GB/s, because that
path is the copy engine. Decode reads weights with the SMs, so the read-kernel number
is the one in the formula.

## What one target token has to read

From the checkpoint and from the engine's own startup lines on this boot:

| Piece | Size | Source |
|---|---:|---|
| Routed experts, whole pack | 42.794 GB | 5451 cache slots occupy 8.84 GiB, and there are 24576 experts (48 layers x 512) |
| Experts actually routed | 0.836 GB | 42.794 x 10/512. Top-10 of 512, every layer |
| Dense projections on the GPU | 1.868 GB | 1781.11 MiB, 300 native matrices |
| LM head | 0.437 GB | experimental native Q5_K, 437043200 bytes |
| KV, int8 | 12698 bytes/token | 1.55 GiB pinned for the full 131072-token cache |

Short-context verify, no speculation:

```
1.868 + 0.836 + 0.437 = 3.141 GB per token
563.45 / 3.141 = 179 tok/s
```

`scripts/ceiling.py` applies the same split and then adds KV. Its no-speculation row is:

| Context | Ceiling |
|---|---:|
| 4K | 176 tok/s |
| 32K | 158 tok/s |
| 128K | 117 tok/s |

Two limits sit under that VRAM number.

- Only 5451 of 24576 experts fit in VRAM (22.2%, 8.84 GiB). The frequency profile still
  serves most lookups from the cache on a long chat (the previous process logged about
  74 to 81% decode hits). A miss is computed from host memory. Host copy bandwidth,
  16 threads, is 22 GB/s. The PCIe link, measured twice, is 12.3 to 12.5 GB/s.
- The working set above assumes every selected expert is read from VRAM. When the hit
  rate is 75%, about 0.21 GB of expert bytes per token are not in that VRAM read.
  Those bytes are not free. They are the CPU-side path (`--pool-workers 15`).

## Speculation

The live server drafts with DFlash2, `--spec 6`, windows up to 8, `--draft-conf 0.7`,
and no MTP fallback. The drafter is 591 MiB Q4_0 plus a 178.4 MiB head (106299 tokens).

The MTP formula in the skill (k full draft steps, each reading a draft head) does not
describe a DFlash2 window, which is one block draft. This file therefore does not
publish a speculative tok/s ceiling. A window that emits `a` tokens can beat the
no-speculation row only when the extra draft bytes, divided by `a`, are smaller than
the bytes saved. That is measured in the ledger, not assumed here.

## Prefill

Peak FP16 tensor GEMM on this GPU is 86.49 TFLOPS at 8192, sustained, at 2310 MHz and
about 129 W of a 175 W cap. There was no thermal drop across 300 reps (about 4 seconds).

Active parameters used for the formula, and why the number is an estimate:

- Routed experts: 48 layers x 10 x 3 x 2560 x 640 = 2.359e9 parameters.
- Dense projections: 1.868 GB. At 3.06 bits per weight (the IQ3_XXS name) that is about
  4.88e9 parameters. Shared experts may sit inside that figure. They are not added again.
- Sum used in `ceiling.json`: 7.24e9.

The script then adds a dense causal-attention term (12 full layers, 24 heads, head dim
256). This model does not do dense attention. `full_attention_interval` is 4, and the
indexer keeps `top_k` 2048. The quadratic term is larger than the model spends, so the
prefill row is a pessimistic formula, not a measured maximum:

| Prompt | Formula |
|---|---:|
| 4K | 2867 tok/s |
| 32K | 2239 tok/s |
| 128K | 1279 tok/s |

## What would count as a win

A kept change has to beat the interleaved control by more than the noise band
(about 5 to 10%), and a long-context needle in the same run has to still match.
The first lever is not chosen until the baseline median exists. The likely place
to look, from the startup log rather than from a guess, is the 22% expert cache
on a 16 GiB card: the drafter, the 704 MiB VRAM reserve, and `--spec` all trade
VRAM slots for tokens per step. One of those at a time.
