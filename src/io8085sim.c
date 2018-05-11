#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <sys/types.h>
#include <sys/uio.h>
#include "io8085sim.h"

typedef unsigned int uint;

bool io8085sim_read_ports(IO8085Sim *unknown_sim, unsigned int start_port, unsigned int num, void *dest)
{
    if(unknown_sim->type != IO8085Sim_GNUSim8085) 
    {
        printf("Critical, unknown simulator\n");
        return false;
    }

    GNUSim8085 *sim = (GNUSim8085 *)unknown_sim;
    struct iovec local, remote;    
    local.iov_base = dest;
    local.iov_len = num;
    remote.iov_base = sim->ports + start_port;
    remote.iov_len = num;

    size_t nread = process_vm_readv(sim->pid, &local, 1, &remote, 1, 0);
    if(nread != num)
    {
        printf("Critical, error reading ports. nread: %u\n", nread);
        return false;
    }
    return true;
}

bool io8085sim_write_ports(IO8085Sim *unknown_sim, unsigned int start_port, unsigned int num, void *src)
{
    if(unknown_sim->type != IO8085Sim_GNUSim8085) 
    {
        printf("Critical, unknown simulator\n");
        return false;
    }

    GNUSim8085 *sim = (GNUSim8085 *)unknown_sim;
    struct iovec local, remote;    
    local.iov_base = src;
    local.iov_len = num;
    remote.iov_base = sim->ports + start_port;
    remote.iov_len = num;

    size_t nwrite = process_vm_writev(sim->pid, &local, 1, &remote, 1, 0);
    if(nwrite != num)
    {
        printf("Critical, error writing ports. nwrite: %u\n", nwrite);
        return false;
    }
    return true;
}



