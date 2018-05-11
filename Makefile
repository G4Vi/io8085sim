CFLAGS = -Wall -Wextra -Wformat  -std=gnu11 -fno-strict-aliasing
DBG_CFLAGS = -DDEBUG -g
CC = gcc
BUILDDIR := build
LIBDIR := lib
SRCDIR := src

TARGET := $(LIBDIR)/libio8085sim.so

#main directives
debug: CFLAGS += $(DBG_CFLAGS)
debug: $(TARGET)
all: $(TARGET)

# combine objects into library
$(TARGET): $(BUILDDIR)/io8085sim.o
	mkdir -p $(@D)
	gcc -shared -o $@ $^

# compile each c file
$(BUILDDIR)/%.o : $(SRCDIR)/%.c
	@mkdir -p $(@D)
	$(CC) -c $^ $(CFLAGS) -o $@

clean:
	rm -f $(BUILDDIR)/*.o $(LIBDIR)/*

