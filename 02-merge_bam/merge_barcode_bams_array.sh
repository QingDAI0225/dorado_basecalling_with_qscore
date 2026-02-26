#!/usr/bin/env bash
#SBATCH -J merge_bc_bam
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH -t 06:00:00
#SBATCH -o logs/%x_%A_%a.out
#SBATCH -e logs/%x_%A_%a.err

set -euo pipefail
mkdir -p logs

# ---------------- args ----------------
OUTDIR="${1:?usage: sbatch --array=0-(N-1)%M merge_barcode_bams_array.sh OUTDIR SAMTOOLS_IMG [THREADS]}"
SAMTOOLS_IMG="${2:?missing SAMTOOLS_IMG (your samtools apptainer image: .sif path or docker://...)}"
THREADS="${3:-${SLURM_CPUS_PER_TASK:-8}}"
# -------------------------------------

OUTDIR="${OUTDIR%/}"
PERPOD5="${OUTDIR}/per_pod5"
MERGED_DIR="${OUTDIR}/merged_bam"

SETUP_LOCK="${MERGED_DIR}/.setup.lock"
SETUP_DONE="${MERGED_DIR}/SETUP.DONE"
SETUP_FAIL="${MERGED_DIR}/SETUP.FAILED"

BARCODE_LIST="${MERGED_DIR}/barcodes.list"
MERGED_SUMMARY="${MERGED_DIR}/sequencing_summary_merged.txt"

mkdir -p "${MERGED_DIR}"

die() { echo "ERROR: $*" >&2; exit 1; }

