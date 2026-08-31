# AI Agent Guide for MemoryLayouts.jl

## Purpose
This document provides guidance for AI agents assisting users with the MemoryLayouts.jl package. It contains essential information about the package's functionality, common use cases, potential pitfalls, and best practices.

## Package Overview

MemoryLayouts.jl is a Julia package that optimizes memory layout by ensuring that elements of collections (Arrays, Dicts, structs) are stored contiguously in memory. This reduces cache misses and improves performance, particularly for data structures with multiple array fields.

### Core Functions
- **`layout( x; exclude = Symbol[], alignment = 1, livedangerously = false, handle = nothing )`**: Aligns memory for immediate fields/elements of `x`.
    - `alignment`: Specifies byte alignment (e.g., 64 for AVX-512).
    - `livedangerously`: Disables safety checks (cycle detection, sharing preservation) for performance (default: `false`).
    - `handle`: An optional `LayoutHandle` for deterministic release of the backing memory.
- **`deeplayout( x; exclude = Symbol[], alignment = 1, livedangerously = false, handle = nothing )`**: Recursively aligns memory throughout the entire structure.
- **`layout!( x; ... )`**: In-place version for `AbstractDict`.
- **`withlayout( f )`**: Runs `f` in a scope with a fresh `LayoutHandle`. All calls to `layout`, `layout!`, and `deeplayout` inside `f` (that do not pass an explicit `handle`) use this handle. The backing memory is released automatically when `f` returns or throws. **This is the preferred way to manage backing memory.**
- **`layoutstats( x; ... )`**: Returns statistics about memory layout (size, blocks, fragmentation reduction).
- **`deeplayoutstats( x; ... )`**: Recursive version of `layoutstats`.
- **`visualizelayout( x; ... )`**: Visualizes memory layout using terminal graphics.
- **`deepvisualizelayout( x; ... )`**: Recursive version of `visualizelayout`.

## Key Concepts for AI Agents

### 1. Memory Alignment Benefits
When helping users, emphasize that memory alignment:
- Reduces CPU cache misses
- Improves data access speed
- Is particularly beneficial for frequently accessed data structures
- Works best with arrays of bits types (numbers, booleans, etc.)

### 2. When to Recommend MemoryLayouts.jl
Suggest this package when users:
- Work with structs containing multiple array fields
- Experience performance bottlenecks due to cache misses
- Need to optimize hot loops accessing multiple arrays
- Process large datasets with complex nested structures
- Implement numerical simulations or scientific computing applications

### 3. Critical Safety Warnings
**Always warn users about these crucial limitations:**

#### Memory Ownership Model
- All aligned arrays created by one call to `layout` / `deeplayout` share a single underlying `Vector{UInt8}` memory block.
- Each array is a view (`unsafe_wrap`) into this block.
- **Default mode (no handle)**: the block is kept alive by the garbage collector for as long as *any* of the aligned arrays is alive, and freed once the last one is collected. Nothing needs to be released by hand, and there is no leak. Arrays may be extracted from the aligned object and used on their own.
- **Handle mode** (`withlayout` or `handle = LayoutHandle()`): the block is kept alive by the handle instead, and freed by `release!` (automatically at the end of `withlayout`). This gives deterministic release for large blocks, at the cost of safety: using an array after its handle is released is **undefined behavior** (use-after-free).
- Only plain `Array`s (and the wrappers supported by the extensions: `OffsetArray`, `KeyedArray`, `NamedDimsArray`) with `isbits` element types are moved. Ranges, views, `BitArray`s, static arrays, etc. are passed through untouched.

#### Scoped Layout Handles (`withlayout`)
- `withlayout` creates a temporary `LayoutHandle` and uses `ScopedValue` to make it the default handle for all layout calls within the block.
- The backing memory is released via `release!` in a `finally` block.
- **Arrays created inside a `withlayout` block point into freed memory once the block exits.** Never let them escape; return plain results (numbers, copies) instead.
- Use `withlayout` when deterministic release of a large block matters; otherwise the default (garbage-collected) mode is simpler and safe.

