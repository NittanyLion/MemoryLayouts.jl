# AI Agent Guide for MemoryLayouts.jl

## Purpose
This document provides guidance for AI agents assisting users with the MemoryLayouts.jl package. It contains essential information about the package's functionality, common use cases, potential pitfalls, and best practices.

## Package Overview

MemoryLayouts.jl is a Julia package that optimizes memory layout by ensuring that elements of collections (Arrays, Dicts, structs) are stored contiguously in memory. This reduces cache misses and improves performance, particularly for data structures with multiple array fields.

### Core Functions
- **`layout( x; exclude = [], alignment = 1 )`**: Aligns memory for immediate fields/elements of `x`. `alignment` specifies byte alignment (e.g., 64 for AVX-512).
- **`deeplayout( x; exclude = [], alignment = 1 )`**: Recursively aligns memory throughout the entire structure.

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
- The first array (offset 0) owns the malloc'd memory block
- Other arrays are views into this same block
- **If the first array is garbage collected, accessing other arrays becomes unsafe**

#### Resizing Dangers
- **Never resize aligned arrays** (no `push!`, `append!`, `resize!`, etc.)
- Resizing the first array invalidates all other array pointers
- Resizing other arrays breaks memory contiguity but doesn't crash
- If resizing is needed, users should use the `exclude` optional argument

## Common User Scenarios and Solutions

### Scenario 1: Basic Struct Alignment
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

### Scenario 2: Excluding Fields
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

### Scenario 3: Deep vs Shallow Alignment
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
   - Cause: Original struct was garbage collected
   - Solution: Keep reference to aligned struct alive
   
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
- **InlineStrings.jl**: Special handling for inline string types

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

### Safe Pattern:
```julia
function processaligneddata( originaldata )
    aligned = layout( originaldata )
    # Keep aligned alive for entire computation
    result = computewithaligned( aligned )
    return result
end
```

### Unsafe Pattern (AVOID):
```julia
function unsafeexample( data )
    aligned = layout( data )
    arr1 = aligned.array1  # Extracting reference
    arr2 = aligned.array2
    aligned = nothing      # DON'T DO THIS!
    # arr1 and arr2 now point to freed memory
end
```

## Debugging Assistance

Help users debug by checking:
1. **Data types**: Use `isbitstype( eltype( array ) )` to verify optimization applies
2. **Memory layout**: Use `pointer( array )` to verify contiguity
3. **Ownership**: First array should have `own=true` in unsafe_wrap
4. **Size calculations**: Use `computesize` and `computesizedeep` for verification

## Example Explanations

When users ask about specific features:

### "What's the difference between layout and deeplayout?"
- `layout`: Single-level alignment, like `copy`
- `deeplayout`: Recursive alignment, like `deepcopy`
- Use `layout` for simple structs, `deeplayout` for nested structures

### "Why did my program crash after alignment?"
Most likely cause: Original aligned structure was garbage collected
Solution: Keep a reference to the aligned structure alive

### "Can I modify aligned arrays?"
No, modifying (especially resizing) aligned arrays is unsafe and breaks guarantees
Alternative: Create new aligned structure after modifications

## Version Compatibility
- Requires Julia 1.6 or higher
- Compatible with standard array wrappers
- Extensions loaded conditionally based on package availability

## Additional Resources
- GitHub: https://github.com/NittanyLion/MemoryLayouts.jl
- Documentation: See docs/src/index.md for user documentation
- Tests: test/runtests.jl provides usage examples

## Final Notes for AI Agents
Remember that MemoryLayouts.jl is a specialized performance optimization tool. It's not always the right solution, and its benefits depend heavily on the specific use case. Always encourage users to profile and benchmark their specific scenarios before and after applying memory alignment.
