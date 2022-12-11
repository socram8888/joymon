
#include "common.inc"

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

#
# Processes a read request
#
doread:
	jal readaddr
	move s0, v0

	# Read length
	jal uartread

	# Compute end of read
	add s1, s0, v0

	# Report command OK
	li a0, '+'
	jal uartwrite

readloop:
	beq s0, s1, repl
	lbu a0, 0(s0)
	jal uartwrite

	addi s0, 1
	j readloop

#
# Processes a write request
#
dowrite:
	jal readaddr
	move s0, v0

	# Read length
	jal uartread

	# Compute end of write
	add s1, s0, v0

writeloop:
	beq s0, s1, writedone
	jal uartread
	sb v0, 0(s0)

	addi s0, 1
	j writeloop

writedone:
	# Report command OK
	li a0, '+'
	jal uartwrite

	j repl

#
# Processes an execution request
#
# Does not return
#
doexec:
	jal readaddr
	move s0, v0

	# Acknowledge we're about to jump
	li a0, '+'
	jal uartwrite

	# Flush cache
	li t1, 0x44
	jal 0xA0

	# Jump!
	jalr s0

	# Run from start
	j __start

#
# Read an address from UART
#
# Returns: address
#
readaddr:
	addi sp, -24
	sw ra, 20(sp)
	sw s0, 16(sp)

	# Read first 8 bits
	jal uartread
	sll s0, v0, 24

	# Read second 8 bits
	jal uartread
	sll v0, 16
	or s0, v0

	# Read third 8 bits
	jal uartread
	sll v0, 8
	or s0, v0

	# Read last 8 bits
	jal uartread
	or v0, s0

	lw s0, 16(sp)
	lw ra, 20(sp)
	addi sp, 24

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
