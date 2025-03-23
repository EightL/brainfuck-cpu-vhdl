# BrainFuck CPU Interpreter

## Project Overview
This project implements an 8-bit CPU in VHDL that interprets and executes BrainFuck programs. The CPU is designed as a finite state machine (FSM) that processes BrainFuck instructions one by one.

## Architecture

### Core Components
- **Program Counter (PC)**: Tracks the current instruction in program memory
- **Pointer (PTR)**: Memory pointer for data operations
- **Counter (CNT)**: Used for loop handling
- **Temporary Register (TMP)**: For storing temporary data

### Memory Interface
- 13-bit memory addressing (8KB memory space)
- 8-bit data width
- Read/write operations controlled by DATA_RDWR and DATA_EN signals

### I/O Operations
- Input port for reading external data
- Output port for displaying results (likely to an LCD display)
- Control signals for handling busy states and timing

## Supported Instructions

| Instruction | ASCII | Description |
|-------------|-------|-------------|
| `>` | 0x3E | Increment pointer |
| `<` | 0x3C | Decrement pointer |
| `+` | 0x2B | Increment value at pointer |
| `-` | 0x2D | Decrement value at pointer |
| `[` | 0x5B | Begin loop (if value at pointer is zero, jump to matching ']') |
| `]` | 0x5D | End loop (if value at pointer is non-zero, jump to matching '[') |
| `.` | 0x2E | Output value at pointer |
| `,` | 0x2C | Input value and store at pointer |
| `$` | 0x24 | Store value at pointer in TMP register |
| `!` | 0x21 | Load value from TMP register to pointer |
| `@` | 0x40 | Halt program execution |

## State Machine Implementation
The CPU uses a finite state machine to process instructions:
1. **Initialization**: Find '@' marker to locate the start of the program
2. **Fetch**: Read the next instruction from memory
3. **Decode**: Identify the instruction type
4. **Execute**: Perform the operation associated with the instruction
5. **Repeat**: Continue until halt instruction is encountered

## Sample Program
The repository includes a sample BrainFuck program (login.b) that outputs the author's login when executed.

## Implementation Details
- The READY signal indicates when the CPU has been initialized
- The DONE signal indicates when program execution has completed
- Loop handling uses a counter to track nesting levels
- The CPU handles memory operations synchronously with the clock

## Author
- xsevcim00 (Martin Ševčík)
- Faculty of Information Technology, Brno University of Technology

## Note
This project was completed as an assignment for the INP (Design of Computer Systems) course at FIT BUT.