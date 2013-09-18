#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Verbose;
use Data::Dumper;

# TODO config einlesen
#my %cfg = do "$FindBin::RealBin/../chloroExtractor.cfg";
#die "Config error" if($@);

my %options;

=head1 NAME 

chloroExtractor.pl

=head1 DESCRIPTION

Wrapper to extract chloroplast reads from genomic samples, assemble and annotate them.

=head1 USAGE

  $ perl chloroExtractor.pl --reads=<fasta> [--mates=<fasta>] [options]

=head1 OPTIONS

=over 25

=item --reads=<FASTQ>

path to the reads in fastq format


=cut

$options{'reads=s'} = \(my $opt_reads);

=item --mates=<FASTA>

path to the paired reads in fastq format


=cut

$options{'mates=s'} = \(my $opt_mates);

=item --phred=<INT>

Phred offset of the fastq files (default 33).
Sickle is called with --qual-type sanger, only if --phred=64 is selected it will be --qual-type illumina

=cut

$options{'phred=i'} = \(my $opt_phred=33);

=item --insertsize=<INT>

Insert size of the paired library as passed to downstream programs (default 200).

=cut

$options{'insertsize=i'} = \(my $opt_insertsize=200);

=item --insertsd=<INT>

Standard deviation of the insert size of paired library as passed to downstream programs (default 100).

=cut

$options{'insertsd=i'} = \(my $opt_insertsd=100);

=item --iterations=<INT>

Number of iterations for the final refinement of the assemblies (default 5).

=cut

$options{'iterations=i'} = \(my $opt_iterations=5);

=item [--prefix=<STRING>] 

prefix for the output files. Default is current directory and a prefix
 <query_file>_-_<reference_file>_-_<aligner>.

=cut

$options{'prefix=s'} = \(my $opt_prefix);

=item [--skip=<STRING>] 

Comma separated list of steps to skip:
1 Kmer counting, merging and histogramming
2 Find Chloro Peak
3 Dump Kmers
4 Filter Raw Reads
5 Dump Reads
6 Error correct Dumped Reads
7 Assemble Reads
8 Filter contigs
9 Iterative refinement

=cut

$options{'skip=s'} = \(my $opt_skip="");

=item [--jellyfish-kmer-size=<INT>] 

desired kmer size for jellyfish

=cut

$options{'jellyfish-kmer-size=i'} = \(my $opt_jellyfish_kmer_size=23);

=item [--velvet-kmer-size=<INT>] 

desired kmer size for velvet

=cut

$options{'velvet-kmer-size=i'} = \(my $opt_velvet_kmer_size=51);
	  
=item [--jellyfish-bin=<FILE>] 

Path to jellyfish binary file. Default tries if jellyfish is in PATH;

=cut

$options{'jellyfish-bin=s'} = \(my $opt_jellyfish_bin = `which jellyfish 2>/dev/null`);

=item [--allpath-correction-bin=<FILE>] 

Path to Allpath-correction executable (ErrorCorrectReads.pl). Default tries if ErrorCorrectReads.pl is in PATH;

=cut

$options{'allpath-correction-bin=s'} = \(my $opt_allpath_correction_bin = `which ErrorCorrectReads.pl 2>/dev/null`);

=item [--sickle-bin=<FILE>] 

Path to sickle executable. Default tries if sickle is in PATH;

=cut

$options{'sickle-bin=s'} = \(my $opt_sickle_bin = `which sickle 2>/dev/null`);

=item [--velvet-bin=<FILE>] 

Path to the velveth or velvetg binary file. Default tries if velveth is in PATH
The containing folder is used to find both velveth and velvetg.

=cut

$options{'velvet-bin=s'} = \(my $opt_velvet_bin = `which velveth 2>/dev/null`);


=item [--sspace-bin=<FILE>] 

Path to the sspace executable (eg SSPACE_Basic_v2.0.pl). Default tries if sspace is in PATH;

=cut

$options{'sspace-bin=s'} = \(my $opt_sspace_bin = `which SSPACE_Basic_v2.0.pl 2>/dev/null`);


