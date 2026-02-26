#!/usr/bin/env bash
#SBATCH -J bam2fq
#SBATCH -A chsi
#SBATCH -p chsi
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH -t 12:00:00
#SBATCH -o logs/%x_%A_%a.out
#SBATCH -e logs/%x_%A_%a.err

set -euo pipefail
mkdir -p logs

MERGED_DIR="${1:?usage: sbatch --array=0-(N-1)%M bam_to_fastq_array.sh MERGED_DIR SAMTOOLS_IMG [THREADS] [OUT_DIR]}"
SAMTOOLS_IMG="${2:?missing SAMTOOLS_IMG (your samtools apptainer image .sif or docker://...)}"
THREADS="${3:-${SLURM_CPUS_PER_TASK:-8}}"
OUT_DIR="${4:-$MERGED_DIR}"

MERGED_DIR="${MERGED_DIR%/}"
OUT_DIR="${OUT_DIR%/}"

[[ -d "$MERGED_DIR" ]] || { echo "MERGED_DIR not found: $MERGED_DIR" >&2; exit 1; }
mkdir -p "$OUT_DIR"

mapfile -t BAMS < <(find "$MERGED_DIR" -maxdepth 1 -type f -name 'barcode*.bam' | sort)
TOTAL="${#BAMS[@]}"
if (( TOTAL == 0 )); then
  echo "No barcode*.bam found in $MERGED_DIR"
  exit 0
fi

: "${SLURM_ARRAY_TASK_ID:?Run as array job}"
if (( SLURM_ARRAY_TASK_ID >= TOTAL )); then
  echo "Array index ${SLURM_ARRAY_TASK_ID} out of range (TOTAL=$TOTAL)" >&2
  exit 1
fi

BAM="${BAMS[$SLURM_ARRAY_TASK_ID]}"
BASE="$(basename "$BAM" .bam)"
OUT_FQ="${OUT_DIR}/${BASE}.fastq.gz"
DONE_STAMP="${OUT_DIR}/${BASE}.fastq.DONE.stamp"

echo "[$(date)] START  ${BASE}  task=${SLURM_ARRAY_TASK_ID}/${TOTAL}"
echo "  BAM     : $BAM"
echo "  OUT_FQ  : $OUT_FQ"

if [[ -s "$OUT_FQ" && -f "$DONE_STAMP" ]]; then
  echo "Already done, skip: $OUT_FQ"
  exit 0
fi

apptainer exec \
  --bind "$MERGED_DIR":"$MERGED_DIR","$OUT_DIR":"$OUT_DIR" \
  "$SAMTOOLS_IMG" \
  bash -lc "
    set -euo pipefail
    BAM='$BAM'
    OUT='$OUT_FQ'
    T='$THREADS'

    TMP_OUT=\"\${OUT}.tmp.\$\$\"

    if command -v pigz >/dev/null 2>&1; then
      samtools fastq -@ \"\$T\" -n \"\$BAM\" | pigz -p \"\$T\" -c > \"\$TMP_OUT\"
    else
      samtools fastq -@ \"\$T\" -n \"\$BAM\" | gzip -c > \"\$TMP_OUT\"
    fi

    mv -f \"\$TMP_OUT\" \"\$OUT\"
  "

date > "$DONE_STAMP"
echo "[$(date)] DONE   ${BASE}"
