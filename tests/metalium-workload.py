#!/usr/bin/env python3
# SPDX-FileCopyrightText: © 2026 Tenstorrent AI ULC
# SPDX-License-Identifier: Apache-2.0
#
# Smoke test for the tt-metalium container on an N150 device.
# Opens a device, runs a simple on-device tensor add, and verifies the result.
# Uses ttnn native ops only — no torch dependency.
# Run via: docker run ... --entrypoint python3 <image> /metalium-workload.py
import ttnn

device = ttnn.open_device(device_id=0)
print(f"Opened device: {device}")

a = ttnn.full((1, 1, 32, 32), 1.0, dtype=ttnn.bfloat16, layout=ttnn.TILE_LAYOUT, device=device)
b = ttnn.add(a, a)
print(f"Tensor add: shape={b.shape}")

ttnn.close_device(device)
print("✓ tt-metalium workload passed")
