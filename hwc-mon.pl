#!/usr/bin/perl

END {
    print "not ok 1 " unless $loaded;
    unlink "demo.rrd";
}

sub ok
{
    my($what, $result) = @_ ;
    $ok_count++;
    print "not " unless $result;
    print "ok $ok_count $what ";
}

#makes programm work AFTER install
use lib qw( /usr/local/lib/perl );

use strict;
use vars qw(@ISA $loaded);

use RRDs;
$loaded = 1;
my $ok_count = 1;

ok("loading",1);

######### End of RRDp black magic
use strict;
use POSIX qw(setsid);
use Proc::Daemon;

use Device::SerialPort;
use Time::Format qw(%time %strftime %manip);
use Getopt::Long;
use RRDs;

###############################
# Config stuff
###############################
# time in seconds between samples. Must match RRD setup.
my $step = 5;
my $pid_file = "/var/run/hwcd.pid";
my $log_dir = "/var/log/hwc";
my $log_file = "$log_dir/hwc.error";
my $rrd_file = "/home/peter/hwc/hwc.rrd";
#my $raw_file = "$log_dir/hwc_raw.log";
my $raw_file = "/home/peter/hwc/hwc-raw.dat";

# Flow control flags
my $keep_going = 1;
my $reload = 0;

# Dummy call of Time::Format to load perlonly code
# Because Time::Format_XS has version campatibility problems
# And will throw an error if attempt is made to load after forking.
my $dummy = $time{'Mon dd hh:mm:ss'};

# Become a daemon
my $daemon_pid = Proc::Daemon::Init( { 
	pid_file => $pid_file,
	child_STDERR => "+>>$log_file"}
);
# Cue parent to quit
exit if $daemon_pid;

# Make STDERR filehandle hot so output is not buffered.
my $ofh = select STDERR;
$| = 1;
select $ofh;

print STDERR $time{'Mon dd hh:mm:ss'}." Loaded hwc\n";

#
# Setup signal handlers so that we have time to cleanup before shutting down
# and so we can reload if init.d scalls for it
#
$SIG{HUP}  = sub { print(STDERR $time{'Mon dd hh:mm:ss'}." Caught SIGHUP:  reloading\n"); $keep_going = 0; $reload = 1};
$SIG{INT}  = sub { print(STDERR $time{'Mon dd hh:mm:ss'}." Caught SIGINT:  exiting gracefully\n"); $keep_going = 0; };
$SIG{QUIT} = sub { print(STDERR $time{'Mon dd hh:mm:ss'}." Caught SIGQUIT:  exiting gracefully\n"); $keep_going = 0; };
$SIG{TERM} = sub { print(STDERR $time{'Mon dd hh:mm:ss'}." Caught SIGTERM:  exiting gracefully\n"); $keep_going = 0; };

# Prepare raw input file ...
(my $raw_open = open RAW,"<$raw_file") || warn "couldn't open raw data file ($raw_file) to process: $!\n";

# Setup and load rrd file if it doesn't already exist
unless( -e $rrd_file) {
    my $start_seconds = 0;
    if($raw_open) {
        # Grab first entry from raw log file
        my $line = <RAW>;
        if($line) {
            (my @F) = split(/:/,$line);
            $start_seconds = eval($F[0]-10);
        }
        # Reset RAW to start of file ready to process later
        seek(RAW, 0, 0);
    }
    print STDERR "Creating RRD file ($rrd_file) with start: $start_seconds and step: $step ...";
    # Create RRD file
    RRDs::create("$rrd_file",
        "--start=$start_seconds",
        "--step=$step",
        "DS:inlet:GAUGE:10:-50:210",
        "DS:roof:GAUGE:10:-50:210",
        "DS:tank:GAUGE:10:-50:210",
        "DS:pump:GAUGE:10:0:1",
        "DS:inlet_raw:GAUGE:10:0x00:0xff",
        "DS:roof_raw:GAUGE:10:0x00:0xff",
        "DS:tank_raw:GAUGE:10:0x00:0xff",
        "DS:flags:GAUGE:10:0x00:0xff",
        "RRA:AVERAGE:0.5:1:12614400",
        "RRA:AVERAGE:0.5:6:120",
        "RRA:AVERAGE:0.5:60:210240");
    my $ERR = RRDs::error;
    die "\nFailed to create rrd file: $ERR" if($ERR);
    print STDERR "done\n";
    #RRDs::update("$rrd_file", "N:u:u:u:u:u:u:u:u");
    #    my $ERR = RRDs::error;
    #    die "Failed to create rrd file: $ERR" if($ERR);
}

# Grab last entry from rrd file
my $last = RRDs::last ($rrd_file);
my $ERR = RRDs::error;
die "Failed to get last time from rrd file: $ERR" if($ERR);

if($raw_open) {
    # Now load in new stuff from log file if there is more recent stuff than the
    # latest entry in the RRD file
    # Also (somewhat hamfisted-ly) get last line of file
    my $last_line = `tail -1 $raw_file`;
#    print STDERR $last_line;
    (my $last_raw) = split(/:/,$last_line);
    warn "last time from raw file: $last_raw\n";
    warn "last time from rrd file: $last\n";
    if($last_raw > $last) { # raw file ends after current rrd file
        my $this = 0;
        my $prev;
        my $said_processing;
        my $said_skipping;
        my $line_count = 0;

        while(<RAW>) {
		chomp;
            (my @F) = split(/:/);
            $prev=$this;
            $this=$F[0];
            if($this <= $last) {
                if(! $said_skipping) {
                    print STDERR "skipping ...";
                    $said_skipping = 1;
                }
                next;
            }
            if($said_skipping and !$said_processing) {
                print STDERR "processing\n";
                $said_processing = 1;
            }
            if($this > $prev)
            {
                RRDs::update ("$rrd_file","$_");
                $ERR = RRDs::error;
                warn "Failed to update to rrd file: $ERR" if($ERR);
                print STDERR ("\r$line_count++") unless($line_count % 720);
                last unless($keep_going); # Escape clause to cancel processing mid-load
                next;
            }
            print STDERR "out of sequence at line $.: prev: $prev, this: $this\n";
            $this = $prev;
        }
    }
}

