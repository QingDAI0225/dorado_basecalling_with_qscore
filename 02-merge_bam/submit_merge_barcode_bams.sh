#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:?usage: submit_merge_barcode_bams.sh OUTDIR SAMTOOLS_IMG [MAX_CONCURRENT]}"
SAMTOOLS_IMG="${2:-docker://quay.io/biocontainers/samtools:1.22.1--h96c455f_0}"
MAX_CONCURRENT="${3:-24}"
PARTITION="chsi"
ACCOUNT="chsi"

OUTDIR="${OUTDIR%/}"
PERPOD5="${OUTDIR}/per_pod5"

N=$(find "${PERPOD5}" -type d -path "*bam_pass/barcode*" -printf "%f\n" \
  | grep -E '^barcode[0-9]+$' | sort -u | wc -l | tr -d ' ')

(( N > 0 )) || { echo "No barcode dirs found under ${PERPOD5}"; exit 1; }

ARRAY="0-$((N-1))%${MAX_CONCURRENT}"
echo "Submitting: N=${N}, array=${ARRAY}"

sbatch -p "$PARTITION" -A "$ACCOUNT" --array="${ARRAY}" merge_barcode_bams_array.sh "${OUTDIR}" "${SAMTOOLS_IMG}"
