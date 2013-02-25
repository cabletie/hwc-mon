#!/usr/bin/perl
use Device::SerialPort;
my $PortName = "/dev/ttyAMA0";
my $Configuration_File_Name = ".hwc-config";
my $PortObj; 

open TTY,"cat < $PortName|";

my $char_in = ' ';
while(1) {
	$char_in = getc TTY;
	$string_in = unpack('H2',$char_in);
	print $string_in;
	last if ($string_in == "f0");
	print("skipping: $string_in\n");
}
print("moving on: $string_in\n");

$char_in = <TTY>;
$string_in = unpack('H2'x7,$char_in);
print $string_in;

close TTY;
