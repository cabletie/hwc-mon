#!/usr/bin/perl
use Device::SerialPort;
my $PortName = "/dev/ttyAMA0";
my $Configuration_File_Name = ".hwc-config";
my $PortObj; 

#if(-e $Configuration_File_Name) {
#	print "Using existing config\n";
#	$PortObj = start Device::SerialPort ($Configuration_File_Name)
#		|| die "Can't start $Configuration_File_Name: $!\n";
# } else {
	print "creating new config\n";
	$PortObj = new Device::SerialPort ($PortName, 0)
		|| die "Can't open $PortName: $!\n";

	$PortObj->baudrate(4800);
	$PortObj->parity("none");
	$PortObj->databits(8);
	$PortObj->stopbits(1);
	$PortObj->handshake("none");

	$PortObj->save($Configuration_File_Name)
		|| warn "Can't save $Configuration_File_Name: $!\n";
#}

$PortObj = tie (*TTY, 'Device::SerialPort', "$Configuration_File_Name")
              || die(RED,"Can't open $PortName: $^E\n",RESET);

# print "Handshake opts:\n";
# my @handshake_opts = $PortObj->handshake; 
# print join(' ',@handshake_opts);
# print "\n";

my $InBytes = 1;
my $string_in = ' ';
while(1) {
#	(my $count_in, $string_in) = $PortObj->read($InBytes);
#	die "read unsuccessful (got $count_in bytes, expected $InBytes)\n" unless ($count_in == $InBytes);

	$string_in = getc FH;
	last if ($string_in == 0xf0);
	printf("skipping: %x \n",$string_in);
}
	printf("moving on: %x ",$string_in);
$InBytes = 7;
while($string_in) {
	(my $count_in, $string_in) = $PortObj->read($InBytes);
	warn "read unsuccessful (got $count_in bytes, expected $InBytes)\n" unless ($count_in == $InBytes);

	printf("%x ",$string_in);
}

my $flowcontrol = $PortObj->handshake;

$PortObj->close || warn "close failed";
