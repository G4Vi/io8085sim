CFLAGS = -Wall -Wextra -Wformat  -std=gnu11 -fno-strict-aliasing
DBG_CFLAGS = -DDEBUG -g
CC = gcc
mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfile_dir:=$(shell cd $(shell dirname $(mkfile_path)); pwd)
current_dir := $(mkfile_dir)
BUILDDIR := build
LIBDIR := $(current_dir)/../lib
BINDIR := bin
SRCDIR := src
INCDIR := $(current_dir)/../src

TARGET := $(BINDIR)/io8085sim_test

#main directives
debug: CFLAGS += $(DBG_CFLAGS)
debug: $(TARGET)
all: $(TARGET)

# combine objects into library
$(TARGET): $(BUILDDIR)/io8085sim_test.o
	mkdir -p $(@D)
	gcc -L$(LIBDIR) -Wl,-rpath=$(LIBDIR) -o $@ $^ -lio8085sim

# compile each c file
$(BUILDDIR)/%.o : $(SRCDIR)/%.c
	@mkdir -p $(@D)
	$(CC) -I$(INCDIR) -c $^ $(CFLAGS) -o $@ 

clean:
	rm -f $(BUILDDIR)/*.o $(BINDIR)/*

