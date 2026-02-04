```@meta
CurrentModule = AlignMemory
```

# AlignMemory.jl 🧠⚡

**Optimize your memory layout for maximum cache efficiency.**

Documentation for [AlignMemory](https://github.com/NittanyLion/AlignMemory.jl).

## 🚀 The Problem vs. The Solution

Standard collections in Julia (`Dict`s, `Array`s of `Array`s, `struct`s) often scatter data across memory, causing frequent **cache misses**. `AlignMemory.jl` packs this data into contiguous blocks.

### 🔮 How it works

| Function | Description | Analogy |
| :--- | :--- | :--- |
| **`alignmem(x)`** | Aligns immediate fields of `x` | Like `copy(x)` but packed |
| **`deepalignmem(x)`** | Recursively aligns nested structures | Like `deepcopy(x)` but packed |

## Usage

The package provides two exported functions: `alignmem` and `deepalignmem`. The distinction is that `alignmem` only applies to top level objects, whereas `deepalignmem` applies to objects at all levels. The two examples below demonstrate their use.

### Example for `alignmem`

The example below demonstrates how to use `alignmem`.

```@example
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

print( styled"{(fg=0xff9999):original}: " ); @btime computeme( X ) setup=(X = original();)
print( styled"{(fg=0x99ff99):alignmem}: " ); @btime computeme( X ) setup=(X = alignmem( original());)
;
```

### Example for `deepalignmem`

The example below illustrates the use of `deepalignmem`.

```@example
using AlignMemory, BenchmarkTools, StyledStrings


struct 𝒮{X,Y,Z}
    x :: X
    y :: Y 
    z :: Z
end


function original( A = 10_000, L = 100, S = 5000)
    x = Vector{Vector{Float64}}(undef, A)
    s = Vector{Vector{Float64}}(undef, A)
    for i ∈ 1:A
        x[i] = rand( L )
        s[i] = rand( S )
    end
    return 𝒮( [x[i] for i ∈ 1:div(A,3)], [ x[i] for i ∈ div(A,3)+1:div(2*A,3)], [x[i] for i ∈ div(2*A,3)+1:A ] )
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
print( styled"{(fg=0x99ff99):alignmem}: " ); @btime computeme( X ) setup=(X = alignmem( original());)
print( styled"{(fg=0x9999ff):deepalignmem}: " ); @btime computeme( X ) setup=(X = deepalignmem( original());)
;
```

## 🔌 Compatibility & Extensions

* `AlignMemory.jl` is further compatible with 
  - [`AxisKeys`](https://github.com/mcabbott/AxisKeys.jl)
  - [`InlineStrings`](https://github.com/JuliaStrings/InlineStrings.jl)
  - [`NamedDimsArrays`](https://github.com/invenia/NamedDims.jl) 
  - [`OffsetArrays`](https://github.com/JuliaArrays/OffsetArrays.jl)
* this assumes that those packages are loaded by the user

## Function documentation

```@docs
alignmem
deepalignmem
```



## ⚠️ Critical Usage Note

!!! warning "Memory Ownership & Safety"
    1. The first array in the aligned structure owns the memory.
    2. **DO NOT RESIZE** aligned arrays (`push!`, `append!`) or the memory map will break.
    3. If the parent structure is garbage collected, the pointers may become invalid. Keep it alive!
    4. Any arrays that you may wish to reassign or resize at a later point in time should be specified in the optional `exclude` argument.
    
    *Implementation Note:* The code allocates a single chunk of memory via `malloc`. This memory will be owned by the *first array* of the ones that are to be aligned. When that array is garbage-collected, the remaining aligned arrays will no longer be accessible.

