
import serial
import struct

class PSMonitor:
	"""
	PlayStation 1 monitor tool.

	This tool is designed to talk to a software-based monitor running on a PS1 console, and allows
	reading, writing and executing from the console's memory space.

	Attributes:
		ser: Serial port instance
		max_chunk_length: Maximum length to read/write in a single command.
	"""

	def __init__(self, port):
		"""
		Creates a new monitor instance.

		Raises:
			SerialException: if an error with the COM port happens
		"""

		self.ser = serial.Serial(port, 115200)
		self.ser.timeout = 0.1

		self.__max_chunk_length = 128

	def close(self):
		"""
		Finalizes the terminal instance.
		"""

		self.ser.close()

	def read(self, addr: int, length: int) -> bytearray:
		"""
		Reads from a memory address.
		
		Args:
			addr: address to read from
			length: number of bytes to read

		Returns:
			bytearray: read bytes

		Raises:
			ValueError: if the address is out of bounds
			ProtocolException: if the console did not reply the expected data
			SerialException: if an error with the COM port happens
		"""

		if not isinstance(addr, int):
			raise ValueError('Address must be an integer')

		if addr < 0:
			raise ValueError('Address cannot be negative')

		if not isinstance(length, int):
			raise ValueError('Length must be an integer')

		if length < 0:
			raise ValueError('Length cannot be negative')

		if addr + length > 0xFFFFFFFF:
			raise ValueError('Read out of bounds')

		ret = bytearray()
		for off in range(0, length, self.__max_chunk_length):
			chunklen = min(length - off, self.__max_chunk_length)

			self.ser.write(b'R' + struct.pack(b'>LB', addr + off, chunklen))
			if self.ser.read(1) != b'+':
				raise ProtocolException("Console did not ACK")

			chunk = self.ser.read(chunklen)
			if len(chunk) != chunklen:
				raise ProtocolException("Unexpected end of read")

			ret.extend(chunk)

		return ret

	def write(self, addr: int, data: bytes | bytearray) -> None:
		"""
		Writes to a memory address.
		
		Args:
			addr: address to write to
			data: number of bytes to read

		Returns:
			bytearray: read bytes

		Raises:
			ValueError: if the address is out of bounds, or the max_chunk_length
			ProtocolException: if the communications fail
			SerialException: if an error with the COM port happens
		"""

		if not isinstance(addr, int):
			raise ValueError('Address must be an integer')

		if not isinstance(data, bytes) and not isinstance(data, bytearray):
			raise ValueError('Data must be either bytes or bytearray')

		if addr < 0:
			raise ValueError('Address cannot be negative')

		if addr + len(data) > 0xFFFFFFFF:
			raise ValueError('Write out of bounds')

		for off in range(0, len(data), self.__max_chunk_length):
			chunk = data[off : off + self.__max_chunk_length]

			self.ser.write(b'W' + struct.pack(b'>LB', addr + off, len(chunk)) + chunk)
			if self.ser.read(1) != b'+':
				raise ProtocolException("Console did not ACK")

	def call(self, addr: int) -> None:
		"""
		Calls code stored in memory.

		If the code returns, the monitor should be still listenint for further commands.

		Args:
			addr: address to call

		Raises:
			ValueError: if the address is out of bounds
			ProtocolException: if the communications fail
			SerialException: if an error with the COM port happens
		"""

		if addr < 0 or addr > 0xFFFFFFFF:
			raise ValueError('Address out of bounds')

		if addr % 4 != 0:
			raise ValueError('Unaligned address')

		self.ser.write(b'X' + struct.pack(b'>L', addr))
		if self.ser.read(1) != b'+':
			raise ProtocolException("Console did not ACK")

	def execute(self, exepath: str) -> None:
		"""
		Loads and executes the given PS-X executable.

		Args:
			exepath: location of file to load and execute

		Raises:
			FileNotFoundError: if the path does not exist
			ValueError: if the executable is invalid
			ProtocolException: if the communications fail
			SerialException: if an error with the COM port happens
		"""

		with open(exepath, 'rb') as f:
			exedata = f.read()

		if len(exedata) < 2048 or exedata[0:8] != b'PS-X EXE':
			raise ValueError('Invalid PSX executable')

		pcaddr, gpaddr, loadaddr, loadlen = struct.unpack('<LLLL', exedata[16:32])

		payload = exedata[2048 : 2048 + loadlen]
		if len(payload) < loadlen:
			raise ValueError('PSX executable is shorter than expected')

		self.write(loadaddr, payload)
		self.call(pcaddr)

	def wait_for_ready(self):
		"""
		Waits until the terminal is ready for commands.

		Raises:
			SerialException: if an error with the COM port happens
		"""

		while True:
			self.ser.write(b'-')
			if self.ser.read() == b'-':
				return

	@property
	def max_chunk_length(self):
		"""
		Maximum length to read/write in a single command. Between 1 and 255.
		"""

		return self.__max_chunk_length

	@max_chunk_length.setter
	def max_chunk_length(self, value: int):
		if not isinstance(value, int):
			raise ValueError('Value must be an integer')

		if value < 1 or value > 255:
			raise ValueError('Value out of bounds')

		self.__max_chunk_length = value

	def __enter__(self):
		pass

	def __exit__(self, exc_type, exc_value, traceback):
		self.close()

class ProtocolException(Exception):
	"""
	A protocol error while talking to the console.
	"""
	pass

if __name__ == '__main__':
	import argparse

	parser = argparse.ArgumentParser(description='PS1 monitor load tool')
	parser.add_argument('port', help='COM port')
	parser.add_argument('exe', help='PSX executable path')
	args = parser.parse_args()

	t = PSMonitor(args.port)
	t.wait_for_ready()
	t.execute(args.exe)
