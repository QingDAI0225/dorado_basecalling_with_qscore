#!/usr/bin/env bash
set -euo pipefail

MERGED_DIR="${1:?usage: launch_bam2fq.sh MERGED_DIR SAMTOOLS_IMG [OUT_DIR] [MAX_CONCURRENT] [THREADS]}"
SAMTOOLS_IMG="${2:-docker://quay.io/biocontainers/samtools:1.22.1--h96c455f_0}"
OUT_DIR="${3:-$MERGED_DIR}"
MAX_CONCURRENT="${4:-50}"
THREADS="${5:-8}"
PARTITION="chsi"
ACCOUNT="chsi"

MERGED_DIR="${MERGED_DIR%/}"
OUT_DIR="${OUT_DIR%/}"

N=$(find "$MERGED_DIR" -maxdepth 1 -type f -name 'barcode*.bam' | wc -l | tr -d ' ')
if [[ "$N" == "0" ]]; then
  echo "No barcode*.bam found in $MERGED_DIR"
  exit 1
fi

ARRAY_MAX=$((N-1))
echo "Found $N BAMs. Submitting array 0-$ARRAY_MAX % $MAX_CONCURRENT"
echo "OUT_DIR=$OUT_DIR THREADS=$THREADS"

sbatch \
  -p "$PARTITION" -A "$ACCOUNT" \
  --cpus-per-task="$THREADS" \
  --array=0-"$ARRAY_MAX"%"$MAX_CONCURRENT" \
  bam_to_fastq_array.sh "$MERGED_DIR" "$SAMTOOLS_IMG" "$THREADS" "$OUT_DIR"
