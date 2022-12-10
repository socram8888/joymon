
#include <regdef.h>

.text
.globl __start

# Fixed-valued registers:
# gp = I/O start address (0x1F800000)

__start:
	# Disable all interrupts
	lui gp, 0x1f80
	sw zero, 0x1074(gp)

	# Restore stack pointer
	li t0, 0x801FFF00
	move sp, t0

	# Reset joystick registers via JOY_CTRL.6
	li t0, 0x20
	sh t0, 0x104A(gp)

	# Reset GPU with GPU1(00h)
	move t0, zero
	sw t0, 0x1814(gp)

	# Put DMA into FIFO mode with GPU1(04h), so we can check if FIFO is full later
	li t0, 0x04000001
	sw t0, 0x1814(gp)

	# Check if PAL - 0xBFC7FF52 should be 'E'
	lbu t0, 0xBFC7FF52
	li t1, 'E'
	bne t0, t1, ntsc

	# Horizontal display range with GP1(06h)
	li t0, 0x06C7E27E

	# Vertical display range with GP1(07h)
	li t1, 0x07000000 | (169 + 264 / 2) << 10 | (169 - 264 / 2)

	# PAL 15bpp 320x264 with GP1(08h)
	li t2, 0x08000009

	j dispon

ntsc:
	# Center the NTSC viewport in the PAL-sized drawing area using GP1(05h)
	li t0, 0x05000000 | ((264 - 224) / 2) << 10
	sw t0, 0x1814(gp)

	# Horizontal display range with GP1(06h)
	li t0, 0x06C58258

	# Vertical display range with GP1(07h)
	li t1, 0x07000000 | (140 + 224 / 2) << 10 | (140 - 224 / 2)

	# NTSC 15bpp 320x224 with GP1(08h)
	li t2, 0x08000001

dispon:
	# Execute all config commands
	sw t0, 0x1814(gp)
	sw t1, 0x1814(gp)
	sw t2, 0x1814(gp)

	# Enable display with GP1(03h)
	li t0, 0x03000000
	sw t0, 0x1814(gp)

	# Paint the image
	la a0, gpucmdstart
	li a1, (gpucmdend - gpucmdstart) / 4
	jal gpuexec

repl:
	jal uartread

	li t0, 'R'
	beq v0, t0, doread

	li t0, 'W'
	beq v0, t0, dowrite

	li t0, 'X'
	beq v0, t0, doexec

	# Report unknown command
	li a0, '-'
	jal uartwrite
	j repl

doread:
	jal readaddr

	# Read length
	jal uartread

	# Compute end of read
	add s2, s1, v0

	# Report command OK
	li a0, '+'
	jal uartwrite

readloop:
	beq s1, s2, repl
	lbu a0, 0(s1)
	jal uartwrite

	addi s1, 1
	j readloop

dowrite:
	jal readaddr

	# Read length
	jal uartread

	# Compute end of write
	add s2, s1, v0

writeloop:
	beq s1, s2, writedone
	jal uartread
	sb v0, 0(s1)

	addi s1, 1
	j writeloop

writedone:
	# Report command OK
	li a0, '+'
	jal uartwrite

	j repl

doexec:
	jal readaddr

	# Acknowledge we're about to jump
	li a0, '+'
	jal uartwrite

	# Flush cache
	li t1, 0x44
	jal 0xA0

	# Jump!
	jalr s1

	# Run from start
	j __start

#
# Read an address from UART
#
# Returns:
#  - s1: address
#
readaddr:
	addi sp, -4
	sw ra, 0(sp)

	# Read first 8 bits
	jal uartread
	sll s1, v0, 24

	# Read second 8 bits
	jal uartread
	sll v0, 16
	or s1, v0

	# Read third 8 bits
	jal uartread
	sll v0, 8
	or s1, v0

	# Read last 8 bits
	jal uartread
	or s1, v0

	lw ra, 0(sp)
	addi sp, 4

	jr ra

#
# UART WRITE
#
# Arguments:
#  - a0: byte to send
#
uartwrite:
	# Add start (0) and stop (1) bits to byte
	andi a0, 0xFF
	sll a0, 1
	ori a0, 0x200

	# Bits to send (1 start + 8 data + 1 stop)
	li t1, 10

	# Set timer 0 target to 293 cycles (33868800Hz/115200bps-1)
	li t0, 293
	sw t0, 0x1108(gp)

	# Start timer 0 in:
	# - Source clock to SysClk (33868800Hz)
	# - Free-running mode
	# - Reset on reaching target value
	# - IRQ on repeat mode (can be fired multiple times)
	# - Toggle IRQ flag (bit 10) on every IRQ
	#
	# We must not use the "reached target value" flag because that seems to be affected by some
	# kind of undocumented hardware errata. In real hardware, that flag can read zero if the
	# elapsed cycles between timer start and read and target values are both even or odd.
	#
	# Also note that although we are using the IRQ bits, interrupts are actually disabled so
	# we will busy poll the corresponding bits.
	li t0, 0x04D8
	sw t0, 0x1104(gp)

	# Current timer IRQ flag status
	li t2, 0x0400

