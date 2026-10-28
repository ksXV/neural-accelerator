#!/usr/bin/env python3
"""
Generate BRAM memory initialization files (.mem) for the Systolic Array.

Parameters matching systolic_control_unit.sv:
- Matrix A: A_ROWS = 32, A_COLUMNS = 16
- Matrix B: B_ROWS = 16, B_COLUMNS = 24
- Systolic Array: N = 4, M = 4
- Output C = A x B: 32 rows x 24 columns (48 tiles of size 4x4)

Memory Layout:
- Data width: 8 bits per element
- Word width: 16 bits (DATA_WIDTH * 2) per address line in hex
- Memory depth: 1024 words (1 << ADDR_WIDTH, ADDR_WIDTH = 10)

BRAM assignment for N=4, M=4:
- Matrix A:
    Tile row r_tile in [0..7], tile starts at row_offset = r_tile * A_COLUMNS (step of 16)
    - a0.mem: holds row pairs (r_tile*4 + 0, r_tile*4 + 1)
              Word at (row_offset + k) = { A[r+1][k], A[r+0][k] }
    - a1.mem: holds row pairs (r_tile*4 + 2, r_tile*4 + 3)
              Word at (row_offset + k) = { A[r+3][k], A[r+2][k] }

- Matrix B:
    Tile col c_tile in [0..5], tile starts at column_offset = c_tile * B_STRIDE
    (By default B_STRIDE = B_COLUMNS = 24, matching systolic_control_unit.sv)
    - b0.mem: holds col pairs (c_tile*4 + 0, c_tile*4 + 1)
              Word at (column_offset + k) = { B[k][c+1], B[k][c+0] }
    - b1.mem: holds col pairs (c_tile*4 + 2, c_tile*4 + 3)
              Word at (column_offset + k) = { B[k][c+3], B[k][c+2] }
"""

import os
import sys
import argparse
import random

DEPTH = 1024

def make_matrix(rows, cols, pattern="simple", seed=42):
    random.seed(seed)
    if pattern == "simple":
        # Small values (1..4) to avoid early overflow and keep verification readable
        return [[((i + j) % 4) + 1 for j in range(cols)] for i in range(rows)]
    elif pattern == "incremental":
        # Monotonically increasing mod 16 + 1
        cnt = 1
        mat = []
        for i in range(rows):
            row = []
            for j in range(cols):
                row.append((cnt % 15) + 1)
                cnt += 1
            mat.append(row)
        return mat
    elif pattern == "random":
        return [[random.randint(1, 8) for _ in range(cols)] for _ in range(rows)]
    elif pattern == "identity_like":
        return [[1 if i == j else 0 for j in range(cols)] for i in range(rows)]
    else:
        raise ValueError(f"Unknown pattern: {pattern}")

def compute_matmul(A, B):
    a_rows = len(A)
    a_cols = len(A[0])
    b_rows = len(B)
    b_cols = len(B[0])
    assert a_cols == b_rows, f"Dimension mismatch: {a_rows}x{a_cols} vs {b_rows}x{b_cols}"

    C = [[0] * b_cols for _ in range(a_rows)]
    for i in range(a_rows):
        for j in range(b_cols):
            C[i][j] = sum(A[i][k] * B[k][j] for k in range(a_cols))
    return C

