# Splits aligned BAM files by chromosome, creates 23 pileup files distributed on 23 machines and then runs
# variant calling

base_dir="/cluster/work/grlab/projects/projects2019-secedo/datasets/melanoma/processed_files/"
bam_dir="${base_dir}/aligned_cells"
split_dir="${base_dir}/aligned_cells_split"
pileup_dir="${base_dir}/pileups"
code_dir="/cluster/work/grlab/projects/projects2019-secedo/code"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"


# split the aligned BAMs by chromosome for easier parallelization
function split_bams() {
  echo "Splitting aligned BAMs by chromosome..."

  files=($(find ${bam_dir} -name *.bam ))
  n_cells=${#files[@]}
  echo "Found ${n_cells} cells"


  step=100
  mkdir -p "${split_dir}"
  logs_dir="${split_dir}/logs"
  mkdir -p ${logs_dir}

  for idx in $(seq 0 ${step} $((n_cells-1))); do
    echo "Processing files ${idx}->$((idx+step-1))..."
    cmd="echo hello"
    for i in $(seq "${idx}" $((idx+step-1))); do
      bam_file=${files[${i}]}
      cmd="${cmd}; ${code_dir}/experiments/melanoma/split.sh ${bam_file} ${split_dir} | tee ${logs_dir}/split-${i}.log"
    done
    # echo "${cmd}"
    bsub -K -J "split-${i}" -W 1:00 -n 1 -R "rusage[mem=8000]" -R "span[hosts=1]" \
        -oo "${logs_dir}/split-${i}.lsf.log" "${cmd}" &
  done

  wait
}

# Starts jobs for creating pileup files from the aligned BAM files. One job per Chromosome.
# Waits for jobs to complete
function create_pileup() {
  echo "Generating pileups..."
  log_dir="${pileup_dir}/logs"
  pileup="${code_dir}/build/pileup"

  mkdir -p ${pileup_dir}
  mkdir -p ${log_dir}
  for chromosome in {1..22} X; do # Y was not added - maybe it confuses things
          scratch_dir="/scratch/pileup_${chromosome}"
          source_files=${split_dir}/*_chr${chromosome}.bam*
          num_files=`ls -l ${source_files} | wc -l`
          echo "Found ${num_files} files for chromosome ${chromosome}"
          copy_command="echo Copying data...; mkdir ${scratch_dir}; cp ${source_files} ${scratch_dir}"
          command="echo Running pileup binary...; ${pileup} -i ${scratch_dir}/ -o ${pileup_dir}/chromosome \
              --num_threads  20 --log_level=trace --min_base_quality 30 --max_coverage 1000 \
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
  echo "Running variant calling..."
  module load openblas
  silver="${code_dir}/build/silver"
  flagfile="${code_dir}/flags_breast"
  for hprob in 0.5; do
    for seq_error_rate in 0.05; do
      out_dir="${base_dir}/silver_${hprob#*.}_${seq_error_rate#*.}/"
      log_dir="${out_dir}/logs/"
      mkdir -p "${log_dir}"
      command="${silver} -i ${pileup_dir}/ -o ${out_dir} --num_threads 20 --log_level=trace --flagfile ${flagfile} \
               --homozygous_filtered_rate=${hprob} --seq_error_rate=${seq_error_rate} \
               --clustering_type SPECTRAL6 --merge_count 1 --max_coverage 100 | tee ${log_dir}/silver.log"
      echo "$command"

      bsub -K -J "silver" -W 01:00 -n 20 -R "rusage[mem=20000]" -R "span[hosts=1]" -oo "${log_dir}/silver.lsf.log" \
           "${command}" &
    done
  done

  wait
}

# check the command-line arguments
if [ "$#" -ne 1 ]; then
            echo "Usage: main.sh <start_step>"
            echo "start_step=1 -> Split aligned BAMs by chromosome (~10 mins)"
            echo "start_step=2 -> Create pileup files (one per chromosome) (~10 mins)"
            echo "start_step=3 -> Run variant calling (~20 mins/cluster)"
            exit 1
fi

action=$1

if (( action <= 1)); then
  split_bams
fi
if (( action <= 2)); then
  create_pileup
fi
if (( action <= 3)); then
  variant_calling
fi
