#pragma once

#include <stdbool.h>
#include <sys/types.h>

typedef enum {
    IO8085Sim_GNUSim8085 = 1 << 0,
} IO8085Sim_t;

#define IMPLEMENT_IO8085Sim \
struct { \
    IO8085Sim_t type; \
}

typedef IMPLEMENT_IO8085Sim IO8085Sim;

typedef struct GNUSim8085 {
    IMPLEMENT_IO8085Sim;
    pid_t pid;
    void *ports;
} GNUSim8085; 

bool io8085sim_read_ports(IO8085Sim *unknown_sim, unsigned int start_port, unsigned int num, void *dest);

bool io8085sim_write_ports(IO8085Sim *unknown_sim, unsigned int start_port, unsigned int num, void *src);



