#!/usr/bin/perl
package Sim8085::Interop;
use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use Inline C => 'DATA' =>
    INC => '-I' . dirname(abs_path $0) . '/../src' =>
    LIBS => '-L' . dirname(abs_path $0) . '/../lib' . ' -lio8085sim -lrt';
use strict; use warnings;
use feature 'say';
use FileHandle;
use IPC::Open2;
use integer;
use Exporter qw(import);
use Data::Dumper;

no warnings 'portable'; 
 
our @EXPORT_OK = qw(CreateGnuSim ReadPorts WritePorts SharePorts HashToStructSVPV updateStruct update);

my @StaticChkOffsetPairs = (
    {
        chk    => "cbdcb2ac647c95b15663014a1bee958d5d8b6c05e9e8e547031d188de4a94d15",
        offset => 0x2ae644
    },
);

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

sub GetMapAddress {
    my ($pid) = @_;
    my @mapsplit = split(/-| /, `cat /proc/$pid/maps | grep heap`);
    return hex($mapsplit[1]);
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
    my $tmp;
    do {
        my $val = int(rand(255));
        say "Set Port 0 to $val. Press enter when done." ;   
        <STDIN>; 
        print Writer "$val\n";  
    #    $tmp = GetTerminal();
    #    say $tmp;      
    #} until($tmp =~ /\s2\smatches\./);
    } until(GetTerminal() =~ /\s1\smatches\./);
    
    # output the match
    print Writer "list\n";
    my $matchline = GetTerminal();
    print Writer "exit\n";
    say $matchline;
    if ($matchline =~ /\]\s(.+?),\s+.\s.\s+(.+?),/) {
        say "port addr: $1 (offset from base: $2)";
        return hex($1);
    }
    return undef;
}

