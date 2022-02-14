DIR="/Volumes/Elements"
OLD_BAM="${DIR}/possorted_bam.bam"
NEW_BAM="${DIR}/possorted_bam_filtered.bam"
LOG="log_1_filtering"
echo > $LOG

echo "Number of reads in the original BAM:" >> $LOG
samtools view -@ 4 -c $OLD_BAM >> $LOG
echo >> $LOG

#### filtering
# -h: include the header in the output
# -b: output in BAM
# filter: -f 0x2 ... read mapped in proper pair
#       -F 0x100 ... not not primary alignment (= primary alignment)
#       -F 0x400 ... not PCR or optical duplicate
echo "Filtering" >> $LOG
echo "samtools view -h -b -f 0x2 -F 0x500 $OLD_BAM > $NEW_BAM" >> $LOG
samtools view -h -b -f 0x2 -@ 4 -F 0x500 $OLD_BAM > $NEW_BAM
echo "Number of reads after filtering:" >> $LOG
samtools view -@ 2 -c $NEW_BAM  >> $LOG
echo >> $LOG