#!/usr/bin/env bash
#SBATCH -J dorado_bc
#SBATCH -A chsi
#SBATCH -p chsi-gpu,gpu-common
#SBATCH --gres=gpu:2080:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH -t 12:00:00
#SBATCH -o logs/%x_%A_%a.out
#SBATCH -e logs/%x_%A_%a.err

set -euo pipefail
mkdir -p logs

POD5_DIR="${POD5_DIR:-/work/qd33/nanopore/20251020_MLI_PCO_20ng/MLI_PCO_20ng/20251020_1251_MN33275_FBD19880_80f4df29/pod5_skip}"
BIND="${BIND:-/work/qd33,/cwork/qd33}"
OUTDIR="${OUTDIR:-/work/qd33/data/basecalling_data/20251020_MLI_PCO_20ng_dorado131_trim}"
APPTAINER_IMG="${APPTAINER_IMG:-docker://ontresearch/dorado:sha00aa724a69ddc5f47d82bd413039f912fdaf4e77}"
KIT="${KIT:-SQK-NBD114-96}"
MODEL="${MODEL:-sup}"
# --------------------------------

APPTAINER_RUN=(apptainer -s run --nv --bind "${BIND}" "${APPTAINER_IMG}")

mapfile -t POD5S < <(find "$POD5_DIR" -type f -name "*.pod5" | sort)
N="${#POD5S[@]}"
if (( N == 0 )); then
  echo "No .pod5 found under: $POD5_DIR"
  exit 0
fi

: "${SLURM_ARRAY_TASK_ID:?Run as a Slurm array job}"
if (( SLURM_ARRAY_TASK_ID >= N )); then
  echo "Array index ${SLURM_ARRAY_TASK_ID} out of range (N=$N)"
  exit 1
fi

POD5="${POD5S[$SLURM_ARRAY_TASK_ID]}"
BASE="$(basename "$POD5" .pod5)"

TASK_OUT="${OUTDIR}/per_pod5/${BASE}"
mkdir -p "$TASK_OUT"

STAMP="${TASK_OUT}/DONE.stamp"
if [[ -f "$STAMP" ]]; then
  echo "[$(date)] DONE already exists, skipping: $POD5"
  exit 0
fi

THREADS="${SLURM_CPUS_PER_TASK:-8}"

echo "[$(date)] START"
echo "  POD5   : $POD5"
echo "  OUT    : $TASK_OUT"
echo "  KIT    : $KIT"
echo "  MODEL  : $MODEL"
echo "  THREADS: $THREADS"
echo "  INDEX  : ${SLURM_ARRAY_TASK_ID}/${N}"
echo "  IMG    : $APPTAINER_IMG"

"${APPTAINER_RUN[@]}" dorado basecaller "${MODEL}" "${POD5}" \
  --kit-name "${KIT}" \
  --emit-summary \
  --output-dir "${TASK_OUT}"
#  --reference /hpc/dctrl/qd33/reference_genome/reference.fasta \

date > "$STAMP"

echo "[$(date)] FINISH"
echo "  outputs:"
echo "    ${TASK_OUT}/calls_*.bam"
echo "    ${TASK_OUT}/sequencing_summary.txt"
