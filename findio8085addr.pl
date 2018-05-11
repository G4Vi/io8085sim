#!/usr/bin/perl
#apt-get install libinline-c-perl
use Inline C;
use strict; use warnings;
use feature 'say';
use FileHandle;
use IPC::Open2;
use integer;
use Data::Dumper;

no warnings 'portable'; 

say "GNUSim8085 IO address finder";

my @StaticChkOffsetPairs = (
    {
        chk    => "cbdcb2ac647c95b15663014a1bee958d5d8b6c05e9e8e547031d188de4a94d15",
        offset => 0x2ae644
    },
);

die("No GNUSim8085 pid provided!") if (@ARGV < 1);
die("Too many arguments") if (@ARGV > 1);

my $pid = $ARGV[0];
my $gnusim = CreateGnuSim($pid);
$gnusim or die "Failed to create Sim Interface";

my @portvals = read_ports($gnusim, 0, 10);   
say "port: $_" foreach(@portvals);
my @vals = (1, 2, 3, 4, 5);
write_ports($gnusim, 4, \@vals);
my @valsag = read_ports($gnusim, 0, 10);   
say "port: $_" foreach(@valsag);

sub GetTerminal {
    my $read = '';
    do
    {
        my $temp;
        sysread Reader, $temp, 1;
        $read .= $temp;
    }
    until($read =~ /> /);  
    return $read;
}

sub GetBaseAddress {
      my ($pid) = @_;
      my @mapsplit = split('-', `head -n1 /proc/$pid/maps`);
      return hex($mapsplit[0]);
}

sub FindPortAddr {
    my ($gpid) = @_;
    say "Attaching to " . $gpid;
    my $startscanmem = "scanmem -p " . $gpid . ' 2>&1';     
    my $pid = open2(*Reader, *Writer, $startscanmem );
    GetTerminal();
    
    # only search for 1byte integers
    print Writer "option scan_data_type int8\n";
    GetTerminal();
    
    # only search the modifiable static storage
    print Writer "dregion !1\n";
    GetTerminal();
    
    # prompt until we have only one match
    do {
        my $val = int(rand(255));
        say "Set Port 0 to $val. Press enter when done." ;   
        <STDIN>; 
        print Writer "$val\n";       
    } until(GetTerminal() =~ /\s1\smatches\./);
    
    # output the match
    print Writer "list\n";
    my $matchline = GetTerminal();
    #say $matchline;
    if ($matchline =~ /\]\s(.+?),\s+.\s.\s+(.+?),/) {
        say "port addr: $1 (offset from base: $2)";
        return hex($1);
    }
    return undef;
}

sub CreateGnuSim {
    my ($pid) = @_;

    #calculate the checksum of the process
    my @linesplit = split(' ', `sha256sum /proc/$pid/exe`);
    my $checksum = $linesplit[0];

    #check against stored checksums for port addr
    my $address;
    foreach my $pair (@StaticChkOffsetPairs) {
        if($pair->{'chk'} eq $checksum) {            
            $address  = GetBaseAddress($pid) + $pair->{'offset'};            
            last;
        }
    }

    #or find it by scanning memory
    unless (defined $address) {
        say "sha256sum: $checksum";
        say "None of the checksums match, launching scanmem frontend";
        $address = FindPortAddr($pid);    
    }

    return undef if (!defined $address);
    
    say sprintf("pid: %u, address 0x%x", $pid, $address);
    return create_gnusim($pid, $address);   
}

  __END__
  __C__
  
  #include <sys/types.h>  
  #include "io8085sim.h"
  #include "io8085sim.c"
  typedef unsigned int uint;
  typedef unsigned long ulong;

  static inline void dumpSVInfo(SV *sv)
  {
      printf("SV addr: %p PVX addr: %p\n", sv, SvPVX(sv));
  }

  /* Create a sim struct and return a ref counted pointer SV *(PV) */ 
  SV *create_gnusim(unsigned long tpid, void *addr)
  {     
      SV *svsim =     newSV(sizeof(GNUSim8085) - 1);           
      GNUSim8085 *sim  = (GNUSim8085 *)SvPVX(svsim);   
      SvCUR_set(svsim, sizeof(GNUSim8085));
      SvPOK_on(svsim);

      sim->type = IO8085Sim_GNUSim8085;
      sim->pid = (pid_t)tpid;
      sim->ports = addr;      
      
      return svsim; 
      /*
      sv_2mortal is called under the hood, so our struct should be freed when there are not remaining references 
      http://search.cpan.org/~tinita/Inline-C-0.78/lib/Inline/C/Cookbook.pod#Using_Memory
      */   
  }
  

  /* Wrapper for io8085sim_read_ports */
  void read_ports(SV *svsim, unsigned int start_port, unsigned int num_ports)
  {      
      void *sim = SvPVX(svsim);      
      uint8_t dest[256];     
      io8085sim_read_ports((IO8085Sim *)sim, start_port, num_ports, dest);
      
      Inline_Stack_Vars;
      Inline_Stack_Reset;
      for(uint i = 0; i < num_ports; i++)
      {
           Inline_Stack_Push(sv_2mortal(newSViv(dest[i])));
      }
      Inline_Stack_Done;
  }

  /* Wrapper for io8085sim_write_ports */
  void write_ports(SV *svsim, unsigned int start_port, AV *array)
  {      
      uint8_t src[256];      
      uint i;
      SV **value;
      for(i = 0; i <= av_len(array); i++)
      {
          value = av_fetch(array, i, 0);  
          if(!SvIOK(*value)) croak("Array contains non-integer value");       
          src[i] = SvUV(*value);
      }     
      
      void *sim = SvPVX(svsim);          
      io8085sim_write_ports((IO8085Sim *)sim, start_port, i, src);     
      
  }

