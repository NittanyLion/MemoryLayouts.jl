```@meta
CurrentModule = MemoryLayouts
```

# MemoryLayouts.jl 🧠⚡

**Optimize your memory layout for maximum cache efficiency.**

Documentation for [MemoryLayouts](https://github.com/NittanyLion/MemoryLayouts.jl).

## 🚀 The Problem vs. The Solution

Standard collections in Julia (`Dicts`, `Arrays` of `Arrays`, `structs`) often scatter data across memory, causing frequent **cache misses**. `MemoryLayouts.jl` packs this data into contiguous blocks.

### 🔮 How it works

| Function | Description | Analogy |
| :--- | :--- | :--- |
| **`layoutmem( x )`** | Aligns immediate fields of `x` | Like `copy( x )` but packed |
| **`deeplayoutmem( x )`** | Recursively aligns nested structures | Like `deepcopy( x )` but packed |

## Usage

The package provides two exported functions: `layoutmem` and `deeplayoutmem`. The distinction is that `layoutmem` only applies to top level objects, whereas `deeplayoutmem` applies to objects at all levels. The two examples below demonstrate their use.

## SIMD Alignment

Both `layoutmem` and `deeplayoutmem` accept an optional `alignment` keyword argument (default `1`). This allows you to specify the byte alignment for the start of each array in the contiguous memory block.

Proper memory alignment is crucial for maximizing performance with SIMD (Single Instruction, Multiple Data) instructions (e.g., AVX2, AVX-512).

*   **AVX2** typically requires 32-byte alignment.
*   **AVX-512** typically requires 64-byte alignment.

### Example

```julia
using MemoryLayouts
struct MyData
    a::Vector{Float64}
    b::Vector{Float64}
end

data = MyData( rand( 100 ), rand( 100 ) )

# Align for AVX-512 (64-byte alignment)
aligneddata = layoutmem( data; alignment = 64 )

# Verify alignment
pointer( aligneddata.a ) # Will be a multiple of 64
pointer( aligneddata.b ) # Will be a multiple of 64
```

### Example for `layoutmem`

The example below demonstrates how to use `layoutmem`.

```@example
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

print( styled"{(fg=0xff9999):original}: " ); @btime computeme( X ) setup=(X = original();)
print( styled"{(fg=0x99ff99):layoutmem}: " ); @btime computeme( X ) setup=(X = layoutmem( original());)
;
```

### Example for `deeplayoutmem`

The example below illustrates the use of `deeplayoutmem`.

```@example
using MemoryLayouts, BenchmarkTools, StyledStrings


struct 𝒮{X,Y,Z}
    x :: X
    y :: Y 
    z :: Z
end


function original( A = 10_000, L = 100, S = 5000)
    x = Vector{Vector{Float64}}( undef, A )
    s = Vector{Vector{Float64}}( undef, A )
    for i ∈ 1:A
        x[i] = rand( L )
        s[i] = rand( S )
    end
    return 𝒮( [x[i] for i ∈ 1:div( A, 3 )], [ x[i] for i ∈ div( A, 3 )+1:div( 2*A, 3 )], [x[i] for i ∈ div( 2*A, 3 )+1:A ] )
end

function computeme( X )
    Σ = 0.0
    for x ∈ X.x  
        Σ += x[5] 
    end
    for y ∈ X.y 
        Σ += y[37]
    end
    for z ∈ X.z 
        Σ += z[5] 
    end
    return Σ
end

print( styled"{(fg=0xff9999):original}: " ); @btime computeme( X ) setup=(X = original();)
print( styled"{(fg=0x99ff99):layoutmem}: " ); @btime computeme( X ) setup=(X = layoutmem( original());)
print( styled"{(fg=0x9999ff):deeplayoutmem}: " ); @btime computeme( X ) setup=(X = deeplayoutmem( original());)
;
```

## 🔌 Compatibility & Extensions

* `MemoryLayouts.jl` is further compatible with 
  - [`AxisKeys`](https://github.com/mcabbott/AxisKeys.jl)
  - [`InlineStrings`](https://github.com/JuliaStrings/InlineStrings.jl)
  - [`NamedDimsArrays`](https://github.com/invenia/NamedDims.jl) 
  - [`OffsetArrays`](https://github.com/JuliaArrays/OffsetArrays.jl)
* this assumes that those packages are loaded by the user

## Function documentation

```@docs
layoutmem
deeplayoutmem
```




