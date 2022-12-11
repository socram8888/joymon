
# Thanks to whoever made https://devhints.io/makefile!

CC := $(shell which mips-linux-gnu-gcc mips-linux-gnu-gcc-10 mips-linux-gnu-gcc-11 mips-linux-gnu-gcc-12 | head -n 1)
CFLAGS = -Os -Wall -Wextra -EL -march=r3000 -mfp32 -mno-abicalls -fno-pic

ifeq ($(CC),)
    $(error Cannot find MIPS GCC compiler)
endif

LD := mips-linux-gnu-ld

MONITOR_OBJECTS := $(patsubst %.S, %.o, $(wildcard *.S))

all: monitor.exe monitor.bin monitor.cue monitor-scph102.mcd

%.o: %.S
	$(CC) $(CFLAGS) -c $<

monitor.elf: $(MONITOR_OBJECTS)
	$(LD) -EL $(MONITOR_OBJECTS) -o monitor.elf

monitor.exe: monitor.ld monitor.elf
	$(LD) -T monitor.ld monitor.elf -o monitor.exe

monitor.bin monitor.cue: monitor.exe system.cnf cd.xml licensee.dat
	mkpsxiso -y cd.xml

monitor-scph102.mcd: monitor.exe | FreePSXBoot/builder/builder
	FreePSXBoot/builder/builder -bios 4.4-20000324-A -slot 2 -in monitor.exe -out $@

clean:
	$(RM) *.o monitor.exe monitor.bin monitor.cue
