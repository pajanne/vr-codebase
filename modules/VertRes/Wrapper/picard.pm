=head1 NAME

VertRes::Wrapper::picard - wrapper for picard tools

=head1 SYNOPSIS

use VertRes::Wrapper::picard;

my $wrapper = VertRes::Wrapper::picard->new(validation_stringency => 'silent');

# Now you can call a method corrseponding to a picard tools jar.
# All methods take the filenames as a list to start with, followed by a hash
# of any additional options the picard jar understands.
$wrapper->MarkDuplicates($in_bam, $out_bam);
$wrapper->MergeSamFiles($out_bam, @bams_to_mergs);

# not yet wrapped:
$wrapper->CreateSequenceDictionary();
$wrapper->ValidateSamFile();
$wrapper->ViewSam();

=head1 DESCRIPTION

Runs picard tools in a nice way.

* not all picard tools have been wrapped yet*

=head1 AUTHOR

Sendu Bala: bix@sendu.me.uk

=cut

package VertRes::Wrapper::picard;

use strict;
use warnings;
use VertRes::IO;
use VertRes::Wrapper::samtools;
use VertRes::Parser::sam;

use base qw(VertRes::Wrapper::WrapperI);

my $io = VertRes::IO->new();
our $DEFAULT_PICARD_DIR = $io->catfile($ENV{BIN}, 'picard-tools');

=head2 new

 Title   : new
 Usage   : my $wrapper = VertRes::Wrapper::picard->new();
 Function: Create a VertRes::Wrapper::picard object.
 Returns : VertRes::Wrapper::picard object
 Args    : quiet   => boolean
           exe     => string (full path to the location of the picard tools jar
                              files; a TEAM145 default exists)
           validation_stringency => STRICT|LENIENT|SILENT (silent by default,
                                    overriden if VALIDATION_STRINGENCY is set
                                    directly in any other method call)
           tmp_dir => /tmp/dir (VertRes::IO->tempdir by default, overriden if
                                TMP_DIR is set directly in any other method
                                call)

=cut

sub new {
    my ($class, @args) = @_;
    
    my $self = $class->SUPER::new(@args);
    
    $self->{picard_dir} = $self->exe() || $DEFAULT_PICARD_DIR;
    $self->{base_exe} = 'java -Xmx5g -jar ';
    
    my $stringency = delete $self->{validation_stringency} || 'silent';
    $self->{_default_validation_stringency} = uc($stringency);
    
    my $temp_dir = delete $self->{tmp_dir} || $io->tempdir;
    $self->{_default_tmp_dir} = $temp_dir;
    
    return $self;
}

sub _handle_common_params {
    my ($self, $params) = @_;
    
    foreach my $key (qw(I INPUT O OUTPUT)) {
        delete $params->{$key};
    }
    
    unless (defined $params->{VALIDATION_STRINGENCY}) {
        $params->{VALIDATION_STRINGENCY} = $self->{_default_validation_stringency};
    }
    unless (defined $params->{TMP_DIR}) {
        $params->{TMP_DIR} = $self->{_default_tmp_dir};
    }
}

=head2 MergeSamFiles

 Title   : MergeSamFiles
 Usage   : $wrapper->MergeSamFiles('out.bam', @in_bams, %options);
 Function: MergeSamFiles...
 Returns : n/a
 Args    : list of file paths (output bam, input bams), followed by a hash of
           options understood by MergeSamFiles, eg. VALIDATION_STRINGENCY =>
           'SILENT'. (case matters: must be uppercase)

=cut

sub MergeSamFiles {
    my ($self, $out_bam, @args) = @_;
    
    $self->exe($self->{base_exe}.$io->catfile($self->{picard_dir}, 'MergeSamFiles.jar'));
    
    $self->switches([]);
    $self->params([qw(SORT_ORDER SO ASSUME_SORTED AS TMP_DIR VERBOSITY QUIET
                      VALIDATION_STRINGENCY COMPRESSION_LEVEL OPTIONS_FILE)]);
    
    my (@in_bams, @params);
    foreach my $arg (@args) {
        if (-e $arg && ! @params) {
            push(@in_bams, " I=$arg");
        }
        else {
            push(@params, $arg);
        }
    }
    my @file_args = (" O=$out_bam", @in_bams);
    
    my %params = @params;
    $self->_handle_common_params(\%params);
    
    $self->register_output_file_to_check($out_bam);
    $self->_set_params_and_switches_from_args(%params);
    
    return $self->run(@file_args);
}

