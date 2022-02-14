# Simulates data using Varsim+dwgsim, aligns it, piles it up and runs variant calling on it

genomes_dir="/cluster/work/grlab/projects/projects2019-secedo/genomes"
base_dir="/cluster/work/grlab/projects/projects2019-secedo/datasets/varsim"

# runs Varsim to generate a pattern for healthy cells based on the GRCh38_new.fa reference genome
# Inputs:
#  - the human reference genome in fasta format e.g. GRCh38_new.fa
#  - common variations on the reference genome, e.g. common_all_20180418.vcf.gz
# Outputs:
#  - one fasta file for the healthy cell

# don't forget to run: "conda activate py2" before running this script

# note the use of --disable_sim; this means that no reads are generated using Varsim (because it's slow and error
# prone). Instead we generate the reads ourself directly using art_illumina in the next step
function generate_healthy_genome() {
  out_dir="${base_dir}/genomes"

  if [ -f "${out_dir}/healthy.fa" ]; then
    echo "Genome for healthy cells already exists, skipping generation: ${out_dir}/healthy.fa"
    return
  fi

  mkdir -p ${out_dir}

  touch "${out_dir}/empty_file"

  cmd="time ${base_dir}/varsim-0.8.4/varsim.py --id healthy --vc_in_vcf ${base_dir}/genomes/common_all_20180418.vcf.gz \
     --reference ${genomes_dir}/GRCh38_new.fa \
     --read_length 100 --vc_num_snp 3000000 --vc_num_ins 100000 \
     --vc_num_del 100000 --vc_num_mnp 50000 --vc_num_complex 50000 \
     --sv_num_ins 0 --sv_num_del 0 --sv_num_dup 0 --sv_num_inv 0 --sv_insert_seq ${out_dir}/empty_file \
     --sv_dgv empty_file \
     --disable_sim \
     --simulator_executable doesnt_matter_we_are_not_simulating \
     --out_dir ${out_dir} --log_dir ${out_dir}/logs/ --work_dir ${out_dir}/tmp | tee 2>&1 ${out_dir}/logs/healthy.log"

  echo "Executing: $cmd"

  bsub -K -J "healthy" -W 1:00 -n 10 -R "rusage[mem=8000]" -R "span[hosts=1]" \
    -oo "${out_dir}/logs/healthy.lsf.log" "${cmd}" &
}

# runs Varsim to generate a pattern for a tumor cell based on the GRCh38_new.fa reference genome and the given
# "normal vcf" (which can actually be another tumor)
# Params:
# - number of SNPs, VCF of the base genome, name of the tumor genome
# Inputs:
#  - the human reference genome in fasta format e.g. GRCh38_new.fa
#  - common variations on the reference genome, e.g. common_all_20180418.vcf.gz
#  - a VCF file to draw mutations for the cancer cells from, e.g. cosmic.vcf.gz
# Outputs:
#  - one fasta+VCF file for the tumor cell
function generate_tumor_genome() {

  num_snps=$1 # how many SNPs to add to the new tumor genome (relative to the base genome)
  base_genome=$2
  tumor_genome=$3

  out_dir="${base_dir}/genomes"

  tumor_fasta="${out_dir}/${tumor_genome}/${tumor_genome}.fa"
  if [ -f ${tumor_fasta} ]; then
    echo "Tumor file ${tumor_fasta} already exists. Skipping generation"
    return
  fi

  if [ -f ${base_genome} ]; then
    echo "Using existing ${base_genome}"
  else
    echo -n "[$(date)] Waiting for ${base_genome} to be generated..."
    while [ ! -f ${base_genome} ]; do sleep 10; echo -n .;  done;
    echo "done"
  fi

  mkdir -p ${out_dir}

  touch "${out_dir}/empty_file"

  printf "\n\n\n"
  if [ ! -f ${base_genome} ]; then
    echo "The base genome ${base_genome} does not exist."
  fi

  seed=$(md5sum <<<"${tumor_genome}")
  seed=$((0x${seed%% *} % 10000))

  command="time python2 ${base_dir}/varsim-0.8.4/varsim_somatic.py \
          --reference ${genomes_dir}/GRCh38_new.fa \
          --id ${tumor_genome} \
          --seed ${seed#-} \
          --som_num_snp ${num_snps} \
          --som_num_ins 250 \
          --som_num_del 250 \
          --som_num_mnp 200 \
          --som_num_complex 200 \
          --cosmic_vcf ${base_dir}/cosmic/cosmic.vcf.gz \
          --normal_vcf ${base_genome} \
          --disable_sim \
          --simulator_executable ${out_dir}/empty_file \
          --out_dir ${out_dir}/${tumor_genome}/ \
          --log_dir ${out_dir}/logs/${tumor_genome} \
          --sv_insert_seq ${out_dir}/empty_file; \
           echo Finished | tee -a ${out_dir}/logs/${tumor_genome}.log"

  echo "[$(date)] Executing: ${command}" | tee "${out_dir}/logs/${tumor_genome}.log"

  # takes about 15 minutes
  bsub -K -J "${tumor_genome}" -W 1:00 -n 10 -R "rusage[mem=20000]" -R "span[hosts=1]" \
    -oo "${out_dir}/logs/${tumor_genome}.lsf.log" "${command}" &

  wait
}

