#!/usr/bin/perl
#apt-get install libinline-c-perl
use strict; use warnings;
use feature 'say';
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
say dirname(abs_path $0) . '/../perllib';
use lib dirname(abs_path $0) . '/../perllib';
use Sim8085::Interop qw(CreateGnuSim ReadPorts WritePorts SharePorts);


say "GNUSim8085 IO address finder";

die("No GNUSim8085 pid provided!") if (@ARGV < 1);
die("Too many arguments") if (@ARGV > 2);

my $pid = $ARGV[0];
my $pid2 = 0;
$pid2 = $ARGV[1] if (@ARGV > 1) ;

my $ognusim;
my $gnusim = CreateGnuSim($pid);
$gnusim or die "Failed to create Sim Interface";

if ($pid2 != 0) {
   $ognusim = CreateGnuSim($pid2);
   $ognusim or die "Failed to create Sim Interface";
}


SharePorts($pid, $pid2);

#my @portvals = ReadPorts($gnusim, 0, 10);   
#say "port: $_" foreach(@portvals);
#my @vals = (1, 2, 3, 4, 5);
#WritePorts($gnusim, 4, \@vals);
#my @valsag = ReadPorts($gnusim, 0, 10);   
#say "port: $_" foreach(@valsag);

#sub CreateGnuSim {}
#sub ReadPorts{}
#sub WritePorts{}