sub new {
    my ($classname, $pid) = @_;
    
    #calculate the checksum of the process
    my @linesplit = split(' ', `sha256sum /proc/$pid/exe`);
    my $checksum = $linesplit[0];

    my $baseaddress = GetBaseAddress($pid);
    #check against stored checksums for port addr
    my $address;
    foreach my $pair (@StaticChkOffsetPairs) {
        if($pair->{'chk'} eq $checksum) {            
            $address  = $baseaddress + $pair->{'offset'};            
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

    my %sim = (
       type => 'GNUSim8085',
       pid  => $pid,
       address => $address,
       baseaddress => $baseaddress,
       struct => create_gnusim($pid, $address)       
    );     
    
    return bless(\%sim, $classname);
}

# updates the field and regenerates the struct
sub update {
    my ($classref, $key, $newvalue) = @_;
    $classref->{$key} = $newvalue;
    updateStruct($classref);
}

# regenerates the struct
sub updateStruct {   
   my ($classref) = @_;
   SAFEFREE($classref->{'struct'});
   $classref->{'struct'} = create_gnusim($classref->{'pid'}, $classref->{'address'});   
}





sub GetGDB {
    my $read = '';
    do
    {
        my $temp;
        sysread Reader, $temp, 1;
        $read .= $temp;
    }
    until($read =~ /\(gdb\) /);  
    return $read;
}

sub GDBCommand {
    my ($command) = @_;
    print Writer $command . "\n";
    return GetGDB();
}

sub SharePorts {
    my ($gnusim, $ognusim) = @_;  

    # make the shared memory
    my $memkey = create_shm();
    my $memfile = "/dev/shm$memkey";
    say $memfile;

    #setup the processes to use the shared memory, instead of their own static storage
    if(defined $ognusim) {
        my $fpid = fork();
        if($fpid == 0) {
            $gnusim = $ognusim;            
        }
    }
    my $pid = $gnusim->{'pid'};    
    my $baseaddress = $gnusim->{'baseaddress'};
    my $portstart = $gnusim->{'address'};
    my @breakpoints;

    # set breakpoints, TODO find the bytecode instead of hardcoding
    push @breakpoints, $baseaddress + 0x1ba51;
    push @breakpoints, $baseaddress + 0x138cb;
    push @breakpoints, $baseaddress + 0x1a7ac;
    push @breakpoints, $baseaddress + 0x1beb4;
    push @breakpoints, $baseaddress + 0x138eb; 
    push @breakpoints, $baseaddress + 0x0a20e;
    push @breakpoints, $baseaddress + 0x1c036;  
    push @breakpoints, $baseaddress + 0x0a027;

    my $startgdb = "gdb -p $pid 2>&1";
    my $gdb = open2(*Reader, *Writer, $startgdb );
    print GetGDB();
    
    #dump preprocessor defines so we can use them
    foreach my $line (`gcc -dM -E -include sys/mman.h -include fcntl.h -include stdio.h - < /dev/null | sed 's/#/macro /g'`) {        
        print Writer $line;
        GetGDB();        
    }

    # open the shared memory
    GDBCommand('set $memfd = open("' . $memfile . '", O_RDWR)');
    print GDBCommand('p/d $memfd');   
    my $mapaddr = GetMapAddress($pid);
    my $mapcmd = sprintf('set $pageaddr =  mmap(' . "0x%x" . ', 4096, PROT_READ | PROT_WRITE, MAP_SHARED, $memfd, 0x0)', $mapaddr);    
    say $mapcmd; 
    print GDBCommand($mapcmd);
    print GDBCommand('p/x $pageaddr');
    
    my $debug = 0;
    if(! $debug)
    {
        # set breakpoints where we need to either patch gnusim code or set a register
        foreach my $breakpoint (@breakpoints) {
            say GDBCommand('b *' . $breakpoint);            
        }

        # monitor by gdb
        while(1) {            
            my $hit = GDBCommand("c");
            print $hit;
            my $reg = GetRegisters();
            ( $hit =~ /hit\s+Breakpoint\s+(\d)/) or die("Unexpected stop");
            my $bnum = $1;
            PatchIfFound($mapaddr, $portstart);
            if((($bnum != 3) && ($bnum != 6)) && ($bnum != 8)) {
                say GDBCommand('del ' . $bnum); 
            }
            else {
                say "Not deleting, $bnum hit";
            }            
        }
        
    }
    else {
    # Trap accesses to the ports page, so we can redirect
    my $page = get_page_address($portstart);
    print sprintf("portstart: 0x%x page: 0x%x\n", $portstart, $page);   
    ProtectPage($page, 'PROT_NONE');    
    say GDBCommand("handle SIGSEGV nopass");  
    
    # monitor by gdb
    while(1) {        
        print GDBCommand("c"); 

        # get the failing address
        my $faultline = GDBCommand('p $_siginfo._sifields._sigfault.si_addr');        
        say $faultline;
        my @parts = split(' ', $faultline);
        my $faultaddr = hex($parts[@parts - 2]);

        # if it's not a port, allow the instruction to be executed
        if(!IsPort($faultaddr, $portstart)) {
             ProtectPage($page, 'PROT_READ | PROT_WRITE');
             say "stepi";
             say GDBCommand("stepi");             
             ProtectPage($page, 'PROT_NONE');             
        }
        # otherwise patch it
        else {            
            PatchIfFound($mapaddr, $portstart);            
        }
    }
    }
}

sub IsPort {
    my ($address, $portstart) = @_;
    return !(($address < $portstart) || ($address > ($portstart + 0xFF))) 
}

sub GetRegisters {
    my %reg;
    my $gdbout = GDBCommand('i r');
    print $gdbout;
    my @gdblines = split (/\n/, $gdbout);
    foreach my $regline (@gdblines) {
        if($regline =~ /^([a-z0-9]+)\s+([a-z0-9]+)\s+/i) {            
            $reg{$1} = hex($2);
        }        
    }
    return \%reg;
}

sub ProtectPage {
    my ($page, $protection) = @_;
    my $mprotect = sprintf('call mprotect(' . "0x%x, 4096, $protection)", $page);
    say $mprotect;
    print GDBCommand($mprotect);    
}

sub PatchIfFound {
    my ($newpage, $portstart) = @_;
   
    my $reg = GetRegisters();

    # check the instruction ptr's bytecode for a match
    # on match, patch the immediate, or set the register value
    my $result = GDBCommand(sprintf("x/9b 0x%x", $reg->{'rip'}));    
    if($result =~ /0x88\s+0x8c\s+0x02\s+0x24\s+0x00\s+0x01\s+0x00/) { #88 8c 02 24 00 01 00 	#mov    BYTE PTR [rdx+rax*1+0x10024],cl
        my $address = $reg->{'rip'} + 0x3;
        my $distance = $newpage - $reg->{'rdx'};               
        replace_distance($distance, $address);        
    }
    elsif($result =~ /0x0f\s+0xb6\s+0x84\s+0x38\s+0x24\s+0x00\s+0x01\s+0x00/) {  #0f b6 84 38 24 00 01 00 #movzx  eax,BYTE PTR [rax+rdi*1+0x10024]       
       my $address = $reg->{'rip'} + 0x4;
       my $distance = $newpage - $reg->{'rax'};
       replace_distance($distance, $address);
       
    }
    elsif($result =~ /0x0f\s+0xb6\s+0x3c\s+0x02/) { #0f b6 3c 02          	$movzx  edi,BYTE PTR [rdx+rax*1]
       if(IsPort($reg->{'rdx'}, $portstart) && ($reg->{'rdx'} != $portstart)) {
           die(sprintf "0f b6 3c 02 needs better patch portstart: 0x%x reg: 0x%x", $portstart, $reg->{'rdx'});
       }
       
       say GDBCommand('set $rdx = ' . $newpage);        
    }
    elsif($result =~ /0x45\s+0x0f\s+0xb6\s+0xac\s+0x04\s+0x24\s+0x00\s+0x01/) {#45 0f b6 ac 04 24 00 01 00 	movzx  r13d,BYTE PTR [r12+rax*1+0x10024]        
        my $address = $reg->{'rip'} + 0x5;
        my $distance = $newpage - $reg->{'r12'};
        replace_distance($distance, $address);
    }
    elsif($result =~ /0x40\s+0x88\s+0xb4\s+0x38\s+0x24\s+0x00\s+0x01\s+0x00/) { #40 88 b4 38 24 00 01 00 	mov    BYTE PTR [rax+rdi*1+0x10024],sil        
        my $address = $reg->{'rip'} + 0x4;
        my $distance = $newpage - $reg->{'rax'};
        replace_distance($distance, $address);
    }
    elsif($result =~ /0x41\s+0x88\s+0x14\s+0x04/) { #41 88 14 04          	mov    BYTE PTR [r12+rax*1],dl
       if(IsPort($reg->{'r12'}, $portstart) && ($reg->{'r12'} != $portstart)) {
           die(sprintf "41 88 14 04 needs better patch portstart: 0x%x reg: 0x%x", $portstart, $reg->{'r12'});
       }
       
       say GDBCommand('set $r12 = ' . $newpage);        
    }
    elsif($result =~ /0x0f\s+0xb6\s+0x8c\s+0x28\s+0x24\s+0x00\s+0x01\s+0x00/) { #0f b6 8c 28 24 00 01 	movzx  ecx,BYTE PTR [rax+rbp*1+0x10024]
        say "HIT";
        say GDBCommand('x/i $pc');
        my $address = $reg->{'rip'} + 0x4;
        my $distance = $newpage - $reg->{'rax'};
        replace_distance($distance, $address);
    }
    #8
    elsif($result =~ /0x0f\s+0xb6\s+0x04\s+0x03/) { #0f b6 04 03          	movzx  eax,BYTE PTR [rbx+rax*1]
       if(IsPort($reg->{'rbx'}, $portstart) && ($reg->{'rbx'} != $portstart)) {
           die(sprintf "0f b6 04 03 needs better patch portstart: 0x%x reg: 0x%x", $portstart, $reg->{'rbx'});
       }
       
       say GDBCommand('set $rbx = ' . $newpage);        
    }
    else {
        say GDBCommand('x/i $pc');
        say $result;
        exit;
    }
    say GDBCommand('x/i $pc');
}

sub replace_distance {    
    my ($distance, $address) = @_;
    my @replacement =  (($distance & 0xFF), (($distance >> 8) & 0xFF), (($distance >> 16) & 0xFF), (($distance >> 24) & 0xFF));
    foreach my $byte (@replacement) {
        say "set *(char*)$address $byte";
        print GDBCommand("set *(char*)$address = $byte");            
        $address++;            
    }
}
    

1;

  __DATA__
  __C__
  
  #include <sys/types.h>  
  #include <sys/mman.h>
  #include <sys/stat.h>        /* For mode constants */
  #include <fcntl.h> 
  #include "io8085sim.h"
  /*#include "io8085sim.c"*/
  typedef unsigned int uint;
  typedef unsigned long ulong;

  void SAFEFREE(void *addr)
  {
      printf("SAFEFREE %p\n", addr);   
      Safefree(addr);
  }  

  void *get_page_address(unsigned long addr)
  {
      ulong PAGESIZE = sysconf(_SC_PAGESIZE);
      return (void*)(addr & ~(PAGESIZE-1));
  }

  const char *create_shm()
  {
      const char *shmname = "/8085portmem";

      unlink("/dev/shm/8085portmem");
      mode_t old_umask = umask(0);
      int fd = shm_open(shmname, O_RDWR | O_CREAT, 0777); //, S_IRUSR | S_IWUSR);
      if (fd == -1) {
          perror("open");
          exit(1);
      }

      umask(old_umask);

      size_t len = 4096;
      if (ftruncate(fd, len) == -1) {
          perror("ftruncate");
          exit(1);
      }


      return shmname;

  }

  static inline void dumpSVInfo(SV *sv)
  {
      printf("SV addr: %p PVX addr: %p\n", sv, SvPVX(sv));
  }

  /* Create a sim struct and return it as an IV */
  SV *create_gnusim(long tpid, void *addr)
  {
      GNUSim8085 *sim;
      Newx(sim, 1, GNUSim8085);   
      printf("sim address start %p\n", sim);   

      sim->type = IO8085Sim_GNUSim8085;
      sim->pid = (pid_t)tpid;
      sim->ports = addr;      
      
      /* Copy the pointer into an RV, make the ptr itself readonly*/
      /*SV *obj_ref = sv_setref_pv(newSV(0), NULL, sim);
      SvREADONLY_on(SvRV(obj_ref));
      return obj_ref;*/

      /* put the ptr in an IV*/
      SV *obj = newSViv((IV)sim);
      SvREADONLY_on(obj);
      return obj;
  }

  void DESTROY(SV* obj)
  {
      SV **structrv;      
      if((structrv = hv_fetchs((HV*)SvRV(obj), "struct", 0)) != NULL)
      {   
          /* RV handling */       
          /* IO8085Sim *sim = (IO8085Sim *)SvIV(SvRV(*structrv)); */

          IO8085Sim *sim = (IO8085Sim *)SvIV(*structrv);
          printf("sim address end %p\n", sim);
          Safefree(sim);
      }
      else
      {
          printf("didn't free\n");
      }      
  }



  SV *HashToStructSVPV(HV *hv)
  {
      SV **type, **pid, **address;
      if(((type = hv_fetchs(hv, "type", 0))!= NULL) &&
      (strEQ(SvPV_nolen(*type), "GNUSim8085")) &&
      ((pid = hv_fetchs(hv, "pid", 0)) != NULL) &&
      ((address = hv_fetchs(hv, "address", 0)) != NULL))     
      {          
          printf("type: %s pid: %ld, address %p\n", SvPV_nolen(*type), SvIV(*pid), SvUV(*address));
          return create_gnusim(SvIV(*pid), (void*)SvUV(*address));          
      }

      return newSV(0); 
  }
  
  /* Wrapper for io8085sim_read_ports */
  void ReadPorts(const char *classname, SV *svsim, unsigned int start_port, unsigned int num_ports)
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
  void WritePorts(const char *classname, SV *svsim, unsigned int start_port, AV *array)
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







