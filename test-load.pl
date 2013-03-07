#!/usr/bin/perl

my @a;
my $count;
do {
	while((my $l = <STDIN>) && $#a <=100) {
		chomp($l);
		push @a,$l;
	}
	$args =  join(" ",@a);
	if(system("rrdtool update hwc.rrd $args") != 0) {
		print $args,"\n";
		exit;
	}	
	undef @a;
	print "      \r",$count++;
} until eof(STDIN);
print;
