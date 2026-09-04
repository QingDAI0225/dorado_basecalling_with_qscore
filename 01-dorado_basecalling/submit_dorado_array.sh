#!/usr/bin/env bash
set -euo pipefail

SUBMIT_DIR="$PWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_SCRIPT="${SCRIPT_DIR}/dorado_basecalling.sh"
mkdir -p "${SCRIPT_DIR}/logs"
cd "$SCRIPT_DIR"

POD5_DIR="${1:?usage: submit_dorado_array.sh POD5_DIR OUTDIR [BARCODE_MODE] [MAX_CONCURRENT]}"
OUTDIR="${2:?missing OUTDIR}"
BARCODE_MODE="${3:-either_end}"
MAX_CONCURRENT="${4:-100}"

BIND="${BIND:-/work/qd33,/cwork/qd33,/hpc/dctrl/qd33}"
KIT="${KIT:-SQK-NBD114-96}"
MODEL="${MODEL:-sup}"
REFERENCE="${REFERENCE:-}"
PARTITION="${PARTITION:-chsi-gpu,gpu-common}"
ACCOUNT="${ACCOUNT:-chsi}"

if [[ -n "$REFERENCE" ]]; then
  [[ "$REFERENCE" = /* ]] || REFERENCE="${SUBMIT_DIR}/${REFERENCE}"
  [[ -r "$REFERENCE" ]] || { echo "Reference not readable: $REFERENCE" >&2; exit 1; }
  REFERENCE="$(realpath "$REFERENCE")"
fi

case "$BARCODE_MODE" in
  either_end|both_ends) ;;
  *) echo "BARCODE_MODE must be 'either_end' or 'both_ends', got: $BARCODE_MODE" >&2; exit 1 ;;
esac

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
echo "  Barcode mode    : $BARCODE_MODE"
echo "  Reference       : ${REFERENCE:-none}"
echo "  N files         : $N"
echo "  Array           : $ARRAY"
echo "  Partition/Acct  : ${PARTITION}/${ACCOUNT}"

sbatch -p "$PARTITION" -A "$ACCOUNT" \
  --array="$ARRAY" \
  --export=ALL,POD5_DIR="$POD5_DIR",OUTDIR="$OUTDIR",KIT="$KIT",MODEL="$MODEL",BIND="$BIND",REFERENCE="$REFERENCE",BARCODE_MODE="$BARCODE_MODE" \
  "$SLURM_SCRIPT"
