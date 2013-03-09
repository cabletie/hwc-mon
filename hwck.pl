#!/usr/bin/perl 
# Processes raw data file, removing out of sequence sections
# only passes through data after

use Getopt::Long;
use RRDp;

# Time after which data will be passed through
my $after = 0;
# rrd filename
my $rrd = "hwc.rrd";
# Input raw data file name
my $input;

my $this = 0;
my $prev;
my $answer;
my $processed;
my $skipped;

my $result = GetOptions ("after=i" => \$after,
	"rrd=s" => \$rrd,
	"input=s" => \$input,
);

if($input) {
	open STDIN,"<$input" || die "can't open $input: $!\n";
}

RRDp::start "/usr/local/bin/rrdtool";

while(<>) {
	(@F) = split(/:/);
	$prev=$this;
	$this=$F[0];
	#next unless $this > $after;
	if($this <= $after) {
		if(! $skipped) {
			print STDERR "skipping ...";
			$skipped = 1;
		}
		next;
	}
	if($skipped and !$processed) {
		print STDERR "processing\n";
		$processed = 1;
	}
	if($this > $prev)
	{
		RRDp::cmd "update","hwc.rrd","$_";
		$answer = RRDp::read;
		#print $_;
		next;
	}
	print STDERR "out of sequence at line $.: prev: $prev, this: $this\n";
	$this = $prev;
}
RRDp::end;
close STDIN;
close STDOUT;
close STDERR;
