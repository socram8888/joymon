
#include <regdef.h>

.text
.globl __start

# Fixed-valued registers:
# s0 = I/O start address (0x1F800000)

__start:
	# Restore stack pointer
	li t0, 0x801FFF00
	move sp, t0

	# Paint dark green
	li a0, 0x004000
	jal paintscr

	# Disable all interrupts
	lui s0, 0x1f80
	sw zero, 0x1074(s0)

	# Reset joystick registers via JOY_CTRL.6
	li t0, 0x20
	sh t0, 0x104A(s0)

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
#  - s0: I/O start address (0x1F800000)
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
	sw t0, 0x1108(s0)

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
	sw t0, 0x1104(s0)

	# Current timer IRQ flag status
	li t2, 0x0400

uartwritebit:
	# Emit bit via /JOY pin of port 2.
	# We need to invert it, then put it into JOY_CTRL.13.
	# The XOR also sets the bit JOY_CTRL.2 which enables outputing the /JOY signal
	andi t0, a0, 1
	sll t0, 13
	xori t0, 0x2002
	sh t0, 0x104A(s0)

	# Shift right current buffer
	srl a0, 1

	# Decrement count while we're waiting
	addi t1, -1

	# Wait until the interrupt flag toggles
uartwritewait:
	lw t0, 0x1104(s0)
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
# Arguments:
#  - s0: I/O start address (0x1F800000)
#
# Returns:
#  - v0: read byte
#
uartread:
	# Wait for /ACK to go low (start bit)
	lh t0, 0x1044(s0)
	andi t0, 0x0080
	beq t0, zero, uartread

	# Set timer 0 target to half a bit, so we start sampling in the middle
	li t0, 146
	sw t0, 0x1108(s0)

	# Start timer 0. See uartwrite for a rationale of this value.
	li t0, 0x04D8
	sw t0, 0x1104(s0)

	# Wait until the IRQ flag toggles low
uartreadwaitmiddle:
	lw t0, 0x1104(s0)
	andi t0, 0x0400
	bne t0, zero, uartreadwaitmiddle

	# Load real delay
	li t0, 293
	sw t0, 0x1108(s0)

	# Read value
	move v0, zero

	# Bits to receive (8 data plus 1 stop)
	li t1, 9

	# Current timer IRQ flag status
	li t2, 0x0000

	# Wait until it reaches the target
uartreadbit:
	lw t0, 0x1104(s0)
	andi t0, 0x0400
	beq t0, t2, uartreadbit

	# Save current IRQ flag status
	move t2, t0

	# Read /ACK
	lh t0, 0x1044(s0)

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

paintscr:
	# Add command byte to a0
	li t0, 0x02000000
	or t0, a0

	# Calculate effective address
	la a0, redscreen

	# Store color with command on buffer
	sw t0, 4(a0)

	# Tail call GPU_cwp to paint the entire screen
	li a1, 4
	li t1, 0x4A
	j 0xA0

redscreen:
	# Allow writing outside VSync
	.word 0xE1000400
	# Space for color and command
	.word 0
	# Start X and Y = 0
	.word 0x00000000
	# Width of 1024, height of 512
	.word 0x01FF03FF
