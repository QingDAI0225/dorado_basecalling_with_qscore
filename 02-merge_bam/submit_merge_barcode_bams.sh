#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:?usage: submit_merge_barcode_bams.sh OUTDIR SAMTOOLS_IMG [MAX_CONCURRENT]}"
SAMTOOLS_IMG="${2:-docker://quay.io/biocontainers/samtools:1.22.1--h96c455f_0}"
MAX_CONCURRENT="${3:-24}"
PARTITION="chsi"
ACCOUNT="chsi"

OUTDIR="${OUTDIR%/}"
PERPOD5="${OUTDIR}/per_pod5"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_SCRIPT="${SCRIPT_DIR}/merge_barcode_bams_array.sh"
mkdir -p "${SCRIPT_DIR}/logs"
cd "$SCRIPT_DIR"

N=$(find "${PERPOD5}" -type d -path "*bam_pass/*" -printf "%f\n" \
  | grep -E '^(barcode[0-9]+|unclassified)$' | sort -u | wc -l | tr -d ' ')

(( N > 0 )) || { echo "No barcode or unclassified dirs found under ${PERPOD5}"; exit 1; }

ARRAY="0-$((N-1))%${MAX_CONCURRENT}"
echo "Submitting: N=${N}, array=${ARRAY}"

sbatch -p "$PARTITION" -A "$ACCOUNT" --array="${ARRAY}" "$SLURM_SCRIPT" "${OUTDIR}" "${SAMTOOLS_IMG}"