uartwritebit:
	# Emit bit via /JOY pin of port 2.
	# We need to invert it, then put it into JOY_CTRL.13.
	# The XOR also sets the bit JOY_CTRL.2 which enables outputing the /JOY signal
	andi t0, a0, 1
	sll t0, 13
	xori t0, 0x2002
	sh t0, 0x104A(gp)

	# Shift right current buffer
	srl a0, 1

	# Decrement count while we're waiting
	addi t1, -1

	# Wait until the interrupt flag toggles
uartwritewait:
	lw t0, 0x1104(gp)
	andi t0, 0x0400
	beq t0, t2, uartwritewait

	# Save current IRQ flag status
	move t2, t0

	# If not done, keep going
	bne t1, zero, uartwritebit

	jr ra

#
# UART READ
#
# Returns:
#  - v0: read byte
#
uartread:
	# Wait for /ACK to go low (start bit)
	lh t0, 0x1044(gp)
	andi t0, 0x0080
	beq t0, zero, uartread

	# Set timer 0 target to half a bit, so we start sampling in the middle
	li t0, 146
	sw t0, 0x1108(gp)

	# Start timer 0. See uartwrite for a rationale of this value.
	li t0, 0x04D8
	sw t0, 0x1104(gp)

	# Wait until the IRQ flag toggles low
uartreadwaitmiddle:
	lw t0, 0x1104(gp)
	andi t0, 0x0400
	bne t0, zero, uartreadwaitmiddle

	# Load real delay
	li t0, 293
	sw t0, 0x1108(gp)

	# Read value
	move v0, zero

	# Bits to receive (8 data plus 1 stop)
	li t1, 9

	# Current timer IRQ flag status
	li t2, 0x0000

	# Wait until it reaches the target
uartreadbit:
	lw t0, 0x1104(gp)
	andi t0, 0x0400
	beq t0, t2, uartreadbit

	# Save current IRQ flag status
	move t2, t0

	# Read /ACK
	lh t0, 0x1044(gp)

	# Shift right current buffer
	srl v0, 1

	# We will now isolate the read bit, undo the inversion the hardware does,
	# and put in MSB of the receive buffer
	andi t0, 0x0080
	xori t0, 0x0080
	sll t0, 1
	or v0, t0

	# Decrement count
	addi t1, -1
	bne t1, zero, uartreadbit

	# Check that stop bit is high, else redo the entire process
	andi t0, v0, 0x100
	beq t0, zero, uartread

	# Return read byte
	andi v0, 0xFF
	jr ra

#
# GPU execute commands
#
# Arguments:
#  - a0: command start
#  - a1: word count
#
gpuexec:
	beq a1, zero, gpuexecdone

gpuwait:
	# Wait until the FIFO buffer is not full
	lw t0, 0x1814(gp)
	li t1, 1 << 25
	and t0, t1
	beq t0, zero, gpuwait

	# Store word, advance pointer and decrease count
	lw t0, 0(a0)
	addi a0, 4
	addi a1, -1
	sw t0, 0x1810(gp)

	bne a1, zero, gpuwait

gpuexecdone:
	jr ra

gpucmdstart:
	# Allow writing outside VSync
	.word 0xE1000400

	# Set drawing area bottom to 320x264
	.word 0xE4000000 | 264 << 10 | 320

#define COORD(x, y) ((y) << 16 | (x))

	# Black entire RAM
	.word 0x02000000
	.word COORD(  0,    0)
	.word COORD(1023, 511)

	# Square around M
	.word 0x60101010
	.word COORD(85, 75)
	.word COORD(320 - 85 - 85, 264 - 75 - 75)

	.word 0x60000000
	.word COORD(90, 80)
	.word COORD(320 - 90 - 90, 264 - 80 - 80)

#undef COORD

#define XOFF (320 / 2 - 80 / 2)
#define YOFF (264 / 2 - 80 / 2)
#define COORD(x, y) ((y) + YOFF) << 16 | ((x) + XOFF)

	# Left bar of the M
	.word 0x28202020
	.word COORD( 0,  0)
	.word COORD(10,  0)
	.word COORD( 0, 80)
	.word COORD(10, 80)

	# \ of the M
	.word 0x28202020
	.word COORD( 0,  0)
	.word COORD(10,  0)
	.word COORD(35, 80)
	.word COORD(45, 80)

	# / of the M
	.word 0x28202020
	.word COORD(70,  0)
	.word COORD(80,  0)
	.word COORD(35, 80)
	.word COORD(45, 80)

	# Right bar of the M
	.word 0x28202020
	.word COORD(70,  0)
	.word COORD(80,  0)
	.word COORD(70, 80)
	.word COORD(80, 80)

#undef XOFF
#undef YOFF
#undef COORD

gpucmdend:
