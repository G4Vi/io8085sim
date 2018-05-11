#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include "io8085sim.h"

typedef unsigned int uint;
typedef uint8_t uint8;

#define LENGTH_1D(X) (sizeof(X)/sizeof(X[0]))

typedef struct {
    const char *sha256sum;
    ptrdiff_t  offset;
} HashOffset;

static HashOffset HashPairs[] = {
    {"cbdcb2ac647c95b15663014a1bee958d5d8b6c05e9e8e547031d188de4a94d15", 0x2ae644}
};

//pass in 0 to get a pid using pgrep
GNUSim8085 *create_GNUSim8085(GNUSim8085 *output_sim, pid_t pid);

uintptr_t GetBaseAddress(pid_t pid);
const char *GetSha256Sum(pid_t pid, char *dest, uint len);
bool find_gnu8085sim_pid(pid_t *pid);


int main(int argc, char **argv)
{    
    GNUSim8085 sim;
    if(create_GNUSim8085(&sim, 0) == NULL)
        return 1;   

    
    uint8 port0;
    if(io8085sim_read_ports((IO8085Sim *)&sim, 0, 1, &port0))
    {
        printf("port 0: %u\n", port0);
    }
 
    
    port0 = 10;
    io8085sim_write_ports((IO8085Sim *)&sim, 0, 1, &port0);
   
    if(io8085sim_read_ports((IO8085Sim *)&sim, 0, 1, &port0))
    {
        printf("port 0: %u\n", port0);
    }    
    
    return 0;
}


bool find_gnu8085sim_pid(pid_t *pid)
{
    FILE *pidCommand = popen("pgrep gnusim8085", "r");
    char pidstr[16];
    fgets(pidstr, sizeof(pidstr), pidCommand);    
    pclose(pidCommand);

    *pid = strtol(pidstr, NULL, 10);
    return true;
}
GNUSim8085 *create_GNUSim8085(GNUSim8085 *output_sim, pid_t pid)
{
   output_sim->type = IO8085Sim_GNUSim8085;

   if((pid == 0) && (!find_gnu8085sim_pid(&pid)))
   {
       return NULL;
   }
   output_sim->pid = pid;   
   
   uintptr_t base;
   if((base = GetBaseAddress(pid)) == 0)
   {
       return NULL;
   }

   char sum[1024];
   if(GetSha256Sum(pid, sum, sizeof(sum)) == NULL)
   {
       return NULL;
   }
   for(uint i = 0; i < LENGTH_1D(HashPairs); i++)
   {
       if(strncmp(HashPairs[i].sha256sum, sum, sizeof(sum)) == 0)
       {
           output_sim->ports = (void*)(base + HashPairs[i].offset);
           printf("gnusim8085 base: %p\n", base);    
           printf("ports start: %p\n", output_sim->ports);
           return output_sim;
       }
   }  
   
   return NULL;
}

uintptr_t GetBaseAddress(pid_t pid)
{
    char mapcmd[64];
    snprintf(mapcmd, sizeof(mapcmd), "head -n1 /proc/%llu/maps", pid);
    FILE *processMap = popen(mapcmd, "r");
    char result[1024];
    fgets(result, sizeof(result), processMap);
    pclose(processMap);
 
    uintptr_t base;
    bool passed = false;
    for(uint i = 0; i < 16; i++)
    {
        if(result[i] == '-')
        {           
            base = strtoll(result, NULL, 16);
            passed = true;
        }
    }
    if(!passed)
    {
        printf("Couldn't find base address\n");
        return 0;
    }

    return base;
}

const char *GetSha256Sum(pid_t pid, char *dest, uint len)
{
    char shacmd[64];
    snprintf(shacmd, sizeof(shacmd), "sha256sum /proc/%llu/exe", pid);
    FILE *hashFile = popen(shacmd, "r");
    char result[1024];  
    fgets(result, sizeof(result), hashFile);
    pclose(hashFile);

    if(len < sizeof(result))
        return NULL;
    sscanf(result, "%s", dest);
    
    return dest;
}