def generate_mem_files(out_dir="systolic_mem_files",
                       a_rows=32, a_cols=16,
                       b_rows=16, b_cols=24,
                       N=4, M=4,
                       b_stride=24,
                       pattern="simple", seed=42):
    os.makedirs(out_dir, exist_ok=True)

    print("==========================================================================")
    print("           SYSTOLIC ARRAY MEMORY GENERATOR")
    print(f"  Matrix A: {a_rows}x{a_cols}  |  Matrix B: {b_rows}x{b_cols}")
    print(f"  PE Array: {N}x{M}  |  BRAM Depth: {DEPTH} words")
    print(f"  Pattern: {pattern}  |  B-stride: {b_stride}")
    print("==========================================================================")

    A = make_matrix(a_rows, a_cols, pattern=pattern, seed=seed)
    B = make_matrix(b_rows, b_cols, pattern=pattern, seed=seed + 1)
    C = compute_matmul(A, B)

    # 1. Generate A memory files (N/2 files = 2 files: a0.mem, a1.mem)
    num_a_brams = N // 2
    row_tiles = a_rows // N
    for b_idx in range(num_a_brams):
        filepath = os.path.join(out_dir, f"a{b_idx}.mem")
        mem_words = [0] * DEPTH

        for r_tile in range(row_tiles):
            base_row = r_tile * N + 2 * b_idx
            row0 = base_row
            row1 = base_row + 1
            row_offset = r_tile * a_cols  # row_offset increments by A_COLUMNS per row tile

            for k in range(a_cols):
                val0 = A[row0][k] if row0 < a_rows else 0
                val1 = A[row1][k] if row1 < a_rows else 0
                addr = row_offset + k
                if addr < DEPTH:
                    mem_words[addr] = ((val1 & 0xFF) << 8) | (val0 & 0xFF)

        with open(filepath, "w") as f:
            for word in mem_words:
                f.write(f"{word:04x}\n")
        print(f"  [Created] {filepath:<30} (feeds rows offset +{2*b_idx}, +{2*b_idx+1})")

    # 2. Generate B memory files (M/2 files = 2 files: b0.mem, b1.mem)
    num_b_brams = M // 2
    col_tiles = b_cols // M
    for b_idx in range(num_b_brams):
        filepath = os.path.join(out_dir, f"b{b_idx}.mem")
        mem_words = [0] * DEPTH

        for c_tile in range(col_tiles):
            base_col = c_tile * M + 2 * b_idx
            col0 = base_col
            col1 = base_col + 1
            column_offset = c_tile * b_stride  # column_offset increments by b_stride per col tile

            for k in range(b_rows):
                val0 = B[k][col0] if col0 < b_cols else 0
                val1 = B[k][col1] if col1 < b_cols else 0
                addr = column_offset + k
                if addr < DEPTH:
                    mem_words[addr] = ((val1 & 0xFF) << 8) | (val0 & 0xFF)

        with open(filepath, "w") as f:
            for word in mem_words:
                f.write(f"{word:04x}\n")
        print(f"  [Created] {filepath:<30} (feeds cols offset +{2*b_idx}, +{2*b_idx+1})")

    # 3. Save reference files for testbench verification
    c_golden_path = os.path.join(out_dir, "c_golden.txt")
    with open(c_golden_path, "w") as f:
        for row in C:
            f.write(" ".join(f"{val:6d}" for val in row) + "\n")
    print(f"  [Created] {c_golden_path:<30} (expected C = A * B reference)")

    # Print summary statistics
    min_c = min(min(row) for row in C)
    max_c = max(max(row) for row in C)
    print(f"\nMatrix C ({a_rows}x{b_cols}) Golden Output Summary:")
    print(f"  Min value: {min_c}, Max value: {max_c}")
    print("  First 4x4 tile (Tile [0,0]):")
    for r in range(min(4, a_rows)):
        print("   ", " ".join(f"{C[r][c]:4d}" for c in range(min(4, b_cols))))
    print("==========================================================================")

    return A, B, C

def main():
    parser = argparse.ArgumentParser(description="Systolic Array Memory Generator")
    parser.add_argument("--outdir", default="systolic_mem_files", help="Output directory for .mem files")
    parser.add_argument("--pattern", choices=["simple", "incremental", "random", "identity_like"],
                        default="simple", help="Matrix data pattern")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument("--b-stride", type=int, default=24,
                        help="Stride between column tiles in BRAM (default: 24, matching systolic_control_unit)")
    args = parser.parse_args()

    generate_mem_files(
        out_dir=args.outdir,
        a_rows=32, a_cols=16,
        b_rows=16, b_cols=24,
        N=4, M=4,
        b_stride=args.b_stride,
        pattern=args.pattern,
        seed=args.seed
    )

if __name__ == "__main__":
    main()
