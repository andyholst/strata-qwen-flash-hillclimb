# Plan

One machine, one model, one change at a time. Failures stay in this file.

## Target

- Model: Qwen3.8-Flash-Next GSQ-RCO, pack IQ3_XXS, served as `qwen3.8-flash-next-iq3_xxs`.
- Engine: Strata 0.1.67, CUDA 13, binary `0.1.67-linux-x86_64-cuda-cuda13`.
- Launch preset: `IQ3_XXS 128K (9)` (`launch-iq3_xxs-128k-9`), `http://127.0.0.1:8080`.
- Context actually served: 131072. The checkpoint's `context_length` is 262144.
  The 256K figure is not a constraint of this run. The card does not hold a 256K cache
  beside the weights.
- Quality bar for a kept change: int8 KV, the quant that is already loaded. A change
  that switches KV format or quant is lossy and has to be labelled as such. None has
  been tried.
- Metric order: single-stream decode tok/s, then cold prefill at about 4K and 32K,
  then a 64K needle (half of the served context).
- Concurrency under test: 1. DFlash2 on this card is running one request at a time,
  and a second stream would fight the same 16 GiB.

## Baseline flags

These are the engine arguments of the process that the benchmark hits. They match the
process that was stopped before the measurements.

```
--expert-cache auto
--prefill auto
--kv int8
--kv-resident 32768
--pool-workers 15
--prompt-cache-spread
--max-context 131072
--conversation-cache-mib 3072
--vram-reserve-mib 704
--draft dflash2
--draft-fallback none
--spec 6
--draft-conf 0.7
--conversation-cache-min-tokens 1024
```

Startup on this boot: expert cache 5451 slots, 8.84 GiB, 913 MiB VRAM free after
load, PCIe 12.5 GB/s, experts loaded at 3.71 GiB/s.

## Runs

| Name | Change | Result | Kept? |
|---|---|---|---|
| baseline-iq3xxs-128k | none | c1 median 79.79 tok/s (six runs, 75.92 to 90.83). Cold prefill 1480.8 tok/s over 2839 tokens, 1944.3 over 21573 tokens. 43147-token needle, decode 79.35, retrieval 3/3. Short TTFT 501 ms. Host RSS peak 46.02 GiB. `ok`, no flags. | control |

No candidate has been run. A candidate waits until this control has a median.

## Prior single requests, not the harness

The previous process, same flags, logged end-of-request lines. Those are single
production calls with prefix reuse, not medians, and they are not the baseline:

- 65125 prompt tokens, 0 reused, prefill 2208.7 tok/s, decode 83.8 tok/s, 16008 generated.
- 96482 prompt tokens, 22653 reused, prefill 1965.7 tok/s on the tokens read, decode 74.4 tok/s.

Short prompts on that process were a different regime (one startup self-check did
41.8 tok/s on a single generated token). They are not used as the decode number.

The harness asks for 4096, 32768, and 65536 tokens by counting words at 1.6 tokens each.
On this tokenizer the documents came back as 2839, 21573, and 43147 tokens. Those
server counts are the ones in the table. The run is still the cold-prefill and
half-context needle the config asked for. It is not a 32K or 64K measurement.

The six decode runs spread from 75.92 to 90.83 around a median of 79.79, about
±9%. A later change has to clear that band on both sides of a control, not on
one lucky run.

79.79 is 45% of the 176 tok/s no-speculation ceiling at 4K. The server is already
drafting, so the gap is not "speculation is off". Prefill at 21573 tokens,
1944 tok/s, sits near the pessimistic formula (2239 at 32K). That comparison is
loose: the formula's active-parameter count is estimated, and the prompt is shorter
than 32K.

## 121530-token prefill, one change

Same document shape as the harness (`--long 185000`), which this tokenizer counts as 121530 tokens. Retrieval is three exact codes. One decode sample at that length, plus one short c1 sample. Controls are fresh process starts.

Hypothesis: on this 16 GiB card `--prefill auto` stays at 8192 so prompt loans do not eat expert slots. `STRATA_NV_CHUNK=16` raises that chunk to 16384. A 121k prefill was the thing to speed up. Decode was not expected to move.

| Run | Chunk the engine reported | Prefill tok/s | TTFT | Decode at 121530 | Retrieval | Short c1 |
|---|---:|---:|---:|---:|---|---:|
| ctl-128k-a (unset, the original preset) | 8192 | 2123.0 | 57.2 s | 82.99 | 3/3 | 79.07 |
| nvchunk16-128k (`STRATA_NV_CHUNK=16`) | 16384 | 2801.2 | 43.4 s | 83.35 | 3/3 | 72.40 |
| ctl-128k-b (`STRATA_NV_CHUNK=0`) | 8192 | 2116.2 | 57.4 s | 84.74 | 3/3 | 76.05 |
| nvchunk1-128k (`STRATA_NV_CHUNK=1`) | 22784 | 2847.1 | 42.7 s | 79.32 | 3/3 | 90.40 |

`STRATA_NV_CHUNK=16` is kept. Prefill is 2801 against controls of 2123 and 2116, about 1.32×, and the needle still matches. Decode at 121530 tokens stays in the same band.

`STRATA_NV_CHUNK=1` raises the chunk again, to 22784, and lands at 2847 tok/s. That is inside the noise of 2801. It is not kept. The server is back on `STRATA_NV_CHUNK=16`.

This is not a doubling. The two controls agree, and a still larger chunk did not add another step, so the 8192 path was the slow one and 16384 already left it. Short-context decode was not the target of this lever. Its no-speculation ceiling at 128K is 117 tok/s, and the measured long decode is about 83 tok/s with DFlash2 already on.

`STRATA_NV_CHUNK=16` is not left on `IQ3_XXS 128K (9)`. That run config's env is empty again. The kept server is a new launch preset, `IQ3_XXS 128K Hermes NV16`, copied from `IQ3_XXS 128K Hermes` with that one variable added. The Hermes preset file was not edited. See `configs/preset-hermes-nv16.json`.

## Not done yet

- A document the tokenizer counts as the full 131072.
- Decode is still about 83 tok/s at 121530 tokens. Doubling that would pass the 117 tok/s no-speculation ceiling, so it needs a cheaper step, not a bigger prefill chunk.
- VRAM bandwidth during a real decode graph. The 563 GB/s figure is a read kernel, not the model's GEMV.
- CPU governor was not switched off `powersave`.