=item [--shrimp-bin=<FILE>] 

Path to the shrimp executable (gmapper-ls). Default tries if gmapper-ls is in PATH;

=cut

$options{'shrimp-bin=s'} = \(my $opt_shrimp_bin = `which gmapper-ls 2>/dev/null`);


=item [--[no]verbose] 

verbose is default.

=cut

$options{'verbose!'} = \(my $opt_verbose = 1);

=item [--help] 

show help

=cut

$options{'help|?'} = \(my $opt_help);

=item [--man] 

show man page

=cut

$options{'man'} = \(my $opt_man);

=back






=head1 CODE

=cut


chomp($opt_jellyfish_bin,$opt_allpath_correction_bin,$opt_velvet_bin,$opt_sickle_bin,$opt_sspace_bin,$opt_shrimp_bin);
my $opt_velvet_path = dirname($opt_velvet_bin);

GetOptions(%options) or pod2usage(1);

my $vwga = Verbose->new(
	report_level => $opt_verbose // 0, #/
	format => "[{TIME_ELAPSED}] {MESSAGE}\n",
	line_width => 70
);

my $vbash = Verbose->new(
	report_level => $opt_verbose // 0, #/
	line_width => 70,
	line_delim => "\\\n",
);

my $vplain = Verbose->new(
	report_level => $opt_verbose // 0, #/
	line_width => 70,
);

pod2usage(1) if($opt_help);
pod2usage(-verbose => 99, -sections => "NAME|DESCRIPTION|USAGE|OPTIONS|AUTHORS") if($opt_man);

$vwga->verbose('Checking parameter');
pod2usage(-msg => "Missing parameter reads", -verbose => 0) unless ($opt_reads);
pod2usage(-msg => 'jellyfish not in $PATH and binary (--jellyfish-bin) not specified', -verbose => 0) unless ($opt_jellyfish_bin);
pod2usage(-msg => 'ErrorCorrectReads.pl not in $PATH and binary (--allpath-correction-bin) not specified', -verbose => 0) unless ($opt_allpath_correction_bin);
pod2usage(-msg => 'sickle not in $PATH and binary (--sickle-bin) not specified', -verbose => 0) unless ($opt_sickle_bin);
pod2usage(-msg => 'velvet not in $PATH and binary (--velvet-bin) not specified', -verbose => 0) unless ($opt_velvet_bin);
pod2usage(-msg => 'sspace not in $PATH and binary (--sspace-bin) not specified', -verbose => 0) unless ($opt_sspace_bin);
pod2usage(-msg => 'shrimp not in $PATH and binary (--shrimp-bin) not specified', -verbose => 0) unless ($opt_shrimp_bin);

my %skip = ();
$skip{$_} = 1 foreach split(/,/,$opt_skip);

$opt_prefix = get_prefix() unless $opt_prefix;
my ($prefix_name,$prefix_dir) = fileparse($opt_prefix);

if(exists $skip{1}){
	$vwga->verbose('Skipping kmer counting, merging und histogramming');
}
else{
	$vwga->verbose('Counting kmers');
	$vwga->hline();
	my $jellyfish_count_cmd = jellyfish_count_command();
	$vbash->verbose( $jellyfish_count_cmd );
	my $jellyfish_count_re = qx($jellyfish_count_cmd); 
	$vwga->nline();
	$vplain->verbose($jellyfish_count_re) if $jellyfish_count_re;
	$vwga->exit('ERROR: Counting kmers failed') if $?>> 8;
	
	$vwga->verbose('Merging kmer counts');
	$vwga->hline();
	my $jellyfish_merge_cmd = jellyfish_merge_command();
	$vbash->verbose( $jellyfish_merge_cmd );
	my $jellyfish_merge_re = qx($jellyfish_merge_cmd); 
	$vwga->nline();
	$vplain->verbose($jellyfish_merge_re) if $jellyfish_merge_re;
	$vwga->exit('ERROR: Merging kmer counts') if $?>> 8;
	
	$vwga->verbose('Histogramming kmer counts');
	$vwga->hline();
	my $jellyfish_histo_cmd = jellyfish_histo_command();
	$vbash->verbose( $jellyfish_histo_cmd );
	my $jellyfish_histo_re = qx($jellyfish_histo_cmd); 
	$vwga->nline();
	$vplain->verbose($jellyfish_histo_re) if $jellyfish_histo_re;
	$vwga->exit('ERROR: Histogramming kmer counts failed') if $?>> 8;
}

