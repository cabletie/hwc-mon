#!/usr/bin/perl
use strict;
use POSIX qw(setsid);
#use Proc::Daemon;
#use Proc::PID::File;
#use LWP::Simple;

use Device::SerialPort;
use Time::Format qw(%time %strftime %manip);
#use GetOpts::Long;

# Clear output buffering
$|=1;

# Pop into the background
&daemonize;

my $PortName = "/dev/ttyAMA0";
my $Configuration_File_Name = ".hwc-config";
my $PortObj; 
my $pidfile = "/var/run/hwc.pid";

#print "timestamp,inlet,roof,tank,pump,inlet_raw,roof_raw,tank_raw,pump_raw\n";

	$PortObj = new Device::SerialPort ($PortName, 0)
		|| die "Can't open $PortName: $!\n";

	$PortObj->baudrate(4800);
	$PortObj->parity("none");
	$PortObj->databits(8);
	$PortObj->stopbits(1);
	$PortObj->handshake("none");
	$PortObj->read_const_time(1000);  
 #$PortObj->debug(0);

	$PortObj->write_settings;

open(RRD,">>/home/peter/hwc/hwc.rrd") || die "Failed to open log file for appending: $!\n";;

# Make RRD filehandle hot so output is not buffered.
my $ofh = select RRD;
	  $| = 1;
	  select $ofh;

# Loop forever
while(1) {
	my $InBytes = 1;
	my $string_in = ' ';
	my $hex;
	my @bytes;
	$PortObj->purge_all;

	# Loop until we find a 0xf0 frame flag
	while(1) {
		(my $count_in, $string_in) = $PortObj->read($InBytes);
		die "read unsuccessful (got $count_in bytes, expected $InBytes)\n" unless ($count_in == $InBytes);

		$hex = unpack ('C',$string_in);
		last if $hex == 0xf0;
	}

	# Read 1 byte at a time, inserting each value into it's register
	$InBytes = 1;
	for (0..6) {
		(my $count_in, $string_in) = $PortObj->read($InBytes);
		warn "read unsuccessful (got $count_in bytes, expected $InBytes)\n" unless ($count_in == $InBytes);

		(my $byte) = unpack ('C',$string_in);
		my $reg = ($byte & 0xf0) >> 4;
		my $val = ($byte & 0x0f);
		$bytes[$reg] = $val;
		#print "reg[$reg] = $val\n";
	}

# These are figures from qualitative measurements between
# read and actual measurements
# T = mX + c
# X is register value read from serial port
#
	my $m = 1.011491061;
	my $c = -50.49657516;
	my $roof_raw = ($bytes[1] << 4) + $bytes[0];
	my $tank_raw = ($bytes[3] << 4) + $bytes[2];
	my $inlet_raw = ($bytes[5] << 4) + $bytes[4];
	my $pump_raw = $bytes[6];
	my $roof = ($roof_raw * $m) + $c;
	my $inlet = ($inlet_raw * $m) + $c;
	my $tank = ($tank_raw * $m) + $c;
	my $pump = ($pump_raw & 0x02) >> 1;

# Insert timestamp
print RRD time;
#	print "$time{'yyyymmdd.hhmmss'},";
	printf RRD (":%0.2f:%0.2f:%0.2f:%d:%02x:%02x:%02x:%d\n",$inlet,$roof,$tank,$pump,$inlet_raw,$roof_raw,$tank_raw,$pump_raw);
	#printf(:"%0.2f:%0.2f:%0.2f:%d:%02x:%02x:%02x:%08b\n",$inlet,$roof,$tank,$pump,$inlet_raw,$roof_raw,$tank_raw,$pump_raw);
	sleep(5);
}

close RRD;
close TTY;

# here is where we make ourself a daemon
sub daemonize {
	chdir '/' or die "Can’t chdir to /: $!";
	open STDIN, '/dev/null' or die "Can’t read /dev/null: $!";
	open STDOUT, '>>/dev/null' or die "Can’t write to /dev/null: $!";
	open STDERR, '>>/dev/null' or die "Can’t write to /dev/null: $!";
	defined(my $pid = fork) or die "Can’t fork: $!";
	if($pid) {
		open PID, ">$pidfile";
		print PID $pid;
		close PID;
		exit;
	}
	setsid or die "Can’t start a new session: $!";
	umask 0;
}