# Main loop to be repeated when reload is requested via SIGHUP
do { #reload - SIGHUP send us back here

	$keep_going = 1;
	$reload = 0;

	# Do important daemonic stuff

	# Setup serial port comms
	my $PortName = "/dev/ttyAMA0";
	my $Configuration_File_Name = ".hwc-config";
	my $PortObj; 

	$PortObj = new Device::SerialPort ($PortName, 0)
		|| die "Can't open $PortName: $!\n";

	$PortObj->baudrate(4800);
	$PortObj->parity("none");
	$PortObj->databits(8);
	$PortObj->stopbits(1);
	$PortObj->handshake("none");
	$PortObj->read_const_time(1000);

	$PortObj->write_settings;

	open(RRD,">>$raw_file") ||
		die "Failed to open log file for appending: $!\n";;

	# Make RRD filehandle hot so output is not buffered.
	$ofh = select RRD;
	$| = 1;
	select $ofh;

    warn "Starting processing at ",time," (",$time{'Mon dd hh:mm:ss'},")\n";
	# Loop forever
	while($keep_going) {
		my $InBytes = 1;
		my $string_in = ' ';
		my $hex;
		my @bytes;
		$PortObj->purge_all;

		# Loop until we find a 0xf0 frame flag
		# TODO: Need to add a timeout here
		while(1) {
			(my $count_in, $string_in) = $PortObj->read($InBytes);
			if($count_in < $InBytes) {
				warn "Read from SolarStat serial port unsuccessful (got $count_in bytes, expected $InBytes)\n";
                #				sleep 15;
				next;
			}
			$hex = unpack ('C',$string_in);
			last if $hex == 0xf0;
		}

		# Read 1 byte at a time, inserting each value into it's register
		# data is formatted in 8 byte frames thusly: f0 rv rv rv rv rv rv rv
		# f0 is frame marker, r is register number nibble, v is value nibble
		# 
		$InBytes = 1;
		for (0..6) {
			(my $count_in, $string_in) = $PortObj->read($InBytes);
			warn "read unsuccessful (got $count_in bytes, expected $InBytes)\n" unless ($count_in == $InBytes);

			(my $byte) = unpack ('C',$string_in);
			my $reg = ($byte & 0xf0) >> 4;
			my $val = ($byte & 0x0f);
			$bytes[$reg] = $val;
		}

		# These are figures from qualitative measurements between
		# read and actual measurements
		# I'm wondering if they should just be m=1, c=-50 ...
		# T = mX + c
		# X is register value read from serial port
		#
		my $m = 1.011491061;
		my $c = -50.49657516;
		# Roof high nibble is R1, low nibble is R0
		my $roof_raw = ($bytes[1] << 4) + $bytes[0];
		# Tank high nibble is R3, low nibble is R2
		my $tank_raw = ($bytes[3] << 4) + $bytes[2];
		# Inlet high nibble is R5, low nibble is R4
		my $inlet_raw = ($bytes[5] << 4) + $bytes[4];
		# Pump R6.1 (topout R6.0 and frost R6.?) flags in R6
		my $pump_raw = $bytes[6];
		my $roof = ($roof_raw * $m) + $c;
		my $inlet = ($inlet_raw * $m) + $c;
		my $tank = ($tank_raw * $m) + $c;
		my $pump = ($pump_raw & 0x02) >> 1;

		# Insert timestamp
        my $t = time;
		# Write data string
		printf RRD ("%d:%0.2f:%0.2f:%0.2f:%d:0x%02x:0x%02x:0x%02x:0x%02x\n",
			$t,
			$inlet,
			$roof,
			$tank,
			$pump,
			$inlet_raw,
			$roof_raw,
			$tank_raw,
			$pump_raw);
	my $rrd_data = sprintf("%d:%0.2f:%0.2f:%0.2f:%d:0x%02x:0x%02x:0x%02x:0x%02x",
                $t, $inlet, $roof, $tank, $pump, $inlet_raw, $roof_raw,
                $tank_raw, $pump_raw);
#print STDERR "rrd_data: $rrd_data\n";
        RRDs::update($rrd_file,$rrd_data);
	$ERR = RRDs::error;
	warn "Failed to update to rrd file: $ERR" if($ERR);
	sleep($step); # Wait around till it's time to do next sample
	} #while keepgoing
	close RRD;
} while ($reload);
warn "Exiting\n";
__END__

=head1 NAME
hwcd - SolarStat solar water heater controller monitor daemon

=head1 SYNOPSIS
sample [options] [file ...]
 Options:
   -help            brief help message
   -man             full documentation
   
=head1 OPTIONS
=over 8
=item B<-help>
Print a brief help message and exits.
=item B<-man>
Prints the manual page and exits.
=back
=head1 DESCRIPTION
B<This program> will read the given input file(s) and do something
useful with the contents thereof.
=cut