my $min;
my $max;
if(exists $skip{2}){
	$vwga->verbose('Skipping peak detection');
}
else{
	$vwga->verbose('Finding chloroplast peak in kmer histogram');
	$vwga->hline();
	my $findChloroPeak_cmd = findChloroPeak_command();
	$vbash->verbose( $findChloroPeak_cmd );
	my $findChloroPeak_re = qx($findChloroPeak_cmd); 
	$vwga->nline();
	$vplain->verbose($findChloroPeak_re) if $findChloroPeak_re;
	$vwga->exit('ERROR: Chloroplast peak detection failed') if $?>> 8;
}

get_min_max();

if(exists $skip{3}){
	$vwga->verbose('Skipping kmer dump');
}
else{
	$vwga->verbose('Dumping kmers in count range $min - $max');
	$vwga->hline();
	my $jellyfish_dump_cmd = jellyfish_dump_command();
	$vbash->verbose( $jellyfish_dump_cmd );
	my $jellyfish_dump_re = qx($jellyfish_dump_cmd); 
	$vwga->nline();
	$vplain->verbose($jellyfish_dump_re) if $jellyfish_dump_re;
	$vwga->exit('ERROR: Dumping kmers failed') if $?>> 8;
}

if(exists $skip{4}){
	$vwga->verbose('Skipping quality trimming');
}
else{
	$vwga->verbose('Quality trimming raw reads');
	$vwga->hline();
	my $quality_trimming_cmd = quality_trimming_command();
	$vbash->verbose( $quality_trimming_cmd );
	my $quality_trimming_re = qx($quality_trimming_cmd); 
	$vwga->nline();
	$vplain->verbose($quality_trimming_re) if $quality_trimming_re;
	$vwga->exit('ERROR: Quality trimming failed') if $?>> 8;
}

if(exists $skip{5}){
	$vwga->verbose('Skipping read dump');
}
else{
	$vwga->verbose('Dumping reads by kmer coverage');
	$vwga->hline();
	my $initial_read_dump_cmd = initial_read_dump_command();
	$vbash->verbose( $initial_read_dump_cmd );
	my $initial_read_dump_re = qx($initial_read_dump_cmd); 
	$vwga->nline();
	$vplain->verbose($initial_read_dump_re) if $initial_read_dump_re;
	$vwga->exit('ERROR: Dumping reads by kmer coverage failed') if $?>> 8;
}

if(exists $skip{6}){
	$vwga->verbose('Skipping error correction');
}
else{
	$vwga->verbose('Error correcting reads');
	$vwga->hline();
	my $error_correction_cmd = error_correction_command();
	$vbash->verbose( $error_correction_cmd );
	my $error_correction_re = qx($error_correction_cmd); 
	$vwga->nline();
	$vplain->verbose($error_correction_re) if $error_correction_re;
	$vwga->exit('ERROR: Error correcting reads failed') if $?>> 8;
}

########### velvet assembly
if(exists $skip{7}){
	$vwga->verbose('Skipping assembly');
}
else{
	$vwga->verbose('Assembly of the corrected reads');
	$vwga->hline();
	$vwga->verbose('Preparing assembly: velveth');
	$vwga->hline();
	my $velveth_cmd = velveth_command();
	$vbash->verbose( $velveth_cmd );
	my $velveth_re = qx($velveth_cmd); 
	$vwga->nline();
	$vplain->verbose($velveth_re) if $velveth_re;
	$vwga->exit('ERROR: velveth failed') if $?>> 8;
	$vwga->verbose('Executing assembly: velvetg');
	$vwga->hline();
	my $velvetg_cmd = velvetg_command();
	$vbash->verbose( $velvetg_cmd );
	my $velvetg_re = qx($velvetg_cmd); 
	$vwga->nline();
	$vplain->verbose($velvetg_re) if $velvetg_re;
	$vwga->exit('ERROR: velvetg failed') if $?>> 8;
}

########### contig Filtering (simple size filter)
if(exists $skip{8}){
	$vwga->verbose('Skipping contig filter');
}
else{
	$vwga->verbose('Filtering contigs by size');
	$vwga->hline();
	my $sizefilter_contigs_cmd = sizefilter_contigs_command();
	$vbash->verbose( $sizefilter_contigs_cmd );
	my $sizefilter_contigs_re = qx($sizefilter_contigs_cmd); 
	$vwga->nline();
	$vplain->verbose($sizefilter_contigs_re) if $sizefilter_contigs_re;
	$vwga->exit('ERROR: Filtering contigs by size failed') if $?>> 8;
}

########### Iteration
if(exists $skip{9}){
	$vwga->verbose('Skipping iterative assembly');
}
else{
	$vwga->verbose('Iterative assembly');
	$vwga->hline();
	for(my $i=1; $i<=$opt_iterations; $i++){
		my $assembly_file = "$prefix_dir"."iteration".($i-1)."/contigs_min2000.fa";
		$assembly_file = "$prefix_dir/contigs_min2000.fa" if $i==1;
		$vwga->verbose('Starting iteration '."$i");
		$vwga->hline();
		my $mkdir_cmd = "mkdir $prefix_dir/iteration$i";
		$vbash->verbose($mkdir_cmd);
		my $mkdir_re = qx($mkdir_cmd);
		$vplain->verbose($mkdir_re) if $mkdir_re;
		
		my $jellifish_count_cmd = "$opt_jellyfish_bin count -m $opt_jellyfish_kmer_size -o $prefix_dir/iteration$i/contigs -s 100000000 -t 20 --both-strands $assembly_file";
		$vbash->verbose( $jellifish_count_cmd );
		my $jellyfish_count_re = qx($jellifish_count_cmd); 
		$vwga->nline();
		$vplain->verbose($jellyfish_count_re) if $jellyfish_count_re;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in kmer counting step') if $?>> 8;
		
		my $jellifish_dump_cmd = "$opt_jellyfish_bin dump --column --tab -o $prefix_dir/iteration$i/chloro_kmers_dump.tsv $prefix_dir/iteration$i/contigs*";
		$vbash->verbose( $jellifish_dump_cmd );
		my $jellyfish_dump_re = qx($jellifish_dump_cmd); 
		$vwga->nline();
		$vplain->verbose($jellyfish_dump_re) if $jellyfish_dump_re;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in kmer dump step') if $?>> 8;
		
		my $read_dump_cmd = "perl $FindBin::Bin/Kmer.pl --kmers $prefix_dir/iteration$i/chloro_kmers_dump.tsv ";
		$read_dump_cmd .= "--reads $opt_prefix"."_trimmed_1.fq ";
		$read_dump_cmd .= "--mates $opt_prefix"."_trimmed_2.fq ";
		$read_dump_cmd .= "--out $prefix_dir/iteration$i/"."chloro_trimmed_dumped ";
		$read_dump_cmd .= "--histo $prefix_dir/iteration$i/"."trusted_kmers.histo ";
		$read_dump_cmd .= "--cutoff 60 --maxreads 200000 --notrustall";
		$vbash->verbose( $read_dump_cmd );
		my $read_dump_re = qx($read_dump_cmd); 
		$vwga->nline();
		$vplain->verbose($read_dump_re) if $read_dump_re;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in read dump step') if $?>> 8;
		
		my $error_correct_cmd = "$opt_allpath_correction_bin ";
		$error_correct_cmd .= "PHRED_ENCODING=$opt_phred READS_OUT=$prefix_dir/iteration$i/"."chloro_trimmed_dumped_corr ";
		$error_correct_cmd .= "PAIRED_READS_A_IN=$prefix_dir/iteration$i/"."chloro_trimmed_dumped_1.fq ";
		$error_correct_cmd .= "PAIRED_READS_B_IN=$prefix_dir/iteration$i/"."chloro_trimmed_dumped_2.fq ";
		$error_correct_cmd .= "PAIRED_SEP=$opt_insertsize PAIRED_STDEV=$opt_insertsd PLOIDY=1 THREADS=20";
		$vbash->verbose( $error_correct_cmd );
		my $error_correct_re = qx($error_correct_cmd); 
		$vwga->nline();
		$vplain->verbose($error_correct_re) if $error_correct_re;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in error correction step') if $?>> 8;
		
		# Create library file for sspace scaffolding
		my $library_txt = "$prefix_dir/iteration$i/"."library.txt";
		open(LIBRARY, ">$library_txt") or die "Can't open $library_txt $!";
		print LIBRARY "raw $opt_prefix"."_trimmed_dumped_corr.paired.A.fastq $opt_prefix"."_trimmed_dumped_corr.paired.B.fastq $opt_insertsize 0.5 FR\n";
		for(my $j=1; $j<=$i; $j++){
			print LIBRARY "iteration$j $prefix_dir/iteration$j/"."chloro_trimmed_dumped_corr.paired.A.fastq $prefix_dir/iteration$j/"."chloro_trimmed_dumped_corr.paired.B.fastq $opt_insertsize 0.5 FR\n";
		}
		close LIBRARY or die "$!";
		my $scaffolding_cmd = "perl $opt_sspace_bin -l $library_txt -s $assembly_file ";
		$scaffolding_cmd .= "-x 1 -T 20 -b iteration$i"."_sspace_x";
		# TODO scaffolding findet immer im Aufrufverzeichnis statt (notfalls schiebe Dateien anschliessend selbst ins korrekte Verzeichnis)
		$vbash->verbose( $scaffolding_cmd );
		my $scaffolding_re = qx($scaffolding_cmd); 
		$vwga->nline();
		$vplain->verbose($scaffolding_re) if $scaffolding_re;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in scaffolding step') if $?>> 8;
				
		#MAPPING
		my $mapping_cmd = "$opt_shrimp_bin --fastq --sam --global --qv-offset $opt_phred --threads 20 ";
		$mapping_cmd .= "--fuull-threshold 95\% --pair-mode opp-in --all-contigs --sam-unaligned --isize ";
		$mapping_cmd .= ($opt_insertsize-$opt_insertsd).",".($opt_insertsize+$opt_insertsd)." ";
		$mapping_cmd .= "-1 $prefix_dir/iteration$i/"."chloro_trimmed_dumped_corr.paired.A.fastq ";
		$mapping_cmd .= "-2 $prefix_dir/iteration$i/"."chloro_trimmed_dumped_corr.paired.B.fastq ";
		$mapping_cmd .= "$prefix_dir/iteration$i/sspace_x.final.scaffolds.fasta >$prefix_dir/iteration$i/mapping.sam ";
		$mapping_cmd .= "2>$prefix_dir/iteration$i/mapping.log ";
		$vbash->verbose( $mapping_cmd );
		my $mapping_re = qx($mapping_cmd); 
		$vwga->nline();
		$vplain->verbose($mapping_re) if $mapping_re;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in mapping step') if $?>> 8;
		my $sort_mapping_cmd = "sort $prefix_dir/iteration$i/mapping.sam $prefix_dir/iteration$i/shortReads.sam";
		$vbash->verbose($sort_mapping_cmd);
		my $sort_mapping_re = qx($sort_mapping_cmd);
		$vplain->verbose($sort_mapping_re) if $sort_mapping_re;
		#MAPPING
		
		my $velveth_cmd2 = "$opt_velvet_path/velveth ";
		$velveth_cmd2 .= "$prefix_dir/iteration$i $opt_velvet_kmer_size ";
		$velveth_cmd2 .= "-reference $prefix_dir/iteration$i/sspace_x.final.scaffolds.fasta";
		$velveth_cmd2 .= "-shortPaired -sam $prefix_dir/iteration$i/shortReads.sam";
		$vbash->verbose( $velveth_cmd2 );
		my $velveth_re2 = qx($velveth_cmd2); 
		$vwga->nline();
		$vplain->verbose($velveth_re2) if $velveth_re2;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in assembly (velveth) step') if $?>> 8;
	
		my $velvetg_cmd2 = "$opt_velvet_path/velvetg ";
		$velvetg_cmd2 .= "$prefix_dir/iteration$i -ins_length $opt_insertsize -exp_cov auto -scaffolding yes";
		$vbash->verbose( $velvetg_cmd2 );
		my $velvetg_re2 = qx($velvetg_cmd2); 
		$vwga->nline();
		$vplain->verbose($velvetg_re2) if $velvetg_re2;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in assembly (velvetg) step') if $?>> 8;
		
		my $seq_filter_cmd = "$FindBin::Bin/SeqFilter ";
		$seq_filter_cmd .= "--in $prefix_dir/iteration$i/contigs.fa ";
		$seq_filter_cmd .= "--min-length 2000 ";
		$seq_filter_cmd .= "--out $prefix_dir/iteration$i/contigs_min2000.fa ";
		$vbash->verbose( $seq_filter_cmd );
		my $seq_filter_re = qx($seq_filter_cmd); 
		$vwga->nline();
		$vplain->verbose($seq_filter_re) if $seq_filter_re;
		$vwga->exit('ERROR: Iterative assembly failed in iteration '."$i".' in contig filtering step') if $?>> 8;
	}
}

