#!/bin/bash

# emulator.sh - Executes VSC binary files
# Usage: bash emulator.sh <filename.bin>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <filename.bin>"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File '$INPUT_FILE' not found"
    exit 1
fi

# Opcode definitions (from Figure 2)
LOAD=1
STORE=2
ADD=3
SUB=4
QUIT=8
PRINT=9

# Initialize memory (256 bytes, all 0)
declare -a MEMORY
for i in {0..255}; do
    MEMORY[$i]=0
done

# Initialize registers (4 registers, all 0)
declare -a REGISTERS
for i in {0..3}; do
    REGISTERS[$i]=0
done

# Program Counter
PC=0

# Running flag
RUNNING=1

# Output buffer
OUTPUT=""

echo ""
echo "============================================================"
echo "VSC Emulator Starting..."
echo "============================================================"
echo ""

# Load binary file into memory
echo "Loading binary file: $INPUT_FILE"

# Read binary file using od (octal dump) or xxd
if command -v xxd &> /dev/null; then
    # Using xxd (more common)
    HEX_DATA=$(xxd -p -c 256 "$INPUT_FILE" | head -1)
    
    # Convert hex to decimal and store in memory
    for i in {0..255}; do
        offset=$((i * 2))
        if [ $offset -lt ${#HEX_DATA} ]; then
            HEX_BYTE="${HEX_DATA:$offset:2}"
            if [ -n "$HEX_BYTE" ]; then
                DECIMAL=$((16#$HEX_BYTE))
                MEMORY[$i]=$DECIMAL
            fi
        fi
    done
elif command -v od &> /dev/null; then
    # Using od (alternative)
    BYTES=$(od -An -tx1 -v "$INPUT_FILE" | tr -d '\n' | tr -s ' ')
    BYTES_ARRAY=($BYTES)
    
    for i in {0..255}; do
        if [ $i -lt ${#BYTES_ARRAY[@]} ]; then
            MEMORY[$i]=$((16${BYTES_ARRAY[$i]}))
        fi
    done
else
    echo "Error: Neither xxd nor od found. Please install one of them."
    exit 1
fi

echo "Memory loaded successfully!"
echo ""

# Show memory dump (first 32 bytes)
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
echo ""

# Decode instruction function
decode_instruction() {
    local addr=$1
    local high_byte=${MEMORY[$addr]}
    local low_byte=${MEMORY[$((addr + 1))]}
    
    # Combine into 16-bit value (big endian)
    local instr_value=$(( (high_byte << 8) | low_byte ))
    
    # Extract fields: [6-bit opcode][2-bit register][8-bit address]
    
    local opcode=$(( (instr_value >> 10) & 0x3F ))
    local reg=$(( (instr_value >> 8) & 0x03 ))
    local mem_addr=$(( instr_value & 0xFF ))
    
    echo "$opcode $reg $mem_addr $instr_value"
}

# Execute program
echo "Starting execution..."
echo ""

while [ $RUNNING -eq 1 ] && [ $PC -lt 256 ]; do
    # Check if we have a valid instruction (opcode > 0)
    # If MEMORY[PC] is 0, we might be at data, skip forward
    if [ ${MEMORY[$PC]} -eq 0 ] && [ ${MEMORY[$((PC + 1))]} -eq 0 ]; then
        # Skip zeros (data section)
        PC=$((PC + 2))
        continue
    fi
    
    # Decode instruction at PC
    read opcode reg mem_addr instr_value <<< $(decode_instruction $PC)
    
    # Get instruction name
    case $opcode in
        $LOAD) instr_name="LOAD" ;;
        $STORE) instr_name="STORE" ;;
        $ADD) instr_name="ADD" ;;
        $SUB) instr_name="SUB" ;;
        $QUIT) instr_name="QUIT" ;;
        $PRINT) instr_name="PRINT" ;;
        *) instr_name="UNKNOWN" ;;
    esac
    
    # Skip if opcode is 0 (data section)
    if [ $opcode -eq 0 ]; then
        PC=$((PC + 2))
        continue
    fi
    
    # Print instruction (for debugging)
    printf "  %-6s R%d %3d" "$instr_name" $reg $mem_addr
    
    # Execute instruction
    case $opcode in
        $LOAD)
            # LOAD: R <- Memory[Address]
            REGISTERS[$reg]=${MEMORY[$mem_addr]}
            printf " -> R%d = %d\n" $reg ${REGISTERS[$reg]}
            ;;
            
        $STORE)
            # STORE: Memory[Address] <- R
            MEMORY[$mem_addr]=${REGISTERS[$reg]}
            printf " -> MEM[%d] = %d\n" $mem_addr ${MEMORY[$mem_addr]}
            ;;
            
        $ADD)
            # ADD: R <- R + Memory[Address]
            local result=$(( ${REGISTERS[$reg]} + ${MEMORY[$mem_addr]} ))
            if [ $result -gt 255 ]; then
                result=$((result % 256))
                printf " -> Overflow! Result = %d (wrapped)\n" $result
            else
                printf " -> R%d = %d + %d = %d\n" $reg ${REGISTERS[$reg]} ${MEMORY[$mem_addr]} $result
            fi
            REGISTERS[$reg]=$result
            ;;
            
        $SUB)
            # SUB: R <- R - Memory[Address] (only if R >= Memory[Address])
            if [ ${REGISTERS[$reg]} -ge ${MEMORY[$mem_addr]} ]; then
                local result=$(( ${REGISTERS[$reg]} - ${MEMORY[$mem_addr]} ))
                REGISTERS[$reg]=$result
                printf " -> R%d = %d - %d = %d\n" $reg ${REGISTERS[$reg]} ${MEMORY[$mem_addr]} $result
            else
                printf " -> ERROR: R%d (%d) < MEM[%d] (%d)\n" $reg ${REGISTERS[$reg]} $mem_addr ${MEMORY[$mem_addr]}
                printf "    Operation failed! Register and memory unchanged.\n"
            fi
            ;;
            
        $PRINT)
            # PRINT: Display register content
            local value=${REGISTERS[$reg]}
            OUTPUT="${OUTPUT}${value}\n"
            printf " -> %d\n" $value
            ;;
            
        $QUIT)
            # QUIT: Stop execution
            printf " -> Stopping program\n"
            RUNNING=0
            ;;
            
        *)
            printf " -> ERROR: Unknown opcode %d at address %d\n" $opcode $PC
            RUNNING=0
            ;;
    esac
    
    # Move to next instruction (2 bytes per instruction)
    PC=$((PC + 2))
    
    # Safety check: prevent infinite loop
    INSTR_COUNT=$((INSTR_COUNT + 1))
    if [ $INSTR_COUNT -gt 1000 ]; then
        echo ""
        echo "ERROR: Too many instructions executed (limit 1000). Possible infinite loop."
        RUNNING=0
    fi
done

echo ""
echo "============================================================"
echo "Program Execution Complete!"
echo "============================================================"
echo ""

# Show final state
echo "Final Register State:"
for i in {0..3}; do
    echo "  R$i = ${REGISTERS[$i]}"
done
echo ""

# Show output
if [ -n "$OUTPUT" ]; then
    echo "Program Output:"
    echo -e "$OUTPUT"
    echo ""
else
    echo "No output generated."
    echo ""
fi

# Show memory dump (first 32 bytes)
echo "Final Memory State (first 32 bytes):"
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

# Show registers (hex)
echo ""
echo "Final Register State (hex):"
for i in {0..3}; do
    printf "  R%d = 0x%02X (%d)\n" $i ${REGISTERS[$i]} ${REGISTERS[$i]}
done

echo ""
echo "Emulator finished." 