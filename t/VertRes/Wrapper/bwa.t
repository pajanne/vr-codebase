#!/usr/bin/perl -w
use strict;
use warnings;
use File::Copy;

BEGIN {
    use Test::Most tests => 41;
    
    use_ok('VertRes::Wrapper::bwa');
    use_ok('VertRes::IO');
}

my $bwa = VertRes::Wrapper::bwa->new(quiet => 1);
isa_ok $bwa, 'VertRes::Wrapper::WrapperI';
is $bwa->quiet, 1, 'quiet set via new';

is $bwa->exe, 'bwa', 'exe ok';
like $bwa->version, qr/\d\.\d.\d/, 'version ok';

# prepare our test files; copy them to a temp dir where we will do the tests
my $io = VertRes::IO->new();
my $temp_dir = $io->tempdir;
my $read1_basename = '2822_6_1_1000.fastq';
my $read2_basename = '2822_6_2_1000.fastq';
my $ref_basename = 'S_suis_P17.fa';
my $read1 = $io->catfile($temp_dir, $read1_basename);
my $read2 = $io->catfile($temp_dir, $read2_basename);
my $ref = $io->catfile($temp_dir, $ref_basename);
copy($io->catfile('t', 'data', $read1_basename), $read1);
copy($io->catfile('t', 'data', $read2_basename), $read2);
copy($io->catfile('t', 'data', $ref_basename), $ref);
ok -s $read1, 'test file 1 ready to use';
ok -s $read2, 'test file 2 ready to use';
ok -s $ref, 'test file 3 ready to use';

# the files we expect to be created
my $sai1 = $io->catfile($temp_dir, '2822_6_1_1000.sai');
my $sai2 = $io->catfile($temp_dir, '2822_6_2_1000.sai');
my $mapping = $io->catfile($temp_dir, 'mapping.sam');
my @ref_index_files;
foreach my $suffix (qw(amb ann bwt pac rbwt rpac rsa sa)) {
    push(@ref_index_files, $io->catfile($temp_dir, 'S_suis_P17.fa.'.$suffix));
}

# run the whole mapping
$bwa->do_mapping(ref => $ref,
                 read1 => $read1,
                 read2 => $read2,
                 output => $mapping,
                 index_a => 'is', sampe_a => 2000);
is $bwa->run_status, 1, 'status after mapping is ok';
my ($lines, $mapped) = check_sam($mapping);
is $lines, 2000, 'output sam not truncated';
cmp_ok $mapped, '>=', 1098, 'mapped enough reads';
foreach my $file ($sai1, $sai2, $mapping, @ref_index_files) {
    ok -s $file, 'output file exists';
    unlink($file);
}

# individual commands
$bwa->index($ref, a => 'is');
is $bwa->run_status, 1, 'status after index is ok';
foreach my $file (@ref_index_files) {
    ok -s $file, 'output file exists';
}

$bwa->aln($ref, $read1, $sai1);
is $bwa->run_status, 1, 'status after aln 1 is ok';
ok -s $sai1, 'sai 1 file created';
$bwa->aln($ref, $read2, $sai2);
is $bwa->run_status, 1, 'status after aln 2 is ok';
ok -s $sai2, 'sai 2 file created';

$bwa->sampe($ref, $sai1, $sai2, $read1, $read2, $mapping, a => 2000);
is $bwa->run_status, 1, 'status after sampe is ok';
ok -s $mapping, 'mapping file created';
($lines, my $mapped2) = check_sam($mapping);
is $lines, 2000, 'output sam not truncated';
cmp_ok $mapped2, '>=', 1098, 'mapped enough reads';
is $mapped, $mapped2, 'mapped the same number of reads both times';

exit;

sub check_sam {
    my $sam = shift;
    open(my $sfh, $sam) || return (0, 0);
    my $lines = 0;
    my $mapped = 0;
    while (<$sfh>) {
        next unless $_ =~ /\S/;
        $lines++;
        my @a = split;
        $mapped++ if $a[3];
    }
    return ($lines, $mapped);
}