########### IR-Resolution

$vwga->verbose('chloroExtractor finished');


=head2 jellyfish_count_command

Returns the command to call jellyfish for counting.

=cut

sub jellyfish_count_command{
	my $cmd = "$opt_jellyfish_bin count -m $opt_jellyfish_kmer_size ";
	$cmd .= "-o $opt_prefix"."_jf_parts ";
	$cmd .= "-s 100000000 -t 20 --both-strands $opt_reads $opt_mates";
	return $cmd;
}

=head2 jellyfish_merge_command

Returns the command to call jellyfish for merging.

=cut

sub jellyfish_merge_command{
	if (-e "$opt_prefix"."_jf_parts_1"){
		my $cmd = "$opt_jellyfish_bin merge ";
		$cmd .= "-o $opt_prefix"."_full.jf ";
		$cmd .= "$opt_prefix"."_jf_parts*";
		return $cmd;
	}
	else{
		return "ln -s $opt_prefix"."_jf_parts_0 $opt_prefix"."_full.jf"
	}
}

=head2 jellyfish_histo_command

Returns the command to call jellyfish for histogramming.

=cut

sub jellyfish_histo_command{
	my $cmd = "$opt_jellyfish_bin histo ";
	$cmd .= "-o $opt_prefix"."_full_histo.jf ";
	$cmd .= "--threads 20 --high 100000 ";
	$cmd .= "$opt_prefix"."_full.jf";
	return $cmd;
}

