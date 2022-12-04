
# Thanks to whoever made https://devhints.io/makefile!

CC=mips-linux-gnu-gcc
CFLAGS=-O1 -Wall -Wextra -EL -march=r3000 -mfp32 -mno-abicalls -fno-pic

LD=mips-linux-gnu-ld

all: monitor.exe monitor.bin monitor.cue monitor-scph102.mcd

monitor.exe: monitor.S monitor.ld
	$(CC) $(CFLAGS) -c monitor.S
	$(LD) -T monitor.ld monitor.o -o monitor.exe

monitor.bin monitor.cue: monitor.exe system.cnf cd.xml licensee.dat
	mkpsxiso -y cd.xml

monitor-scph102.mcd: monitor.exe | FreePSXBoot/builder/builder
	FreePSXBoot/builder/builder -bios 4.4-20000324-A -slot 2 -in monitor.exe -out $@

clean:
	$(RM) *.o monitor.exe monitor.bin monitor.cue
