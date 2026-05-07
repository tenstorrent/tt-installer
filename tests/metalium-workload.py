#!/usr/bin/env python3
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0
#
# Smoke test for the tt-metalium container on an N150 device.
# Opens a device, runs a simple tensor add, and verifies the result.
# Run via: docker run ... --entrypoint python3 <image> /metalium-workload.py
import torch
import ttnn

device = ttnn.open_device(device_id=0)
print("Opened device:", device)

a = ttnn.from_torch(
    torch.ones(32, 32, dtype=torch.bfloat16),
    dtype=ttnn.bfloat16,
    layout=ttnn.TILE_LAYOUT,
    device=device,
)
b = ttnn.add(a, a)
result = ttnn.to_torch(b)

expected = 2.0
got = float(result[0][0])
assert got == expected, f"Expected {expected}, got {got}"
print(f"Tensor add result: {got} (expected {expected})")

ttnn.close_device(device)
print("✓ tt-metalium workload passed")
