#!/usr/bin/perl
my $test_mode = 0;
my $t;
my $inlet;
my $roof;
my $tank;
my $pump;
my $topout;
my $inlet_raw;
my $roof_raw;
my $tank_raw;
my $status_raw;
my $last_t = 0;
my $dataString;

while(<>) {
    chomp;
    undef $dataString;
    next if /^(\d{10}):-50.00:-50.00:-50.00:0:0:0x00:0x00:0x00:0x00$/;
    if (/^(\d{10}):.*:.*:.*:[0|1]:(0x..):(0x..):(0x..):(0x.*)$/) { # Old format
        $t = $1;
        $inlet_raw = $2;
        $roof_raw = $3;
        $tank_raw = $4;
        $status_raw =$5;
        $dataString = generateUpdateString($t,hex $inlet_raw,hex $roof_raw,hex $tank_raw,hex $status_raw);
    }
    if (/^(\d{10}):.*:.*:.*:[0|1]:[0|1]:(0x..):(0x..):(0x..):(0x..)$/) { # New format
        $t = $1;
        $dataString = $_;
    }
    if (defined $dataString && $t>$last_t) {
        print $dataString,"\n";
        $last_t = $t;
    }
}

sub generateUpdateString
{
    # $time,$inlet,$roof,$tank,$pump,$inlet_raw,$roof_raw,$tank_raw,$status_raw
    my $t = shift;
    my $inlet_raw = shift;
    my $roof_raw = shift;
    my $tank_raw = shift;
    my $status_raw = shift;
    printf("Received: %d:0x%02x:0x%02x:0x%02x:0x%02x\n", $t, $inlet_raw, $roof_raw, $tank_raw, $status_raw) if $test_mode;
    # These are figures from qualitative measurements between
    # read and actual measurements
    # I'm wondering if they should just be m=1, c=-50 ...
    # T = mX + c
    # X is register value read from serial port
    #
    #    my $m = 1.011491061;
    #    my $c = -50.49657516;
    my $m = 1.0;
    my $c = -50.0;
    my $roof = ($roof_raw * $m) + $c;
    my $inlet = ($inlet_raw * $m) + $c;
    my $tank = ($tank_raw * $m) + $c;
    my $pump = ($status_raw & 0x02) >> 1;
    my $topout = ($status_raw & 0x01);
    
    my $result = sprintf("%d:%0.2f:%0.2f:%0.2f:%d:%d:0x%02x:0x%02x:0x%02x:0x%02x",
    $t, $inlet, $roof, $tank, $pump, $topout, $inlet_raw, $roof_raw,
    $tank_raw, $status_raw);
    print "Result: $result\n" if $test_mode;
    return $result;
}
