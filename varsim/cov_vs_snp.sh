# Tests the minimum coverage that works for a given SNP number by simulating 2 groups of cells with the given
# SNP distance and given coverage and checking if the algorithm correctly clusters


# runs art_illumina to generate simulated reads for #n_cells cells with coverage #coverage
# Start jobs for generating both healthy and tumor reads and wait for the jobs to complete
function generate_reads() {
  echo "[$(date)] Generating reads..."

  module load bowtie2

  step=100

  art_illumina="/cluster/work/grlab/projects/projects2019-secedo/art_bin_MountRainier/art_illumina"
  gen_reads="python3 ${code_dir}/experiments/varsim/generate_reads.py"
  scratch_dir=$(mktemp -d -t genome-XXXXXXXXXX --tmpdir=/scratch)

  out_dir="${base_dir}/${cov}/reads"
  mkdir -p "${out_dir}/logs/"

  for tumor_type in 0 1; do
    out_prefix=${out_dir}/tumor_${tumor_type}_
    fasta=${fastas[${tumor_type}]}
    filename=$(basename -- "${fasta}")  # extract file name from path

    for batch in $(seq 0 ${step} $((n_cells[tumor_type]-1))); do
      cmd="echo [$(date)] Copying data...; mkdir -p ${scratch_dir}; cp ${fasta} ${scratch_dir}"
      cmd="$cmd;${gen_reads} --fasta ${scratch_dir}/${filename} --art ${art_illumina} -p 20 --id_prefix tumor_${tumor_type}_ \
          --start ${batch} --stop $((batch + step)) --out ${out_prefix} --coverage ${coverage} --seed_offset $((tumor_type*10000))  \
          2>&1 | tee ${out_dir}/logs/sim-tumor-${tumor_type}-${batch}.log"
      echo ${cmd}
      bsub  -K -J "sim-${tumor_type}-${batch}" -W 04:00 -n 20 -R "rusage[mem=4000,scratch=2000]" -R "span[hosts=1]" \
                  -oo "${out_dir}/logs/sim-tumor-${tumor_type}-${batch}.lsf.log" "${cmd}; rm -rf ${scratch_dir}" &
    done
  done

  wait
}


# align synthetic reads (tumor+healthy) generated e.g. by varsim to the reference genome,
# then filter and sort the resulting BAM file
# indexing is necessary because we are splitting the resulting aligned cells later by chromosome (samtools can only
# split indexed files).

# Starts jobs for mapping reads against the GRCh38 human genome and waits for the jobs to complete
# takes < 10 minutes
function map_reads() {
  echo "[$(date)] Mapping reads using bowtie2, sorting and splitting by chromosome..."
  step=10

  mkdir -p "${base_dir}/${cov}/aligned_cells"
  mkdir -p "${base_dir}/${cov}/aligned_cells_split"
  logs_dir="${base_dir}/${cov}/aligned_cells_split/logs"
  mkdir -p ${logs_dir}

  # Now map tumor cells
  for tumor_type in 0 1; do
    for idx in $(seq 0 ${step} $((n_cells[tumor_type]-1))); do
        cmd="echo hello"
        for i in $(seq "${idx}" $((idx+step-1))); do
          suf=$(printf "%03d" ${i})

          file1="${base_dir}/${cov}/reads/tumor_${tumor_type}_${i}.1.fq.gz"
          file2="${base_dir}/${cov}/reads/tumor_${tumor_type}_${i}.2.fq.gz"
          bam_file="${base_dir}/${cov}/aligned_cells/tumor_${tumor_type}_${suf}.bam"
          cmd="${cmd}; bowtie2 -p 20 -x ${base_dir}/genomes/ref_index/GRCh38 -1 $file1 -2 $file2 \
              | samtools view -h -b -f 0x2 -F 0x500 - \
              | samtools sort -@ 10 -o ${bam_file}; samtools index ${bam_file}; \
              ${code_dir}/experiments/varsim/split.sh ${bam_file} ${base_dir}/${cov}"
        done
        # echo "${cmd}"
        bsub -K -J "bt-${i}" -W 2:00 -n 20 -R "rusage[mem=800]" -R "span[hosts=1]"  -oo "${logs_dir}/bowtie-tumor-${i}.lsf.log" "${cmd}" &
    done
  done

  wait

}

