
#include "common.inc"

#
# Read a byte from UART
#
# Returns: read byte, or -1 if timed out
#
.globl uartread
uartread:
	# Start bit timeout in cycles, of half a second. 7 is the number of instructions in the loop.
	li t1, (CPU_HZ / 7 / 2)

uartreadwaitack:
	# If timed out, fail
	addi t1, -1
	beq t1, zero, uartreadfail

	# Check if /ACK is low (start bit), and keep iterating if not
	lh t0, 0x1044(gp)
	andi t0, 0x0080
	beq t0, zero, uartreadwaitack

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

	# Check that stop bit is high, else fail
	andi t0, v0, 0x100
	beq t0, zero, uartreadfail

	# Return read byte
	andi v0, 0xFF
	jr ra

uartreadfail:
	li v0, -1
	jr ra

#
# Write a byte to UART
#
# Arguments:
#  - a0: byte to send
#
.globl uartwrite
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
# Send from a buffer to UART
#
# Arguments:
#  - a0: buffer
#  - a1: length
#
.globl uartsendbuf
uartsendbuf:
	# Early exit if zero
	beq a1, zero, uartsendbufra

	# Save registers
	addi sp, -28
	sw ra, 24(sp)
	sw s1, 20(sp)
	sw s0, 16(sp)

	# Save current address and calculate end address
	move s0, a0
	add s1, a0, a1

uartsendbufnext:
	# Load byte and send straight away
	lbu a0, 0(s0)
	jal uartwrite

	# Increment counter and continue if not done
	addi s0, 1
	bne s0, s1, uartsendbufnext

	# Load saved registers
	lw s0, 16(sp)
	lw s1, 20(sp)
	lw ra, 24(sp)
	addi sp, 28

uartsendbufra:
	jr ra

#
# Receives from UART into a buffer
#
# Arguments:
#  - a0: buffer
#  - a1: length
# Returns: 1 if received, 0 if a reception error occured
#
.globl uartrecvbuf
uartrecvbuf:
	# Early exit if zero
	li v0, 1
	beq a1, zero, uartrecvbufra

	# Save registers
	addi sp, -28
	sw ra, 24(sp)
	sw s1, 20(sp)
	sw s0, 16(sp)

	# Save current address and calculate end address
	move s0, a0
	add s1, a0, a1

uartrecvbufnext:
	# Read byte
	jal uartread

	# If value is not negative, it was received okay
	bgez v0, uartrecvbufok

	# Load fail value and return
	li v0, 0
	b uartrecvbufret

uartrecvbufok:
	# Save read byte
	sb v0, 0(s0)

	# Increment pointer
	addi s0, 1

	# Do next iteration if not done - else fall through with v0 to 1
	li v0, 1
	bne s0, s1, uartrecvbufnext

uartrecvbufret:
	# Load saved registers
	lw s0, 16(sp)
	lw s1, 20(sp)
	lw ra, 24(sp)
	addi sp, 28

uartrecvbufra:
	jr ra
