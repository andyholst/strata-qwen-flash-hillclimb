#!/usr/bin/env bash
# Print the Strata engine's host RSS in bytes. bench.py's watchdog reads this number.
# GPU memory is reported separately by nvidia-smi during the write-up; summing it with RSS
# would count the same weights twice on a discrete GPU.
set -euo pipefail
pid=$(ps -eo pid,cmd | awk '/\/strata --serve / && !/awk/ {print $1; exit}')
if [ -z "${pid:-}" ]; then
  echo 0
  exit 0
fi
awk '/VmRSS/{print $2 * 1024}' "/proc/$pid/status"
