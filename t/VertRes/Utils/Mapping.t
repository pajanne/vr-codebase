#!/usr/bin/perl -w
use strict;
use warnings;

BEGIN {
    use Test::Most tests => 28;
    
    use_ok('VertRes::Utils::Mapping');
    use_ok('VertRes::IO');
}

my $mapping_util = VertRes::Utils::Mapping->new();
isa_ok $mapping_util, 'VertRes::Base';

# setup our input files
my $io = VertRes::IO->new();
my $ref_file = $io->catfile('t', 'data', 'S_suis_P17.dna');
ok -s $ref_file, 'ref file ready to test with';
my $faq1_file = $io->catfile('t', 'data', '2822_6_1_1000.fastq');
ok -s $faq1_file, 'faq1 file ready to test with';
my $faq2_file = $io->catfile('t', 'data', '2822_6_2_1000.fastq');
ok -s $faq2_file, 'faq2 file ready to test with';

# simple methods
is $mapping_util->lane_to_module('/path/to/SLX/lane'), 'VertRes::Utils::Mappers::bwa', 'SLX lane leads to bwa';
is $mapping_util->lane_to_module('/path/to/454/lane'), 'VertRes::Utils::Mappers::ssaha', '454 lane leads to ssaha';
throws_ok { $mapping_util->wrapper } qr/This is supposed to be overriden/, 'wrapper is supposed to be overriden';
throws_ok { $mapping_util->do_mapping } qr/This is supposed to be overriden/, 'do_mapping is supposed to be overriden';
is_deeply $mapping_util->_bsub_opts, { bsub_opts => '' }, '_bsub_opts empty by default';

my %mapping_converter = (insert_size => 'foo');
throws_ok { $mapping_util->_do_mapping_args(\%mapping_converter, read0 => $faq1_file) } qr/ref is required/, '_do_mapping_args throws when no ref';
throws_ok { $mapping_util->_do_mapping_args(\%mapping_converter, read0 => $faq1_file, ref => 'foo') } qr/ref file .+ must exist/, '_do_mapping_args throws when ref doesn\'t exist';
throws_ok { $mapping_util->_do_mapping_args(\%mapping_converter, read0 => $faq1_file, ref => $ref_file) } qr/output is required/, '_do_mapping_args throws when no output';
is_deeply {$mapping_util->_do_mapping_args(\%mapping_converter, read0 => $faq1_file, ref => $ref_file, output => 'out', foo => 'bar')}, {ref => $ref_file, output => 'out', foo => 2000, read0 => $faq1_file}, '_do_mapping_args test';

throws_ok { $mapping_util->_do_read_args() } qr/read0 or read1 & read2 must be supplied/, '_do_read_args throws when no args';
throws_ok { $mapping_util->_do_read_args(read0 => 'foo', read1 => 'bar') } qr/read0 and read1\/2 are mutually exclusive/, '_do_read_args throws when mixed read0 and 1/2';
throws_ok { $mapping_util->_do_read_args(read0 => 'foo') } qr/read0 file .+ must exist/, '_do_read_args throws when read0 nonexistant';
is_deeply {$mapping_util->_do_read_args(read0 => $faq1_file)}, { read0 => $faq1_file }, '_do_read_args works with a real read0';
throws_ok { $mapping_util->_do_read_args(read1 => 'foo') } qr/read2 must be supplied with read1/, '_do_read_args throws when read1 but no read2';
throws_ok { $mapping_util->_do_read_args(read2 => 'foo') } qr/read1 must be supplied with read2/, '_do_read_args throws when read2 but no read1';
throws_ok { $mapping_util->_do_read_args(read1 => 'foo', read2 => 'foo') } qr/read1 file .+ must exist/, '_do_read_args throws when read1 nonexistant';
throws_ok { $mapping_util->_do_read_args(read1 => $faq1_file, read2 => 'foo') } qr/read2 file .+ must exist/, '_do_read_args throws when read2 nonexistant';
is_deeply {$mapping_util->_do_read_args(read1 => $faq1_file, read2 => $faq2_file)}, { read1 => $faq1_file, read2 => $faq2_file }, '_do_read_args works with a real read1 & read2';

# split_fastq (basically just an alias to VertRes::Utils::FastQ::split, which
# is already well tested in the FastQ.t script - just a basic check needed here)
my $temp_dir = $io->tempdir();
is $mapping_util->split_fastq(read0 => $faq1_file,
                              split_dir => $temp_dir,
                              chunk_size => 6100), 10, 'split_fastq with one fastq worked';
is $mapping_util->split_fastq(read1 => $faq1_file,
                              read2 => $faq2_file,
                              split_dir => $temp_dir,
                              chunk_size => 11500), 10, 'split_fastq with two fastqs worked';


TODO: {
    local $TODO = "Currently unused methods that are difficult to test for";
    ok 0, 'mapping_hierarchy_report() test';
    ok 0, 'get_mapping_stats';
}

exit;