=head2 jellyfish_dump_command

Returns the command to call jellyfish for dumping.

=cut

sub jellyfish_dump_command{
	my $cmd = "$opt_jellyfish_bin dump ";
	$cmd .= "--column --tab ";
	$cmd .= "-o $opt_prefix"."_dump_$min"."_$max".".jf ";
	$cmd .= "--lower-count=$min --upper-count=$max ";
	$cmd .= "$opt_prefix"."_full.jf";
	return $cmd;
}

=head2 findChloroPeak_command

Returns the command to call findChloroPeak.pl for chloroplast peak detection.

=cut

sub findChloroPeak_command{
	my $cmd = "perl $FindBin::Bin/findChloroPeak.pl ";
	$cmd .= "--histo $prefix_dir"."$prefix_name"."_full_histo.jf ";
	$cmd .= "--prefix $prefix_dir"."$prefix_name";
	return $cmd;
}

=head2 quality_trimming_command

Returns the command to call sickle for quality trimming of the raw reads.

=cut

sub quality_trimming_command{
	my $cmd = "$opt_sickle_bin pe ";
	my $offset_type = "sanger";
	$offset_type = "illumina" if($opt_phred == 64);
	$cmd .= "-f $opt_reads -r $opt_mates -t $offset_type ";
	$cmd .= "-o $opt_prefix"."_trimmed_1.fq ";
	$cmd .= "-p $opt_prefix"."_trimmed_2.fq ";
	$cmd .= "-s $opt_prefix"."_trimmed_singles.fq ";
	$cmd .= "-l 50";
	return $cmd;
}

