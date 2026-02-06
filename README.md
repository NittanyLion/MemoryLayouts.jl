<div align="center">

# MemoryLayouts.jl 🧠⚡

**Optimize your memory layout for maximum cache efficiency.**

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://NittanyLion.github.io/MemoryLayouts.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://NittanyLion.github.io/MemoryLayouts.jl/dev/)
[![Build Status](https://github.com/NittanyLion/MemoryLayouts.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/NittanyLion/MemoryLayouts.jl/actions/workflows/CI.yml?query=branch%3Amain)

</div>

---

## 🚀 The Problem vs. The Solution

Standard collections in Julia (`Dicts`, `Arrays` of `Arrays`, `structs`) often scatter data across memory, causing frequent **cache misses**. `MemoryLayouts.jl` packs this data into contiguous blocks.

The advantage of contiguity is that it reduces cache misses and should be expected to improve performance.

### 🔮 How it works

| Function | Description | Analogy |
| :--- | :--- | :--- |
| **`layout( x )`** | Aligns immediate fields of `x` | Like `copy( x )` but packed |
| **`deeplayout( x )`** | Recursively aligns nested structures | Like `deepcopy( x )` but packed |
| **`layoutstats( x )`** | Dry run statistics for `layout( x )` | |
| **`deeplayoutstats( x )`** | Dry run statistics for `deeplayout( x )` | |

### 🚀 SIMD Optimization

Both functions accept an optional `alignment` keyword argument (default `1`).
This allows aligning data to specific byte boundaries (e.g., 32 or 64 bytes), which is relevant for maximizing performance with **SIMD** instructions (AVX2, AVX-512).

```julia
aligneddata = layout( data; alignment = 64 )
```

---

## ⚡ Performance Example

In scientific computing, memory locality is everything.

> **Benchmark Result:**
> `original`: 159.177 μs
> `layout`: **111.251 μs** (🚀 43% Faster)

<details>
<summary><b>Click to see the benchmark code</b></summary>

```julia
using MemoryLayouts, BenchmarkTools, StyledStrings

function original( A = 10_000, L = 100, S = 5000)
    x = Vector{Vector{Float64}}( undef, A )
    s = Vector{Vector{Float64}}( undef, A )
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
print( styled"{green:layout}: " ); @btime computeme( X ) setup=(X = layout( original()))
```
</details>

* The above example is included as `example1.jl` in the `examples` folder.

---

## 📊 Dry Run / Statistics

You can inspect the potential improvements in memory contiguity without performing the actual allocation using `layoutstats` and `deeplayoutstats`.

```julia
julia> using MemoryLayouts

julia> data = [rand(10) for _ in 1:5];

julia> layoutstats(data)
LayoutStats(packed=400, blocks=5, span=2304, reduction=1904 (82.6%))
```

The output indicates:
- **packed**: The total size (in bytes) of the data if packed.
- **blocks**: The number of individual arrays identified.
- **span**: The current distance between the minimum and maximum memory addresses of the data.
- **reduction**: The potential reduction in memory span.

---

## ⚠️ Usage Notes

> [!IMPORTANT]
> 1. Use the statistics to evaluate whether packing is worth it.
> 2. There are some issues to pay attention to: please read the documentation carefully.
> 3. This is the first version of this package: comments are welcome.

---

## 🔌 Compatibility & Extensions

`MemoryLayouts` is further compatible with:
* 🔑 [`AxisKeys`](https://github.com/mcabbott/AxisKeys.jl)
* 📝 [`InlineStrings`](https://github.com/JuliaStrings/InlineStrings.jl)
* 🏷️ [`NamedDims.jl`](https://github.com/invenia/NamedDims.jl) 
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

**MemoryLayouts.jl** differs by focusing specifically on physically aligning multiple independent arrays (which may be fields in a struct) into a single contiguous memory block to optimize cache usage, while using `unsafe_wrap` to present them as standard Julia arrays.
