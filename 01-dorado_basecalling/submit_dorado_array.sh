#!/usr/bin/env bash
set -euo pipefail

# --------- edit these ----------
SLURM_SCRIPT="dorado_basecalling.sh"
BIND="/work/qd33"
POD5_DIR="/work/qd33/data/Nanopore/20250326_separate_test/separated_102K/20250326_1502_MN33275_ASD212_676057dc/pod5_skip"
OUTDIR="/work/qd33/data/basecalling_data/20250326_separate_test"
KIT="SQK-NBD114-96"
MODEL="sup"
MAX_CONCURRENT=100                            
PARTITION="chsi-gpu,gpu-common"
ACCOUNT="chsi"
# -------------------------------

if [[ ! -f "$SLURM_SCRIPT" ]]; then
  echo "ERROR: slurm script not found: $SLURM_SCRIPT" >&2
  exit 1
fi

if [[ ! -d "$POD5_DIR" ]]; then
  echo "ERROR: POD5_DIR not found: $POD5_DIR" >&2
  exit 1
fi

N=$(find "$POD5_DIR" -type f -name "*.pod5" | wc -l | tr -d ' ')
if [[ "$N" -eq 0 ]]; then
  echo "No .pod5 found under: $POD5_DIR"
  exit 0
fi

ARRAY="0-$((N-1))%${MAX_CONCURRENT}"

echo "Submitting:"
echo "  POD5_DIR        : $POD5_DIR"
echo "  OUTDIR          : $OUTDIR"
echo "  KIT / MODEL     : $KIT / $MODEL"
echo "  N files         : $N"
echo "  Array           : $ARRAY"
echo "  Partition/Acct  : ${PARTITION}/${ACCOUNT}"

sbatch -p "$PARTITION" -A "$ACCOUNT" \
  --array="$ARRAY" \
  --export=ALL,POD5_DIR="$POD5_DIR",OUTDIR="$OUTDIR",KIT="$KIT",MODEL="$MODEL",BIND="$BIND" \
  "$SLURM_SCRIPT"
