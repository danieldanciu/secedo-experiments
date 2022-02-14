slice="C"
DIR="/cluster/work/grlab/projects/projects2019-secedo/10x_data_breastcancer/slice${slice}/"
NEW_BAM2=$DIR"processed_files/breast_tissue_${slice}_2k_possorted_bam_filtered_withCBtag.bam"
NEW_BAM2_SORTED=$DIR"processed_files/breast_tissue_${slice}_2k_possorted_bam_filtered_withCBtag_sorted.bam"
CELL_BAMS_DIR=$DIR"processed_files/cell_bams/"
TAGS_FILE=$DIR"processed_files/allowedTags"
PER_CELL_SUMMARY_FILE=$DIR"breast_tissue_${slice}_2k_per_cell_summary_metrics.csv"
BAM_LIST=$CELL_BAMS_DIR"list_of_bams"
LOG="log_3_splittingByCB"
echo > $LOG

##### split based on CB tag to many smaller sam files
# first sort the file based on CB tag
echo "Sort by CB tag" >> $LOG
scratch_dir="/scratch/slice${slice}"
copy_command="echo Creating ${scratch_dir}...; mkdir -p ${scratch_dir}"
sort_cmd="samtools sort -t CB -m 10G -@ 10 -T ${scratch_dir} ${NEW_BAM2} > ${NEW_BAM2_SORTED}"
echo ${sort_cmd} >> $LOG

bsub  -K -J "sort_slice${slice}" -W 24:00 -n 10 -R "rusage[mem=22000,scratch=30000]" -R "span[hosts=1]" \
                -oo "${LOG}.lsf.log" "${copy_command}; ${sort_cmd}; rm -rf ${scratch_dir}" &

echo >> $LOG
wait

# allowed tags
cat $PER_CELL_SUMMARY_FILE | cut -d ',' -f 1 | tail -n +2 > $TAGS_FILE

# then create a separate file for each allowed tag
echo "Splitting based on CB tag" >> $LOG
mkdir -p $CELL_BAMS_DIR
echo "python3 ~/sc_clustering/split_by_CBtag.py -f $NEW_BAM2_SORTED -o $CELL_BAMS_DIR -t $TAGS_FILE" >> $LOG
python3 ../../split_by_CBtag.py -f $NEW_BAM2_SORTED -o $CELL_BAMS_DIR -t $TAGS_FILE