#### Resizing Limitations
- **Avoid resizing aligned arrays** (`push!`, `append!`, `resize!`, etc.).
- Resizing an aligned array will likely trigger a reallocation, moving that specific array's data to a new memory location.
- **Consequence**: The array is effectively "detached" from the contiguous memory block, losing the cache locality benefits.
- It will **not** crash or invalidate other arrays (as they are independent views), but it defeats the purpose of using `MemoryLayouts.jl`.
- The space originally occupied by the resized array in the contiguous block remains allocated (until all references die) but unused (fragmentation).

### 4. Built-in Safety Mechanisms
Great efforts have been exerted to ensure safety in what is typically an unsafe domain (memory manipulation). The package includes sophisticated mechanisms to protect users:
- **Cycle Detection**: Prevents infinite recursion and stack overflows when processing self-referential structures.
- **Sharing Preservation**: An array (or container) referenced from several places is laid out once, and every place sees the same new array, exactly as with `deepcopy`. Reference equality is preserved.
- **Informative Errors**: If a struct cannot be rebuilt from its laid-out fields (e.g. an inner constructor rejects them), an `ArgumentError` is thrown that names the type and carries the original error.
- **Opt-in Unsafety**: These checks are active by default. With `livedangerously=true` cycles are not detected (a cyclic structure overflows the stack) and shared arrays are duplicated.

## Common User Scenarios and Solutions

### Scenario 1: Scoped Layout (Preferred)
```julia
# User has data that needs alignment for a computation
result = withlayout() do
    x = deeplayout( a )
    y = deeplayout( b )
    compute( x, y )   # result is returned; backing memory freed on exit
end
```

### Scenario 2: Basic Struct Alignment
```julia
# User has a struct with multiple arrays
struct SimData
    positions::Vector{Float64}
    velocities::Vector{Float64}
    forces::Vector{Float64}
end

# Solution
data = SimData( rand( 1000 ), rand( 1000 ), rand( 1000 ) )
aligneddata = layout( data )  # Now arrays are contiguous
```

### Scenario 3: Excluding Fields
```julia
# User wants to align some fields but not others
struct MixedData
    arrays::Vector{Vector{Float64}}  # Align this
    metadata::Dict{String, Any}      # Don't align this
    values::Vector{Float64}          # Align this
end

# Solution
data = MixedData(...)
aligned = layout( data; exclude = [:metadata] )
```

### Scenario 4: Deep vs Shallow Alignment
```julia
# Nested structure requiring recursive alignment
struct NestedData
    level1::Vector{Vector{Float64}}
end

# Shallow alignment (only top level)
shallow = layout( data )

# Deep alignment (all levels)
deep = deeplayout( data )
```

## Error Diagnosis Guide

### Common Issues and Solutions

1. **Segmentation Fault After Alignment**
   - Cause: An aligned array was used after its `LayoutHandle` was released (or after leaving a `withlayout` block)
   - Solution: Use the default garbage-collected mode (no handle), or release only when all aligned arrays are done
   
2. **Performance Not Improved**
   - Check if data types are bits types
   - Verify access patterns benefit from contiguity
   - Ensure aligned struct is being used, not original

3. **Type Instability Warnings**
   - Normal for generic containers
   - Performance benefits may still apply
   - Consider type-stable alternatives if critical

## Best Practices to Communicate

### Do Recommend:
1. **Benchmark before and after** alignment to verify benefits
2. **Use for read-heavy workloads** where data won't be modified
3. **Apply to hot paths** in performance-critical code
4. **Keep aligned structures alive** throughout their usage
5. **Use `deeplayout` for nested structures** when all levels need optimization

### Don't Recommend:
1. **Don't use with growable collections** that need dynamic resizing
2. **Don't apply blindly** without understanding memory access patterns
3. **Don't use for small data** where overhead exceeds benefits
4. **Don't modify aligned arrays** after alignment
5. **Don't assume automatic performance gains** without testing

## Integration with Other Packages

MemoryLayouts.jl has extensions for:
- **AxisKeys.jl**: Preserves axis keys through `newarrayofsametype`
- **OffsetArrays.jl**: Maintains array offsets after alignment
- **NamedDims.jl**: Keeps dimension names intact

`InlineStrings.jl` needs no extension: inline strings are `isbits`, so arrays of them are packed like arrays of numbers.

