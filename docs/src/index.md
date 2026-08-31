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
| **`layout( x )`** | Aligns immediate fields of `x` | Like `copy( x )` but packed |
| **`deeplayout( x )`** | Recursively aligns nested structures | Like `deepcopy( x )` but packed |
| **`layout!( x )`** | In-place alignment (e.g. for Dicts) | Like `layout( x )` but in-place |
| **`withlayout( f )`** | Runs `f` with a scoped layout handle | Automatic memory management |
| **`layoutstats( x )`** | Dry run statistics for `layout( x )` | |
| **`deeplayoutstats( x )`** | Dry run statistics for `deeplayout( x )` | |
| **`visualizelayout( x )`** | Visualizes memory layout using terminal graphics | |
| **`deepvisualizelayout( x )`** | Recursively visualizes memory layout | |

## 🛠️ Usage

The package provides the exported functions `layout`, `deeplayout`, `layout!`, `withlayout`, `layoutstats`, `deeplayoutstats`, `visualizelayout` and `deepvisualizelayout`. The distinction between `layout` and `deeplayout` is that `layout` only applies to top level objects, whereas `deeplayout` applies to objects at all levels. The two examples below demonstrate their use.  As for the `stats` functions, these just do a dry run and print out some statistics on the degree of contiguity improvement a user can expect to see. The `visualize` functions provide a graphical representation of the memory layout in the terminal.

### 💡 Example for `layout`

The example below demonstrates how to use `layout`.

```@example
using MemoryLayouts, BenchmarkTools, StyledStrings

function original( A = 10_000, L = 100, S = 5000 )
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

print( styled"{(fg=0xff9999):original}: " ); @btime computeme( X ) setup=( X = original(); );
print( styled"{(fg=0x99ff99):layout}: " ); @btime computeme( X ) setup=( X = layout( original() ); );
;
```

### 💡 Example for `deeplayout`

The example below illustrates the use of `deeplayout`.

```@example
using MemoryLayouts, BenchmarkTools, StyledStrings


struct 𝒮{X,Y,Z}
    x :: X
    y :: Y 
    z :: Z
end


function original( A = 10_000, L = 100, S = 5000 )
    x = Vector{Vector{Float64}}( undef, A )
    s = Vector{Vector{Float64}}( undef, A )
    for i ∈ 1:A
        x[i] = rand( L )
        s[i] = rand( S )
    end
    return 𝒮( [ x[i] for i ∈ 1:div( A, 3 ) ], [ x[i] for i ∈ div( A, 3 )+1:div( 2*A, 3 ) ], [ x[i] for i ∈ div( 2*A, 3 )+1:A ] )
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

println( layoutstats( original() ) )
visualizelayout( original() )


println( deeplayoutstats( original() ) )
deepvisualizelayout( original() )


print( styled"{(fg=0xff9999):original}: " ); @btime computeme( X ) setup=( X = original(); );
print( styled"{(fg=0x99ff99):layout}: " ); @btime computeme( X ) setup=( X = layout( original() ); );
print( styled"{(fg=0x9999ff):deeplayout}: " ); @btime computeme( X ) setup=( X = deeplayout( original() ); );
;
```

## 📊 Dry Run / Statistics

You can inspect the potential improvements in memory contiguity without performing the actual allocation using `layoutstats` and `deeplayoutstats` or visually by using `visualizelayout` and `deepvisualizelayout`.

```@example
using MemoryLayouts

data = [ rand( 10 ) for _ in 1:5 ];

layoutstats( data )

visualizelayout( data )
```

The output indicates:
- **packed**: The total size (in bytes) of the data if packed.
- **blocks**: The number of individual arrays identified.
- **span**: The current distance between the minimum and maximum memory addresses of the data.
- **reduction**: The potential reduction in memory span.

## 🤝 Compatibility


