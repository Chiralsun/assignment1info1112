#!/bin/bash

# --- Validation checks ---
if [ $# -lt 1 ]; then
    echo "usage: no argument provided"
    exit 1
fi

if [ $# -gt 1 ]; then
    echo "usage: more than one arguments are provided"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "usage: input is not a file or it does not exist"
    exit 1
fi

if [ ! -s "$INPUT_FILE" ]; then
    echo "usage: the file is empty - no .bin file is produced"
    exit 0
fi

if [[ "$INPUT_FILE" != *.vsc ]]; then
    echo "usage: input does not have the extension .vsc"
    exit 1
fi

# --- Read n_values and static values ---
N_VALUES=$(head -n 1 "$INPUT_FILE" | tr -d '\r')

declare -a STATIC_VALUES
for ((i = 0; i < N_VALUES; i++)); do
    line_num=$((i + 2))
    val=$(sed -n "${line_num}p" "$INPUT_FILE" | tr -d '\r')
    STATIC_VALUES+=("$val")
done

INSTR_START=$((N_VALUES + 2))






# --- Opcode table ---
declare -A OPCODES=(
    [LOAD]=1
    [STORE]=2
    [ADD]=3
    [SUB]=4
    [QUIT]=8
    [PRINT]=9
)

# --- Build the byte stream ---
declare -a BYTES
for v in "${STATIC_VALUES[@]}"; do
    BYTES+=("$v")
done

FIRST=1                # true until we process the first instruction
IS_QUIT_PROGRAM=0      # 1 if the first instruction is QUIT
ADDSUB_PRINTED=0       # 1 once we've printed the ADD/SUB message

while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue

    IFS=',' read -ra FIELDS <<< "$line"
    OP="${FIELDS[0]}"
    REG="${FIELDS[1]}"
    ADDR="${FIELDS[2]}"

    # --- First instruction: figure out program type ---
    if [ "$FIRST" -eq 1 ]; then
        if [ "$OP" = "QUIT" ]; then
            echo "It is a QUIT program"
            IS_QUIT_PROGRAM=1
        fi
        FIRST=0
    fi

    # --- ADD/SUB detection (only if first instruction was NOT QUIT) ---
    if [ "$IS_QUIT_PROGRAM" -eq 0 ] && [ "$ADDSUB_PRINTED" -eq 0 ]; then
        if [ "$OP" = "ADD" ] || [ "$OP" = "SUB" ]; then
            echo "It is an ADD/SUB program"
            ADDSUB_PRINTED=1
        fi
    fi

    # --- Encode the instruction ---
    OPCODE=${OPCODES[$OP]}
    if [ -z "$OPCODE" ]; then
        echo "Unknown opcode: $OP"
        exit 1
    fi

    BYTE1=$(( (OPCODE << 2) | REG ))
    BYTE2=$ADDR

    BYTES+=("$BYTE1" "$BYTE2")
done < <(tail -n +"$INSTR_START" "$INPUT_FILE")






#tutor says: create an output bin file, and then print out the bin file contents

# --- Write the .bin file ---
OUTPUT_FILE="${INPUT_FILE%.vsc}.bin"

# Truncate or create the file
: > "$OUTPUT_FILE"

# Write each byte as a raw byte
for byte in "${BYTES[@]}"; do
    printf "\\x$(printf '%02x' "$byte")" >> "$OUTPUT_FILE"
done

# --- Read it back and print each byte in hex ---
echo "The content of the .bin file is"

xxd -p "$OUTPUT_FILE" | fold -w2


exit 0
