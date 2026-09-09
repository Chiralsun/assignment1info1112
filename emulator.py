#!/usr/bin/env python3
"""
emulator.py - Executes VSC binary files
Usage: python3 emulator.py <filename.bin>
"""

import sys
import struct

# Opcodes from Figure 2
OPCODES = {
    'LOAD': 1,
    'STORE': 2,
    'ADD': 3,
    'SUB': 4,
    'QUIT': 8,
    'PRINT': 9
}

# Reverse lookup: opcode -> name
OPCODE_NAMES = {
    1: 'LOAD',
    2: 'STORE',
    3: 'ADD',
    4: 'SUB',
    8: 'QUIT',
    9: 'PRINT'
}

class VSCEmulator:
    """Very Simple Computer Emulator"""
    
    def __init__(self):
        # Memory: 256 bytes, all initialized to 0
        self.memory = [0] * 256
        
        # Registers: 4 registers (R0, R1, R2, R3), all 0
        self.registers = [0, 0, 0, 0]
        
        # Program Counter: address of next instruction
        self.pc = 0
        
        # Flag to indicate if the program is running
        self.running = True
        
        # Output buffer for PRINT instructions
        self.output = []
        
        # Instruction count (for debugging)
        self.instruction_count = 0
    
    def load_binary(self, filename):
        """Load binary file into memory"""
        try:
            with open(filename, 'rb') as f:
                data = f.read()
                
                # Check file size
                if len(data) > 256:
                    print(f"Warning: File larger than 256 bytes ({len(data)} bytes)")
                    data = data[:256]
                elif len(data) < 256:
                    print(f"Warning: File smaller than 256 bytes ({len(data)} bytes)")
                    # Pad with zeros
                    data = data + b'\x00' * (256 - len(data))
                
                # Load into memory
                for i, byte in enumerate(data):
                    self.memory[i] = byte
                    
        except FileNotFoundError:
            print(f"Error: File '{filename}' not found")
            sys.exit(1)
        except Exception as e:
            print(f"Error loading file: {e}")
            sys.exit(1)
    
    def decode_instruction(self, address):
        """Decode a 16-bit instruction from memory at given address"""
        # Read 2 bytes (high byte, low byte)
        high_byte = self.memory[address]
        low_byte = self.memory[address + 1]
        
        # Combine into 16-bit value (big endian)
        instr_value = (high_byte << 8) | low_byte
        
        # Extract fields:
        # [6-bit opcode][2-bit register][8-bit address]
        opcode = (instr_value >> 10) & 0x3F  # 6 bits
        reg = (instr_value >> 8) & 0x03      # 2 bits
        mem_addr = instr_value & 0xFF        # 8 bits
        
        return opcode, reg, mem_addr, instr_value
    
    def execute_instruction(self, opcode, reg, mem_addr):
        """Execute a single instruction"""
        
        if opcode == OPCODES['LOAD']:
            # LOAD: R <- Memory[Address]
            self.registers[reg] = self.memory[mem_addr]
            print(f"  LOAD R{reg} {mem_addr} -> R{reg} = {self.registers[reg]}")
            
        elif opcode == OPCODES['STORE']:
            # STORE: Memory[Address] <- R
            self.memory[mem_addr] = self.registers[reg]
            print(f"  STORE R{reg} {mem_addr} -> MEM[{mem_addr}] = {self.memory[mem_addr]}")
            
        elif opcode == OPCODES['ADD']:
            # ADD: R <- R + Memory[Address]
            result = self.registers[reg] + self.memory[mem_addr]
            
            # Handle 8-bit overflow (wrap around 0-255)
            if result > 255:
                result = result % 256
                print(f"  ADD R{reg} {mem_addr} -> Overflow! Result = {result} (wrapped)")
            else:
                print(f"  ADD R{reg} {mem_addr} -> R{reg} = {self.registers[reg]} + {self.memory[mem_addr]} = {result}")
            
            self.registers[reg] = result
            
        elif opcode == OPCODES['SUB']:
            # SUB: R <- R - Memory[Address] (only if R >= Memory[Address])
            if self.registers[reg] >= self.memory[mem_addr]:
                result = self.registers[reg] - self.memory[mem_addr]
                self.registers[reg] = result
                print(f"  SUB R{reg} {mem_addr} -> R{reg} = {self.registers[reg]} - {self.memory[mem_addr]} = {result}")
            else:
                print(f"  SUB R{reg} {mem_addr} -> ERROR: R{reg} ({self.registers[reg]}) < MEM[{mem_addr}] ({self.memory[mem_addr]})")
                print(f"  Operation failed! Register and memory unchanged.")
            
        elif opcode == OPCODES['PRINT']:
            # PRINT: Display register content
            value = self.registers[reg]
            self.output.append(str(value))
            print(f"  PRINT R{reg} -> {value}")
            
        elif opcode == OPCODES['QUIT']:
            # QUIT: Stop execution
            print(f"  QUIT -> Stopping program")
            self.running = False
            
        else:
            print(f"  ERROR: Unknown opcode {opcode} at address {self.pc}")
            self.running = False
    
    def run(self, debug=True):
        """Run the program"""
        print("\n" + "="*60)
        print("VSC Emulator Starting...")
        print("="*60)
        print()
        
        # Program starts at address 0 (or wherever the first instruction is)
        # We'll start at 0 and look for instructions
        self.pc = 0
        
        while self.running and self.pc < 256