# ======================= SETUP (only once, with lock) =======================
if [[ ! -f "${SETUP_DONE}" && ! -f "${SETUP_FAIL}" ]]; then
  (
    flock -n 9 || exit 0  # someone else is doing setup
    set -euo pipefail

    [[ -d "${PERPOD5}" ]] || { echo "PERPOD5 not found: ${PERPOD5}" > "${SETUP_FAIL}"; exit 1; }

    # ---- 1) Check all per_pod5/* have DONE.stamp and sequencing_summary.txt ----
    mapfile -t PODDIRS < <(find "${PERPOD5}" -mindepth 1 -maxdepth 1 -type d | sort)
    if (( ${#PODDIRS[@]} == 0 )); then
      echo "No pod5 subdirs under ${PERPOD5}" > "${SETUP_FAIL}"
      exit 1
    fi

    missing=0
    {
      echo "Missing files under per_pod5 (need DONE.stamp + sequencing_summary.txt):"
      for d in "${PODDIRS[@]}"; do
        [[ -f "${d}/DONE.stamp" ]] || { echo "  missing DONE.stamp : ${d}"; missing=$((missing+1)); }
        [[ -f "${d}/sequencing_summary.txt" ]] || { echo "  missing sequencing_summary.txt : ${d}"; missing=$((missing+1)); }
      done
    } > "${SETUP_FAIL}.tmp"

    if (( missing > 0 )); then
      mv "${SETUP_FAIL}.tmp" "${SETUP_FAIL}"
      exit 1
    else
      rm -f "${SETUP_FAIL}.tmp"
    fi

    # ---- 2) Build barcode list by scanning any depth for bam_pass/barcodeXX ----
    tmp_bc="${BARCODE_LIST}.tmp.$$"
    find "${PERPOD5}" -type d -path "*bam_pass/barcode*" -printf "%f\n" \
      | grep -E '^barcode[0-9]+$' \
      | sort -u > "${tmp_bc}"

    if ! [[ -s "${tmp_bc}" ]]; then
      echo "No barcode dirs found under ${PERPOD5} matching */bam_pass/barcodeXX" > "${SETUP_FAIL}"
      rm -f "${tmp_bc}"
      exit 1
    fi
    mv "${tmp_bc}" "${BARCODE_LIST}"

    # ---- 3) Merge sequencing_summary.txt (keep header once; append from line 2) ----
    tmp_sum="${MERGED_SUMMARY}.tmp.$$"
    mapfile -t SUMFILES < <(find "${PERPOD5}" -mindepth 2 -maxdepth 2 -type f -name "sequencing_summary.txt" | sort)

    if (( ${#SUMFILES[@]} == 0 )); then
      echo "No sequencing_summary.txt found under ${PERPOD5}/*/" > "${SETUP_FAIL}"
      rm -f "${tmp_sum}"
      exit 1
    fi

    cat "${SUMFILES[0]}" > "${tmp_sum}"
    for f in "${SUMFILES[@]:1}"; do
      tail -n +2 "${f}" >> "${tmp_sum}"
    done
    mv "${tmp_sum}" "${MERGED_SUMMARY}"

    date > "${SETUP_DONE}"
  ) 9>"${SETUP_LOCK}" || true
fi

# ======================= WAIT for setup completion =======================
if [[ -f "${SETUP_FAIL}" ]]; then
  cat "${SETUP_FAIL}" >&2
  exit 1
fi

for _ in $(seq 1 300); do
  [[ -f "${SETUP_DONE}" ]] && break
  [[ -f "${SETUP_FAIL}" ]] && { cat "${SETUP_FAIL}" >&2; exit 1; }
  sleep 2
done
[[ -f "${SETUP_DONE}" ]] || die "Setup did not complete (no ${SETUP_DONE})."

# ======================= Resolve array item (one barcode per task) =======================
: "${SLURM_ARRAY_TASK_ID:?This script must be run as a Slurm array job}"

mapfile -t BARCODES < "${BARCODE_LIST}"
TOTAL="${#BARCODES[@]}"
(( TOTAL > 0 )) || die "Barcode list empty: ${BARCODE_LIST}"

if (( SLURM_ARRAY_TASK_ID >= TOTAL )); then
  die "Array index ${SLURM_ARRAY_TASK_ID} out of range (TOTAL=${TOTAL})"
fi

BC="${BARCODES[$SLURM_ARRAY_TASK_ID]}"

OUT_BAM="${MERGED_DIR}/${BC}.bam"

echo "[$(date)] START barcode=${BC} task=${SLURM_ARRAY_TASK_ID}/${TOTAL} threads=${THREADS}"
echo "  OUTDIR        : ${OUTDIR}"
echo "  PERPOD5       : ${PERPOD5}"
echo "  MERGED_DIR    : ${MERGED_DIR}"
echo "  MERGED_SUMMARY: ${MERGED_SUMMARY}"
echo "  OUT_BAM       : ${OUT_BAM}"

# ======================= Collect BAMs for this barcode (temp list, auto-clean) =======================
TMPDIR_USE="${SLURM_TMPDIR:-/tmp}"
LIST="$(mktemp "${TMPDIR_USE}/${BC}.bams.list.XXXXXX")"
cleanup() { rm -f "${LIST}"; }
trap cleanup EXIT

find "${PERPOD5}" -type f -path "*bam_pass/${BC}/*.bam" | sort > "${LIST}"
N_BAMS=$(wc -l < "${LIST}" | tr -d ' ')

if (( N_BAMS == 0 )); then
  echo "No BAMs found for ${BC} (pattern *bam_pass/${BC}/*.bam). Nothing to do."
  exit 0
fi

# ======================= Merge BAMs (NO .bai, NO .bams.list output) =======================
if [[ -s "${OUT_BAM}" ]]; then
  echo "Exists, skip merge: ${OUT_BAM}"
else
  echo "Merging ${N_BAMS} BAMs -> ${OUT_BAM}"

  apptainer exec --bind "${OUTDIR}:${OUTDIR}" "${SAMTOOLS_IMG}" bash -lc "
    set -euo pipefail
    samtools merge -@ ${THREADS} -c -p -b '${LIST}' '${OUT_BAM}'
  "
fi

echo "[$(date)] DONE barcode=${BC}"
echo "  merged bam     : ${OUT_BAM}"
echo "  global summary : ${MERGED_SUMMARY}"