# Starts jobs for creating pileup files from the aligned BAM files. One job per Chromosome.
# Waits for jobs to complete
function create_pileup() {
  module load openblas

  echo "[$(date)] Generating pileups..."
  out_dir="${base_dir}/${cov}/pileups"
  log_dir="${out_dir}/logs"
  pileup="${code_dir}/build/pileup"

  mkdir -p ${out_dir}
  mkdir -p ${log_dir}
  for chromosome in {1..22} X; do # Y was not added - maybe it confuses things
          scratch_dir=$(mktemp -d -t pileup-XXXXXXXXXX --tmpdir=/scratch)
          source_files=${base_dir}/${cov}/aligned_cells_split/*_chr${chromosome}.bam*
          num_files=`ls -l ${source_files} | wc -l`
          echo "Found ${num_files} files for chromosome ${chromosome}"
          copy_command="echo Copying data...; mkdir ${scratch_dir}; cp ${source_files} ${scratch_dir}"
          command="echo Running pileup binary...; ${pileup} -i ${scratch_dir}/ -o ${out_dir}/chromosome --num_threads 20 \
                  --log_level=trace --min_base_quality 30 --max_coverage 1000 \
                  --chromosomes ${chromosome} | tee ${log_dir}/pileup-${chromosome}.log"
          echo "Copy command: ${copy_command}"
          echo "Pileup command: $command"
          # allocating 40G scratch space; for the 1400 simulated Varsim cells, chromosomes 1/2 (the longest) need ~22G
          bsub  -K -J "pile-${chromosome}" -W 01:00 -n 20 -R "rusage[mem=4000,scratch=2000]" -R "span[hosts=1]" \
                -oo "${log_dir}/pileup-${chromosome}.lsf.log" "${copy_command}; ${command}; rm -rf ${scratch_dir}" &
  done

  wait
}

# Runs the variant caller on pileup files (either binary generated by our own pileup binary, or textual
# generated by samtools mpileup)
# ~5 minutes for 1000 cells coverage 0.05x
function variant_calling() {
  echo "[$(date)] Running variant calling..."
  module load openblas
  work_dir="${base_dir}/${cov}"
  input_dir="${work_dir}/pileups"
  silver="${code_dir}/build/silver"
  flagfile="${code_dir}/flags_sim"
  for hprob in 0.5; do
    for seq_error_rate in 0.05; do
      out_dir="${work_dir}/silver_${hprob#*.}_${seq_error_rate#*.}/"
      mkdir -p "${out_dir}"
      command="${silver} -i ${input_dir}/ -o ${out_dir} --num_threads 20 --log_level=trace --flagfile ${flagfile} \
             --homozygous_filtered_rate=${hprob} --seq_error_rate=${seq_error_rate} \
             --clustering_type SPECTRAL6 --merge_count 1 --max_coverage 1000 -min_cluster_size 50 \
             | tee ${out_dir}/silver.log"
             #       --pos_file=${base_dir}/cosmic/cosmic.vcf \
      echo "$command"

      bsub -K -J "silver" -W 03:00 -n 20 -R "rusage[mem=10000]" -R "span[hosts=1]" -oo "${out_dir}/silver.lsf.log" "${command}" &
    done
  done

  wait
}

# check the command-line arguments
if [ "$#" -ne 4 ]; then
            echo "Usage: main.sh <start_step> <coverage> <cell1.fa> <cell2.fa>"
            echo "start_step=1 -> Generate reads for healthy/tumor cells (~20 mins)"
            echo "start_step=2 -> Align reads against the human genome (~10 mins)"
            echo "start_step=3 -> Create pileup files (one per chromosome) (~10 mins)"
            echo "start_step=4 -> Run variant calling (~10 mins)\n\n"
            echo "For example: "
            echo "\t./cov_vs_snp.sh 1 0.02 tumor-20K-3 tumor-30K-6"
            exit 1
fi

action=$1
coverage=$2
cell1=$3
cell2=$4

base_dir="/cluster/work/grlab/projects/projects2019-secedo/datasets/varsim"
fastas=("${base_dir}/genomes/${cell1}/${cell1}.fa" "${base_dir}/genomes/${cell2}/${cell2}.fa")
snps=$(cut -d "-" -f3 <<< ${cell2})

cov="cov${coverage#*.}x_${snps}snp"  # e.g. cov01x_15Ksnp for coverage 0.01x and 15K snps
n_cells=(500 500) # number of  cells in each group
code_dir="$HOME/somatic_variant_calling/code"

echo "Writing to directory: ${cov}"

if (( action <= 1)); then
  generate_reads
fi
if (( action <= 2)); then
  map_reads
fi
if (( action <= 3)); then
  create_pileup
fi
if (( action <= 4)); then
  variant_calling
fi

