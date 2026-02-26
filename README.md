# dorado_basecalling_with_qscore

A modular Dorado basecalling pipeline with multiplex support, optional alignment, reads quality summary, and downstream format conversion, organized into structured and reproducible steps.

---

## Repository structure

- `01-dorado_basecalling`
  - Perform basecalling with Dorado
  - Generate per-pod5 multiplex results
  - Produce a sequencing summary file
  - Optional: Supports internal alignment using Dorado’s built-in minimap2 integration against a provided reference dataset.
- `02-merge_bam`
  - Merges per-pod5 demultiplexed BAM files by identical barcode
- `03-bam_to_fastq`
  - Converts merged BAM files (per barcode) into FASTQ format
  