* `MemoryLayouts.jl` is compatible with 
  - [`AxisKeys`](https://github.com/mcabbott/AxisKeys.jl)
  - [`NamedDims.jl`](https://github.com/invenia/NamedDims.jl) 
  - [`OffsetArrays`](https://github.com/JuliaArrays/OffsetArrays.jl)
* this assumes that those packages are loaded by the user (weak dependences)
* arrays of [`InlineStrings`](https://github.com/JuliaStrings/InlineStrings.jl) are `isbits` and are packed like arrays of numbers; no extension is needed
* other array types (ranges, views, `BitArray`s, static arrays, ...) are passed through untouched; support for a new wrapper type can be added by defining `MemoryLayouts.transferable` and `MemoryLayouts.newarrayofsametype` for it





## ⚡ SIMD Alignment

Both `layout` and `deeplayout` accept an optional `alignment` keyword argument (default `1`). This allows you to specify the byte alignment for the start of each array in the contiguous memory block.

Proper memory alignment is relevant for maximizing performance with SIMD (Single Instruction, Multiple Data) instructions (e.g., AVX2, AVX-512). On the other hand, such alignment leaves gaps between blocks of memory that are not a multiple of 64 bytes in length.

*   **AVX2** typically requires 32-byte alignment.
*   **AVX-512** typically requires 64-byte alignment.

### 💡 Example

```julia
using MemoryLayouts
struct MyData
    a::Vector{Float64}
    b::Vector{Float64}
end

data = MyData( rand( 100 ), rand( 100 ) )

aligneddata = layout( data; alignment = 64 )

pointer( aligneddata.a ) # Will be a multiple of 64
pointer( aligneddata.b ) # Will be a multiple of 64
```

## 🔒 Memory Management

All arrays produced by one call to `layout` or `deeplayout` are views into a single contiguous block.  Who keeps that block alive depends on how the call was made.

### Default: garbage collected

Without a handle, the block is kept alive by the garbage collector for as long as *any* array pointing into it is alive, and freed once the last one is collected.  Nothing needs to be released by hand, arrays may be extracted from the laid-out object and used on their own, and there is no leak.

```julia
aligned = layout( data )
a = aligned.a          # fine to keep around; the block lives as long as `a` does
```

### Deterministic: `withlayout` and `LayoutHandle`

When a block is large and you want it freed at a known point rather than at the garbage collector's discretion, use `withlayout`.  All calls to `layout`, `layout!`, and `deeplayout` inside the block (that do not pass an explicit `handle`) use a temporary `LayoutHandle` that is released when the block exits (or throws):

```julia
result = withlayout() do
    x = deeplayout( a )
    y = deeplayout( b )
    compute( x, y )
end
```

An explicit handle does the same by hand:

```julia
h = LayoutHandle()
x = deeplayout( a; handle = h )
compute( x )
release!( h )
```

!!! warning
    Arrays created with a handle point into **freed memory** once the handle is released (for `withlayout`: once the block exits).  Using such an array afterwards is undefined behavior: it may return garbage or crash the process.  Do not let them escape; return plain results (numbers, copies) instead.

## 🏈️ Performance Mode (Live Dangerously)

By default, `MemoryLayouts` performs checks to ensure robustness:
1.  **Cycle Detection**: Prevents `StackOverflowError` if your data structure has cycles (e.g. A -> B -> A); an `ArgumentError` is thrown instead.
2.  **Sharing Preservation**: An array (or container) referenced from several places is laid out once, and every place sees the same new array, exactly as with `deepcopy`.

If you are confident your data is acyclic and you don't care about shared references (they will be duplicated), you can disable these checks for a small performance boost by setting `livedangerously = true`.

```julia
# Faster, but crashes on cycles!
fast_result = deeplayout( huge_tree; livedangerously = true )
```

## ⚠️ Things to be mindful of

!!! warning "Important details"
    - it operates on various types of collections including `structs`, `arrays`, and `dicts`
        * *operating on* means that these collections are traversed, possibly recursively
    - the only objects that are copied into contiguous memory are plain `Array`s (plus the wrappers supported by the extensions) with `isbits` element types (think arrays of numbers, InlineStrings (but **not** regular strings), etcetera ); ranges, views, `BitArray`s and other array types are passed through untouched
    - the more scattered is the memory before the layout change, the greater is the potential speed gain
    - `layout` copies, but only the top level; see example 2 above
        * `deeplayout` copies all levels
        * no attempt is made to make empty arrays contiguous
        * no attempt is made to make objects that are not one of the covered collections contiguous
        * the package assigns one memory block and within that block uses `unsafe_wraps` to obtain Julia arrays
            - this *can* have 'interesting' consequences if misused
            - ergo, this package should not be used by those new to programming 
        * objects can be excluded from layout changes via the `exclude` keyword; a name in `exclude` matches a field or dictionary key of that name at **any** depth
        * `layout` shares excluded values with the original; `deeplayout` deep-copies them
    - there is overhead in laying out memory initially
    - thus, `MemoryLayouts` works best for aligning memory in a collection once and then using it for an extended stretch
    - resizing one of the arrays whose memory was laid out by `MemoryLayouts` is safe, but likely results in that array being moved to another location in memory **assigned by Julia** (not by `MemoryLayouts`)
    - reassigning an array assigned by `MemoryLayouts` to another location, e.g. by writing `y[i] = ...` does not release the entire memory block
    - without a handle, the entire memory block is only released once every array pointing into it has been garbage collected; with a handle, it is released by `release!` (see above)
    - by default, `MemoryLayouts` packs in the isbits arrays as tightly as it can
        * this may not be optimal, e.g. for AVX-512 computations
        * use the `alignment=64` option to give up some contiguity and regain alignment desired for optimal AVX-512 performance
    - the code has a number of safety checks and features:
        * it throws an error on detecting cyclic content (a depends on b depends on a) 
        * it preserves sharing (an array referenced twice is moved once)
        * it throws an informative error if a struct cannot be rebuilt from its laid-out fields
        * alignment used is the maximum of user-specified alignment and machine-required alignment for the type
    - the code makes an attempt to skip types that are not suitable for aligning, but it may not always succeed; use `exclude` to exclude such fields
    - also exclude fields with low-level objects like pointers

## 🔇 Suppressing the Banner

The startup banner is only shown in interactive sessions.  You can suppress it there too by setting the environment variable `MEMORYLAYOUTS` to `"false"` or `"no"`; `MemoryLayouts.banner()` prints it on demand.

```bash
export MEMORYLAYOUTS="false"
```

## 📖 Function documentation

```@docs
layout
deeplayout
layout!
withlayout
LayoutHandle
release!
release_all!
layoutstats
deeplayoutstats
visualizelayout
deepvisualizelayout
MemoryLayouts.transferable
MemoryLayouts.newarrayofsametype
MemoryLayouts.banner
```