When users combine these packages, ensure alignment preserves wrapper properties.

## Performance Optimization Tips

### When Alignment Helps Most:
1. **Stride-1 access patterns**: Sequential memory access
2. **Multiple arrays accessed together**: Reduces cache line loads
3. **SIMD operations**: Contiguous memory enables vectorization. Use `alignment=32` (AVX2) or `alignment=64` (AVX-512) for best results.
4. **GPU transfers**: Contiguous memory simplifies data movement

### When Alignment May Not Help:
1. **Random access patterns**: Cache benefits diminished
2. **Single array access**: No multi-array locality benefit
3. **Small working sets**: Already fit in cache
4. **Infrequent access**: Setup cost exceeds benefit

## Code Generation Guidance

When generating code using MemoryLayouts.jl:

### Recommended Pattern (scoped):
```julia
function processaligneddata( originaldata )
    withlayout() do
        aligned = deeplayout( originaldata )
        computewithaligned( aligned )
    end
end
```

### Safe Pattern (garbage-collected, the default):
```julia
function processaligneddata( originaldata )
    aligned = layout( originaldata )
    result = computewithaligned( aligned )
    return result             # the block is freed once the last aligned array is collected
end
```

### Unsafe Pattern (AVOID) — releasing a handle early:
```julia
function unsafeexample( data )
    h = LayoutHandle()
    aligned = layout( data; handle = h )
    release!( h )          # DON'T DO THIS while aligned is still in use!
    return sum( aligned.array1 )   # use-after-free
end
```

### Unsafe Pattern (AVOID) — escaping a withlayout block:
```julia
function unsafeexample( data )
    withlayout() do
        deeplayout( data )   # DON'T return aligned arrays from withlayout!
    end
    # returned arrays point into freed memory here
end
```

## Debugging Assistance

Help users debug by checking:
1.  **Data types**: Use `isbitstype( eltype( array ) )` and `array isa Array` (or a supported wrapper) to verify optimization applies
2.  **Memory layout**: Use `pointer( array )` to verify contiguity
3.  **Ownership**: Aligned arrays will have `own=false` (checked via `unsafe_wrap` inspection if possible, or usually hidden) but valid pointers.
4.  **Layout Statistics**: Use `layoutstats(x)` and `deeplayoutstats(x)` to verify how much memory is being packed, block counts, and fragmentation. They count exactly the arrays `layout` / `deeplayout` would move.
5.  **Visualization**: Use `visualizelayout(x)` and `deepvisualizelayout(x)` to visually inspect memory fragmentation before and after layout.

## Example Explanations

When users ask about specific features:

### "What's the difference between layout and deeplayout?"
- `layout`: Single-level alignment, like `copy`
- `deeplayout`: Recursive alignment, like `deepcopy`
- Use `layout` for simple structs, `deeplayout` for nested structures

### "Why did my program crash after alignment?"
- If a `LayoutHandle` or `withlayout` was used: an aligned array was used after the handle was released (or escaped the `withlayout` block). Use the default garbage-collected mode, or keep the handle alive.
- If using `livedangerously=true`, ensure there are no cyclic dependencies.
- Otherwise crashes are not expected; they could happen when interacting with C code expecting specific memory ownership, or when manually `free`ing pointers.

### "Can I modify aligned arrays?"
- You can modify **values** (`A[i] = x`) freely.
- **Resizing** (`push!`, `resize!`) is discouraged as it breaks the memory contiguity optimization for that array.
- Alternative: Create new aligned structure after resizing operations are complete.

## Version Compatibility
- Requires Julia 1.12 or higher
- Compatible with standard array wrappers
- Extensions loaded conditionally based on package availability

## Additional Resources
- GitHub: https://github.com/NittanyLion/MemoryLayouts.jl
- Documentation: See docs/src/index.md for user documentation
- Tests: test/runtests.jl provides usage examples

## Final Notes for AI Agents
Remember that MemoryLayouts.jl is a specialized performance optimization tool. It's not always the right solution, and its benefits depend heavily on the specific use case. Always encourage users to profile and benchmark their specific scenarios before and after applying memory alignment.