=head2 MarkDuplicates

 Title   : MarkDuplicates
 Usage   : $wrapper->MarkDuplicates($in_bam, $out_bam, %options);
 Function: MarkDuplicates...
 Returns : n/a
 Args    : list of file paths (input bam, output bam), followed by a hash of
           options understood by MarkDuplicates, eg. VALIDATION_STRINGENCY =>
           'SILENT'. (case matters: must be uppercase)
           By default, METRICS_FILE (M) goes to /dev/null

=cut

sub MarkDuplicates {
    my ($self, $in_bam, $out_bam, %args) = @_;
    
    $self->exe($self->{base_exe}.$io->catfile($self->{picard_dir}, 'MarkDuplicates.jar'));
    
    $self->switches([]);
    $self->params([qw(METRICS_FILE M TMP_DIR VERBOSITY QUIET
                      VALIDATION_STRINGENCY COMPRESSION_LEVEL OPTIONS_FILE)]);
    
    my @file_args = (" I=$in_bam", " O=$out_bam");
    $self->_handle_common_params(\%args);
    unless (defined $args{M} || defined $args{METRICS_FILE}) {
        $args{M} = '/dev/null';
    }
    
    $self->register_output_file_to_check($out_bam);
    $self->_set_params_and_switches_from_args(%args);
    
    return $self->run(@file_args);
}

=head2 rmdup

 Title   : rmdup
 Usage   : $wrapper->rmdup($in_bam, $out_bam, %options);
 Function: rmdup creates an output bam file with duplicate reads physically
           removed, based on the output of MarkDuplicates().
 Returns : n/a
 Args    : list of file paths (input bam, output bam), followed by a hash of
           options understood by MarkDuplicates().

=cut

sub rmdup {
    my ($self, $in_bam, $out_bam, %args) = @_;
    
    # MarkDuplicates
    my $temp_dir = $io->tempdir;
    my $marked_bam = $io->catfile($temp_dir, 'marked.bam');
    my $orig_run_method = $self->run_method;
    $self->run_method('system');
    $self->MarkDuplicates($in_bam, $marked_bam, %args);
    $self->run_method($orig_run_method);
    $self->throw("failed during the MarkDuplicates step, giving up") unless $self->run_status >= 1;
    
    # use samtools to run through the bam, filter out dups, and create a new bam
    my $st = VertRes::Wrapper::samtools->new(quiet => 1);
    $st->run_method('open');
    my $fh = $st->view($marked_bam, undef, h => 1);
    $self->throw("failed during the first view step, giving up") unless $st->run_status >= 1;
    $fh || $self->throw("failed to get a filehandle from the view step, giving up");
    
    my $sp = VertRes::Parser::sam->new();
    
    my $total_lines = 0;
    my $dup_lines = 0;
    my $filtered_sam = $io->catfile($temp_dir, 'filtered.sam');
    open(my $fsfh, '>', $filtered_sam) || $self->throw("Could not write to $filtered_sam: $!");
    while (<$fh>) {
        if (/^@/) {
            print $fsfh $_;
            next;
        }
        
        $total_lines++;
        
        my (undef, $flag) = split(qr/\t/, $_);
        if ($sp->is_duplicate($flag)) {
            $dup_lines++;
        }
        else {
            print $fsfh $_;
        }
    }
    close($fh);
    close($fsfh);
    
    $st->run_method('system');
    my $tmp_bam = $out_bam.'_tmp';
    $st->view($filtered_sam, $tmp_bam, h => 1, S => 1, b => 1);
    $self->throw("failed during the second view step, giving up") unless $st->run_status >= 1;
    
    # check the output isn't truncated, or unlink it
    $st->run_method('open');
    undef($fh);
    $fh = $st->view($tmp_bam, undef, h => 1);
    my $bam_count = 0;
    while (<$fh>) {
        $bam_count++;
    }
    close($fh);
    my $expected_count = $total_lines - $dup_lines;
    if ($bam_count >= $expected_count) { # >= because it might have 1 or 2 extra header lines
        system("mv $tmp_bam $out_bam");
        $self->_set_run_status(2);
    }
    else {
        $self->warn("$tmp_bam.bam is bad ($bam_count lines vs $expected_count), will unlink it");
        $self->_set_run_status(-1);
        unlink("$tmp_bam.bam");
    }
    
    return;
}

sub _pre_run {
    my $self = shift;
    $self->_set_params_string(join => '=');
    return @_;
}

sub run {
    my $self = shift;
    
    # refuses to be quiet, so force the issue
    if ($self->quiet) {
        my $run_method = $self->run_method;
        $self->run_method('open');
        my $fh = $self->SUPER::run(@_);
        while (<$fh>) {
            next;
        }
        close($fh);
        $self->_post_run();
        $self->run_method($run_method);
    }
    else {
        return $self->SUPER::run(@_);
    }
}

1;