if [ $CONDA_DEFAULT_ENV != "py2" ]; then
  echo "Varsim needs python2. Please activate py2 environment using 'conda activate py2'"
  exit
fi
module load jdk # varsim doesn't work with openjdk

# create the genome VCF+Fasta for the healthy cells
generate_healthy_genome

# create the first tumor cell, differing in 20K snps from the healthy cell
generate_tumor_genome 20000 "${base_dir}/genomes/healthy.truth.vcf" "tumor1-h-20K"
# tumor2 is based on tumor 1 and differs in 10K SNPs
generate_tumor_genome 10000 "${base_dir}/genomes/tumor1-h-20K/tumor1-h-20K.truth.vcf" "tumor2-1-10K"
# tumor3 is based on tumor 1 and differs in 15K SNPs
generate_tumor_genome 15000 "${base_dir}/genomes/tumor1-h-20K/tumor1-h-20K.truth.vcf" "tumor3-1-15K"
# tumor 7 differs in 5K SNPs from tumor 1
generate_tumor_genome 5000 "${base_dir}/genomes/tumor1-h-20K/tumor1-h-20K.truth.vcf" "tumor7-1-5K"
# tumor 4 differs in 10K SNPs from tumor 3
generate_tumor_genome 10000 "${base_dir}/genomes/tumor3-1-15K/tumor3-1-15K.truth.vcf" "tumor4-3-10K"
# tumor 5 differs in 5K SNPs from tumor 3
generate_tumor_genome 5000 "${base_dir}/genomes/tumor3-1-15K/tumor3-1-15K.truth.vcf" "tumor5-3-5K"
# tumor 6 differs in 7.5K SNPs from tumor 3
generate_tumor_genome 7500 "${base_dir}/genomes/tumor3-1-15K/tumor3-1-15K.truth.vcf" "tumor6-3-7.5K"
# tumor 8 differs in 2.5K SNPs from tumor 5
generate_tumor_genome 2500 "${base_dir}/genomes/tumor5-3-5K/tumor5-3-5K.truth.vcf" "tumor8-5-2.5K"
# tumor 9 differs in 1.250 SNPS from the healthy cell
generate_tumor_genome 1250 "${base_dir}/genomes/healthy.truth.vcf" "tumor9-h-1.25K"
# tumor 10 differs in 750 SNPS from the healthy cell
generate_tumor_genome 750 "${base_dir}/genomes/healthy.truth.vcf" "tumor10-h-0.75K"
# tumor 11 differs in 500 SNPS from the healthy cell
generate_tumor_genome 500 "${base_dir}/genomes/healthy.truth.vcf" "tumor11-h-0.5K"
