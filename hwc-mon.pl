#!/usr/bin/perl
use Device::SerialPort;
my $PortName = "/dev/ttyAMA0";
my $Configuration_File_Name = ".hwc-config";
my $PortObj; 

print "inlet,roof,tank,pump,inlet_raw,roof_raw,tank_raw,pump_raw\n";

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

	#$PortObj->save($Configuration_File_Name)
		#|| warn "Can't save $Configuration_File_Name: $!\n";


# Loop forever
while(1) {
	my $InBytes = 1;
	my $string_in = ' ';
	my $hex;
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

		($byte) = unpack ('C',$string_in);
		$reg = ($byte & 0xf0) >> 4;
		$val = ($byte & 0x0f);
		$bytes[$reg] = $val;
		#print "reg[$reg] = $val\n";
	}

	$m = 1.011491061;
	$c = -50.49657516;
	$roof_raw = ($bytes[1] << 4) + $bytes[0];
	$tank_raw = ($bytes[3] << 4) + $bytes[2];
	$inlet_raw = ($bytes[5] << 4) + $bytes[4];
	$pump_raw = $bytes[6];
	$roof = ($roof_raw * $m) + $c;
	$inlet = ($inlet_raw * $m) + $c;
	$tank = ($tank_raw * $m) + $c;
	$pump = ($pump_raw & 0x02) >> 1;
	printf("%0.2f,%0.2f,%0.2f,%d,%02x,%02x,%02x,%08b\n",$inlet,$roof,$tank,$pump,$inlet_raw,$roof_raw,$tank_raw,$pump_raw);
	sleep(5);
}

close TTY;
