#!/bin/bash

# assembler.sh - Converts .vsc files to .bin files

if [ $# -ne 1 ]; then
    echo "Usage: $0 <filename.vsc>"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${INPUT_FILE%.vsc}.bin"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File '$INPUT_FILE' not found"
    exit 1
fi

# Check if input file is empty
if [ ! -s "$INPUT_FILE" ]; then
    echo "Warning: File '$INPUT_FILE' is empty. No .bin file produced."
    exit 0
fi

# Initialize memory array (256 elements, all 0)
declare -a MEMORY
for i in {0..255}; do
    MEMORY[$i]=0
done

# Opcode definitions (from Figure 2)
LOAD=1
STORE=2
ADD=3
SUB=4
QUIT=8
PRINT=9

echo "Assembling $INPUT_FILE..."

# Flag to track if any valid instruction/data was found
FOUND_CONTENT=0

# Read the file line by line
while IFS= read -r line || [ -n "$line" ]; do
    # Remove leading/trailing whitespace
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Skip empty lines and comments
    if [ -z "$line" ] || [[ "$line" =~ ^// ]]; then
        continue
    fi
    
    # If we reach here, we have actual content
    FOUND_CONTENT=1
    
    # Check if this is a data line (address: value)
    if [[ "$line" =~ ^([0-9]+)[[:space:]]*:[[:space:]]*([0-9]+)$ ]]; then
        addr="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        
        if [ "$addr" -lt 0 ] || [ "$addr" -gt 255 ]; then
            echo "Error: Memory address $addr out of range (0-255)"
            exit 1
        fi
        if [ "$value" -lt 0 ] || [ "$value" -gt 255 ]; then
            echo "Error: Value $value out of range (0-255)"
            exit 1
        fi
        
        MEMORY[$addr]=$value
        echo "  Data: MEM[$addr] = $value"
        continue
    fi
    
    # Check if this is an instruction line (address: INSTRUCTION args)
    if [[ "$line" =~ ^([0-9]+)[[:space:]]*:[[:space:]]*([A-Z]+)[[:space:]]*(.*)$ ]]; then
        addr="${BASH_REMATCH[1]}"
        instr="${BASH_REMATCH[2]}"
        args="${BASH_REMATCH[3]}"
        
        # Remove extra spaces from args
        args=$(echo "$args" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Parse instruction
        case "$instr" in
            LOAD|STORE|ADD|SUB)
                # Format: LOAD/STORE/ADD/SUB R# address
                if [[ "$args" =~ ^R([0-3])[[:space:]]+([0-9]+)$ ]]; then
                    reg="${BASH_REMATCH[1]}"
                    mem_addr="${BASH_REMATCH[2]}"
                    
                    if [ "$mem_addr" -lt 0 ] || [ "$mem_addr" -gt 255 ]; then
                        echo "Error: Memory address $mem_addr out of range (0-255)"
                        exit 1
                    fi
                    
                    # Get opcode
                    case "$instr" in
                        LOAD) opcode=$LOAD ;;
                        STORE) opcode=$STORE ;;
                        ADD) opcode=$ADD ;;
                        SUB) opcode=$SUB ;;
                    esac
                    
                    # Build 16-bit instruction
                    instr_value=$(( (opcode << 10) | (reg << 8) | mem_addr ))
                    
                    # Split into two bytes (big endian)
                    high_byte=$(( (instr_value >> 8) & 0xFF ))
                    low_byte=$(( instr_value & 0xFF ))
                    
                    # Store in memory
                    MEMORY[$addr]=$high_byte
                    MEMORY[$((addr+1))]=$low_byte
                    
                    echo "  INSTR[$addr]: $instr R$reg $mem_addr -> [0x$(printf '%02X' $high_byte), 0x$(printf '%02X' $low_byte)]"
                else
                    echo "Error: Invalid $instr syntax: $args"
                    echo "Expected: $instr R# address"
                    exit 1
                fi
                ;;
                
            PRINT)
                # Format: PRINT R#
                if [[ "$args" =~ ^R([0-3])$ ]]; then
                    reg="${BASH_REMATCH[1]}"
                    
                    instr_value=$(( (PRINT << 10) | (reg << 8) | 0 ))
                    
                    high_byte=$(( (instr_value >> 8) & 0xFF ))
                    low_byte=$(( instr_value & 0xFF ))
                    
                    MEMORY[$addr]=$high_byte
                    MEMORY[$((addr+1))]=$low_byte
                    
                    echo "  INSTR[$addr]: PRINT R$reg -> [0x$(printf '%02X' $high_byte), 0x$(printf '%02X' $low_byte)]"
                else
                    echo "Error: Invalid PRINT syntax: $args"
                    echo "Expected: PRINT R#"
                    exit 1
                fi
                ;;
                
            QUIT)
                # Format: QUIT (no arguments)
                if [ -z "$args" ]; then
                    instr_value=$(( QUIT << 10 ))
                    
                    high_byte=$(( (instr_value >> 8) & 0xFF ))
                    low_byte=$(( instr_value & 0xFF ))
                    
                    MEMORY[$addr]=$high_byte
                    MEMORY[$((addr+1))]=$low_byte
                    
                    echo "  INSTR[$addr]: QUIT -> [0x$(printf '%02X' $high_byte), 0x$(printf '%02X' $low_byte)]"
                else
                    echo "Error: QUIT takes no arguments"
                    exit 1
                fi
                ;;
                
            *)
                echo "Error: Unknown instruction '$instr'"
                exit 1
                ;;
        esac
        continue
    fi
    
    # If we get here, the line didn't match any pattern
    echo "Warning: Skipping unrecognized line: $line"
    
done < "$INPUT_FILE"

# Check if any content was found
if [ $FOUND_CONTENT -eq 0 ]; then
    echo "Warning: File '$INPUT_FILE' contains no valid instructions or data. No .bin file produced."
    exit 0
fi

# Write the binary file
echo ""
echo "Writing binary to $OUTPUT_FILE..."

# Write memory as binary
{
    for i in {0..255}; do
        printf "\\x$(printf '%02x' ${MEMORY[$i]})"
    done
} > "$OUTPUT_FILE"

echo "Assembly complete! Output: $OUTPUT_FILE"
echo ""
echo "Memory dump (first 32 bytes):"
printf "      "
for i in {0..7}; do
    printf "0x%02X " $i
done
echo ""
for row in {0..3}; do
    start=$((row * 8))
    printf "0x%02X: " $start
    for i in {0..7}; do
        addr=$((start + i))
        printf "0x%02X " ${MEMORY[$addr]}
    done
    echo ""
done