=head2 initial_read_dump_command

Returns the command to call Kmer.pl for the initial dumping of reads (by kmer coverage).

=cut

sub initial_read_dump_command{
	my $cmd = "perl $FindBin::Bin/Kmer.pl ";
	$cmd .= "--kmers $opt_prefix"."_dump_$min"."_$max".".jf ";
	$cmd .= "--reads $opt_prefix"."_trimmed_1.fq ";
	$cmd .= "--mates $opt_prefix"."_trimmed_2.fq ";
	$cmd .= "--out $opt_prefix"."_trimmed_dumped ";
	$cmd .= "--histo $opt_prefix"."_trusted_kmers.histo ";
	$cmd .= "--cutoff 50 --maxreads 200000 --notrustall";
	return $cmd;
}

=head2 error_correction_command

Returns the command to call ErrorCorrectReads.pl for ErrorCorrection of the dumped reads.

=cut

sub error_correction_command{
	my $cmd = "$opt_allpath_correction_bin ";
	$cmd .= "PHRED_ENCODING=$opt_phred READS_OUT=$opt_prefix"."_trimmed_dumped_corr ";
	$cmd .= "PAIRED_READS_A_IN=$opt_prefix"."_trimmed_dumped_1.fq ";
	$cmd .= "PAIRED_READS_B_IN=$opt_prefix"."_trimmed_dumped_2.fq ";
	$cmd .= "PAIRED_SEP=$opt_insertsize PAIRED_STDEV=$opt_insertsd PLOIDY=1 THREADS=20";
	return $cmd;
}

=head2 velveth_command

Returns the command to call velveth.

=cut

sub velveth_command{
	my $cmd = "$opt_velvet_path/velveth ";
	$cmd .= "$prefix_dir $opt_velvet_kmer_size -fastq -shortPaired -separate ";
	$cmd .= "$opt_prefix"."_trimmed_dumped_corr.paired.A.fastq ";
	$cmd .= "$opt_prefix"."_trimmed_dumped_corr.paired.B.fastq ";
	return $cmd;
}

=head2 velvetg_command

Returns the command to call velvetg.

=cut

sub velvetg_command{
	my $cmd = "$opt_velvet_path/velvetg ";
	$cmd .= "$prefix_dir -ins_length $opt_insertsize -exp_cov auto -scaffolding yes";
	return $cmd;
}

=head2 sizefilter_contigs_command

Returns the command to call SeqFilter for filtering the contigs by length.

=cut

sub sizefilter_contigs_command{
	my $cmd = "$FindBin::Bin/SeqFilter ";
	$cmd .= "--in $prefix_dir/contigs.fa ";
	$cmd .= "--min-length 2000 ";
	$cmd .= "--out $prefix_dir/contigs_min2000.fa ";
	return $cmd;
}

=head2 get_prefix

Returns a default prefix if none is specified by the user. Style: <reads_-> (without .fq/.fastq)

=cut

sub get_prefix{
	my ($reads_name,$reads_path,$reads_suffix) = fileparse($opt_reads, qw(.fq .fastq));
	return './'.$reads_name.'_-';
}

=head2 get_min_max

Reads minimum and maximum from file

=cut

sub get_min_max{
	open(IN, "<$opt_prefix"."_minmax.tsv") or die "Can't open file $opt_prefix"."_minmax.tsv$!";
	($min, $max) = split(/\t/,<IN>);
	chomp $max;
	$max *= 3; # Take three times the maximal x value (expect IR at double)
}

=head1 LIMITATIONS

If you encounter a bug, please drop me a line.

=head1 AUTHORS

=over

=item * Markus Ankenbrand, markus.ankenbrand@stud-mail.uni-wuerzburg.de

=back


