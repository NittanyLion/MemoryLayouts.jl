```@meta
CurrentModule = AlignMemory
```

# AlignMemory.jl

Documentation for [AlignMemory](https://github.com/NittanyLion/AlignMemory.jl).

## Purpose

The purpose of the `AlignMemory.jl` package is to make arrays contained in collections like `structs`, `arrays`, and `dicts` occupy contiguous memory space automatically.  The reason that this can be advantageous is that using contiguous memory for related objects can improve performance. 

## Usage

The package provides two exported functions: `alignmem` and `deepalignmem`.  The distinction is that `alignmem` only applies to top level objects, whereas `deepalignmem` applies to objects at all levels. The two examples below demonstrate their use.

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

## Function documentation

```@docs
alignmem
deepalignmem
```



## Caveats

!!! warning "implementation details to be mindful of"
    - avoid resizing or reassigning arrays that are realigned
    - any arrays that you may wish to reassign or resize at a later point in time should be specified in the optional `exclude` argument
    - what the code does:
        * the code allocates a single chunk of memory via malloc * this memory will be owned by the first array of the ones that are to be aligned
        * so when that that array is garbage-collected, the remaining aligned arrays will no longer be accessible
    - this is version 0.1 of this package, so there may still be some issues

