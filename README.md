# io8085sim

Usable as a c library or perl module (using the c library).

`make or make debug` to compile the c library (Required for everything)

`make or make debug` in the examples directory to build the c example, in examples/bin

`perl examples/connect8085sims.pl $(pgrep gnusim)` redirects one or two gnusim8085 processes' IO ports buffer memory accesses from their own static storage to using a shared memory page.

The cool stuff is in Interop.pm

TODO add licensing. Assume GPLV2 for the examples and LGPL2.1 for the c library and perl module.


