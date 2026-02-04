# AlignMemory.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://NittanyLion.github.io/AlignMemory.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://NittanyLion.github.io/AlignMemory.jl/dev/)
[![Build Status](https://github.com/NittanyLion/AlignMemory.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/NittanyLion/AlignMemory.jl/actions/workflows/CI.yml?query=branch%3Amain)

`AlignMemory.jl` addresses the issue that entries of collections (`Dicts`, `Arrays`, and `structs`) are not necessarily contiguous in memory.  It provides two functions:
1. `alignmem`
2. `deepalignmem` 

For instance, `s₂ = alignmem( s )` creates a copy of the contents of `s` in which the memory of the various elements of `s₂` are contiguous in memory. The advantage of this is that it reduces `cache misses` and should be expected to improve performance. 

Analogously, `s₃ = deepalignmem( s )` goes beyond `alignmem` by recursively going through `s`.  In other words, `deepalignmem` is to `alignmem` what `deepcopy` is to `copy`.

**Please read the documentation carefully.**

## Related packages

There are several other Julia packages that address memory layout and array storage, though with a different focus:

*   [RaggedArrays.jl](https://github.com/mbauman/RaggedArrays.jl): Provides contiguous memory storage specifically for arrays of arrays (jagged/ragged arrays).
*   [BlockArrays.jl](https://github.com/JuliaArrays/BlockArrays.jl): Focuses on partitioning arrays into blocks. The `BlockedArray` type stores the full array contiguously with a block structure overlaid.
*   [Strided.jl](https://github.com/Jutho/Strided.jl): Specialized for efficient strided array views and operations.
*   [UnsafeArrays.jl](https://github.com/JuliaArrays/UnsafeArrays.jl): Provides stack-allocated pointer-based array views.
*   [Buffers.jl](https://github.com/fkfest/Buffers.jl): Manages buffer allocation/deallocation for multidimensional arrays.

**AlignMemory.jl** differs by focusing specifically on physically aligning multiple independent arrays (which may be fields in a struct) into a single contiguous memory block to optimize cache usage, while using `unsafe_wrap` to present them as standard Julia arrays.
