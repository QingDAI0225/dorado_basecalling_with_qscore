# dorado_basecalling_with_qscore

[![DOI](https://zenodo.org/badge/1167837858.svg)](https://doi.org/10.5281/zenodo.18942954)

Three-step Slurm workflow for Dorado basecalling/demultiplexing, merging BAMs by
barcode classification, and converting merged BAMs to compressed FASTQ.

`01-dorado_basecalling/submit_dorado_array.sh` accepts two barcode modes:

- `either_end`: Dorado's default double-ended barcode heuristic; a barcode can
  be classified from either end of a read.
- `both_ends`: adds `--barcode-both-ends`, requiring a matching barcode at both
  ends.

Always use separate output directories for the two modes. The workflow retains
the `unclassified` BAM/FASTQ alongside all `barcodeNN` outputs so that those
reads remain available for denominator audits.

Basecalling runs without reference alignment by default. To align during
basecalling, set `REFERENCE` when submitting:

```bash
REFERENCE=/path/to/reference.fasta ./01-dorado_basecalling/submit_dorado_array.sh POD5_DIR OUTDIR either_end
```
