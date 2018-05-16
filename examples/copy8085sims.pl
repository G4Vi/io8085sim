#!/usr/bin/perl
#apt-get install libinline-c-perl
use strict; use warnings;
use feature 'say';
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
say dirname(abs_path $0) . '/../perllib';
use lib dirname(abs_path $0) . '/../perllib';
use Sim8085::Interop qw(CreateGnuSim ReadPorts WritePorts);
use Data::Dumper;

say "GNUSim8085 IO address finder";

die("No GNUSim8085 pid provided!") if (@ARGV < 1);
#die("Too many arguments") if (@ARGV > 1);

my $pid = $ARGV[0];
my $gnusim = CreateGnuSim($pid);
$gnusim or die "Failed to create Sim Interface";

my $opid = $ARGV[1];
my $ognusim = CreateGnuSim($opid);
$ognusim or die "Failed to create Sim Interface";

exit;
my @portvals = ReadPorts($gnusim, 0, 5);
if($portvals[1] != 0)
{
    say "swapping rw sims";
    my $tempsim = $gnusim;
    $gnusim = $ognusim;
    $ognusim = $tempsim;
}   


my @REQ_WRITE = (1);
my @AKWRITE = ( 0 );
my @CONFM_WRITE = (1);

say "start vals";
my @temp1 = ReadPorts($gnusim, 0, 2);
my $lastportvals = \@temp1;
say "port: $_" foreach(@temp1);

my @temp2 = ReadPorts($ognusim, 0, 2);
my $lastoportvals = \@temp2;
say "oport: $_" foreach(@temp2);
say "----------------------------";
for(;;) {
my @oportvals = ReadPorts($ognusim, 0, 2);

my @portvals = ReadPorts($gnusim, 0, 2);

my $needsetport = 0;
#my $oportChanged = (@oportvals != @$lastoportvals);
my $oportChanged = ($oportvals[0] != $lastoportvals->[0]);
if($oportChanged)
{
    say "oport: $_" foreach(@oportvals);
    $lastoportvals = \@oportvals;
    WritePorts($gnusim, 0, $lastoportvals);
    $needsetport = 1;
    
}

#my $portChanged = (@portvals != @$lastportvals);
my $portChanged = ($portvals[0] != $lastportvals->[0]);
if($portChanged)
{
    say "port: $_" foreach(@portvals);
    $lastportvals = \@portvals;
    WritePorts($ognusim, 0, $lastportvals);
    $lastoportvals = \@portvals;
}

($lastportvals =  $lastoportvals) if($needsetport);

if($portChanged && $oportChanged)
{
    die("Hit race condition");
}
#sleep(1);
}





#my @vals = (1, 2, 3, 4, 5);
#WritePorts($gnusim, 4, \@vals);
#my @valsag = ReadPorts($gnusim, 0, 10);   
#say "port: $_" foreach(@valsag);

#sub CreateGnuSim {}
#sub ReadPorts{}
#sub WritePorts{}
