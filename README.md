<div align="center">

# AlignMemory.jl 🧠⚡

**Optimize your memory layout for maximum cache efficiency.**

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://NittanyLion.github.io/AlignMemory.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://NittanyLion.github.io/AlignMemory.jl/dev/)
[![Build Status](https://github.com/NittanyLion/AlignMemory.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/NittanyLion/AlignMemory.jl/actions/workflows/CI.yml?query=branch%3Amain)

</div>

---

## 🚀 The Problem vs. The Solution

Standard collections in Julia (`Dict`s, `Array`s of `Array`s, `struct`s) often scatter data across memory, causing frequent **cache misses**. `AlignMemory.jl` packs this data into contiguous blocks.

The advantage of contiguity is that it reduces cache misses and should be expected to improve performance.

### 🔮 How it works

| Function | Description | Analogy |
| :--- | :--- | :--- |
| **`alignmem(x)`** | Aligns immediate fields of `x` | Like `copy(x)` but packed |
| **`deepalignmem(x)`** | Recursively aligns nested structures | Like `deepcopy(x)` but packed |

---

## ⚡ Performance Example

In scientific computing, memory locality is everything.

> **Benchmark Result:**
> `original`: 159.177 μs
> `alignmem`: **111.251 μs** (🚀 43% Faster)

<details>
<summary><b>Click to see the benchmark code</b></summary>

```julia
using AlignMemory, BenchmarkTools, StyledStrings

function original( A = 10_000, L = 100, S = 5000)
    x = Vector{Vector{Float64}}(undef, A)
    s = Vector{Vector{Float64}}(undef, A)
    for i ∈ 1:A
        x[i] = rand( L )
        s[i] = rand( S )
    end
    return x
end

function computeme( X )
    Σ = 0.0
    for x ∈ X 
        Σ += x[5] 
    end
    return Σ
end

print( styled"{red:original}: " ); @btime computeme( X ) setup=(X = original())
print( styled"{green:alignmem}: " ); @btime computeme( X ) setup=(X = alignmem( original()))
```
</details>

* The above example is included as `example1.jl` in the `examples` folder.

---

## ⚠️ Critical Usage Note

> [!IMPORTANT]
> **Memory Ownership & Safety**
> 1. The first array in the aligned structure owns the memory.
> 2. **DO NOT RESIZE** aligned arrays (`push!`, `append!`) or the memory map will break.
> 3. If the parent structure is garbage collected, the pointers may become invalid. Keep it alive until the pointers are no longer needed!

---

## 🔌 Compatibility & Extensions

`AlignMemory` is further compatible with:
* 🔑 [`AxisKeys`](https://github.com/mcabbott/AxisKeys.jl)
* 📝 [`InlineStrings`](https://github.com/JuliaStrings/InlineStrings.jl)
* 🏷️ [`NamedDimsArrays`](https://github.com/invenia/NamedDims.jl) 
* 📏 [`OffsetArrays`](https://github.com/JuliaArrays/OffsetArrays.jl)

(Assumes these packages are loaded by the user)

---

## 📚 Related Packages

There are several other Julia packages that address memory layout and array storage, though with a different focus:

*   [RaggedArrays.jl](https://github.com/mbauman/RaggedArrays.jl): Provides contiguous memory storage specifically for arrays of arrays (jagged/ragged arrays).
*   [BlockArrays.jl](https://github.com/JuliaArrays/BlockArrays.jl): Focuses on partitioning arrays into blocks. The `BlockedArray` type stores the full array contiguously with a block structure overlaid.
*   [Strided.jl](https://github.com/Jutho/Strided.jl): Specialized for efficient strided array views and operations.
*   [UnsafeArrays.jl](https://github.com/JuliaArrays/UnsafeArrays.jl): Provides stack-allocated pointer-based array views.
*   [Buffers.jl](https://github.com/fkfest/Buffers.jl): Manages buffer allocation/deallocation for multidimensional arrays.

**AlignMemory.jl** differs by focusing specifically on physically aligning multiple independent arrays (which may be fields in a struct) into a single contiguous memory block to optimize cache usage, while using `unsafe_wrap` to present them as standard Julia arrays.
