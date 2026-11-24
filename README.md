# Strata hill-climb: Qwen3.8-Flash-Next IQ3_XXS on an RTX 4090 Laptop

This repo is the log of one speed hill-climb. The method is
[0xSero's inference-optimisation skill](https://github.com/sybil-solutions/inference-optimisation-skill)
(`fda968e7fc1996aa23c67139c755fe541c9d4be0`): measure the machine, change one thing,
compare it with a control on both sides, and keep a number only when a long prompt
still retrieves.

No API keys, tokens, or account files belong in this repo. The server key stays in
the environment of the process that calls the API.

## Machine and model

| | |
|---|---|
| GPU | NVIDIA GeForce RTX 4090 Laptop, 16 GiB, sm 8.9, driver 615.78.08, 175 W cap |
| CPU | Intel i9-13980HX, governor `powersave`, 62 GiB RAM |
| Model | Qwen3.8-Flash-Next GSQ-RCO IQ3_XXS (`qwen4exp`, 48 layers, 512 experts, top-10) |
| Served id | `qwen3.8-flash-next-iq3_xxs` |
| Engine | Strata 0.1.67, CUDA 13 |
| Endpoint | `http://127.0.0.1:8080/v1` |
| Context served | 131072 tokens, KV int8 |
| Drafter | DFlash2, `--spec 6`, `--draft-conf 0.7` |

Measured ceilings, and the raw numbers behind them, are in `hardware/` and `THEORY.md`.
The no-speculation decode ceiling from the VRAM read bandwidth is **176 tok/s at 4K**,
**158 at 32K**, **117 at 128K**. That is a ceiling for reading weights, not a promise
the engine reaches it.

## The loop

1. Measure bandwidth and GEMM with the server stopped. Do not use datasheet GB/s.
2. Start the preset you mean to tune, and record the engine argv you actually got.
3. Run the harness against that live server. Medians, server-reported token counts.
4. Change exactly one flag or one `STRATA_*` variable.
5. Run control, then the candidate, then the control again.
6. Keep the change only if the median clears the noise and the needle still matches.
7. Write the failure down.

## Reproduce the baseline

Install the skill if you want the write-up next to the agent, or use the copies here:

```bash
git clone https://github.com/sybil-solutions/inference-optimisation-skill
mkdir -p ~/.claude/skills
cp -r inference-optimisation-skill/skills/inference-optimisation ~/.claude/skills/
```

Stop anything already bound to port 8080. With the GPU idle, the ceiling programs are
the ones described in `hardware/README.md` (a 1 GiB device read, a pinned host-to-device
copy, and a large FP16 GEMM). Then start the same preset. The command does not print
the key. `STRATA_API_KEY` must already be exported, and it must be the key the clients
already use:

```bash
cd ~/.local/share/strata/components/control/0.1.67
python3.12 strata.py launch \
  --preset "IQ3_XXS 128K (9)" \
  --api-key-env STRATA_API_KEY \
  --no-tui --yes --output json
```

From this repo, with the same variable exported:

```bash
python3 scripts/bench.py run configs/baseline.json --long 65536 --skip-cN --reps 6
python3 scripts/bench.py show
```

`--skip-cN` is deliberate. This card is full with one 128K stream, and DFlash2 is
serving a single request. `scripts/bench.py` reads `api_key_env` and sends a bearer
token. `configs/baseline.json` names the variable. It does not contain the secret.

What that run records:

- a short warm-up, not scored
- time to first token on a tiny prompt
- six single-stream generations of 512 tokens, temperature 0.6, median decode tok/s
- cold prefill near 4096 and near 32768 tokens (the real count comes back as `prompt_tokens`)
- one 65536-token document with three codes, temperature 0, scored by exact match
- peak host RSS of the `strata --serve` process, capped at 58 GiB in the watchdog

Token counts are the server's `usage` fields. Stream chunks are not counted.

## Files

| Path | What it is |
|---|---|
| `THEORY.md` | Byte budget and ceilings |
| `PLAN.md` | What was run, what was kept, what was not tried |
| `hardware/` | Measurements and `ceiling.py` input |
| `configs/baseline.json` | Harness config for the live server |
| `ledger.jsonl` | One JSON object per run |
| `scripts/bench.py` | Upstream harness plus bearer auth from the environment |
| `NOTICE.md` | Where the scripts came from |

## Baseline (2026-11-24)

One harness run, six decode repeats, temperature 0.6, thinking tokens counted when the server sends them. No flag was changed.

| Metric | Median or single run | Ceiling used for scale | Notes |
|---|---:|---:|---|
| c1 decode | 79.79 tok/s | 176 tok/s at 4K, no speculation | six runs, in order: 89.74, 77.65, 75.92, 80.17, 90.83, 79.41 |
| Cold prefill | 1480.8 tok/s | formula 2867 at 4K | 2839 tokens, one run |
| Cold prefill | 1944.3 tok/s | formula 2239 at 32K | 21573 tokens, one run |
| 65536-target needle | prefill 1993.9, decode 79.35 |  | 43147 tokens, retrieval 3/3 |
| Short TTFT | 501 ms |  | after one discarded warm-up |
| Engine RSS | 46.02 GiB peak | 58 GiB watchdog, 62 GiB machine | |

45% of the no-speculation decode ceiling, with DFlash2 already on. Prefill on the 21K document is in the neighborhood of the formula. Details, including why the token counts undershoot the targets, are in `PLAN.md`. The raw row is `ledger.jsonl`.

## 121530-token result

One change from the original preset: `STRATA_NV_CHUNK=16`, which moves this card's prompt chunk from 8192 to 16384. Same 121530-token document, needle 3/3 every time.

| Run | Prefill | TTFT | Decode |
|---|---:|---:|---:|
| Control, chunk 8192 | 2123 and 2116 tok/s | 57.2 s and 57.4 s | 83 and 85 tok/s |
| Kept, `STRATA_NV_CHUNK=16` | 2801 tok/s | 43.4 s | 83 tok/s |
| Rejected, `STRATA_NV_CHUNK=1` (chunk 22784) | 2847 tok/s | 42.7 s | 79 tok/s |

That is 1.32× on the long prefill, not 2×. A larger chunk did not go any further. The live preset is `STRATA_NV_CHUNK=16`.
