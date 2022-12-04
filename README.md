
PS1 monitor
===========

Software-only serial monitor for reading, writing and executing arbitrary memory locations.

Instead of relying on the physical serial port present in fat PS1 consoles, this tool uses the
controller port's /SEL and /ACK pins to emulate an UART in software, allowing it to be used in
fat PS1 and slim PSone consoles (and possibly PS2 as well).
