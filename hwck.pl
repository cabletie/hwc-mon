#!/usr/bin/perl 
#my $datafile = "hwc-raw.dat";
my $this = 0;
my $prev;
#open RAW,"<$datafile" || die "can't open $datafile: $!\n";
while(<>) {
	(@F) = split(/:/);
	$prev=$this;
	$this=$F[0];
#print $F[0],"\n";
	if($this > $prev)
	{
		print $_;
		next;
	}
	print STDERR "out of sequence at line $.: prev: $prev, this: $this\n";
	$this = $prev;
}
#close RAW;
