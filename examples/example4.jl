using MemoryLayouts, BenchmarkTools, StyledStrings, LoopVectorization

# Example 4: Object Layout vs. Aligned Memory
# This example compares the performance of processing "standard" Julia objects (mutable structs)
# which are heap-allocated and often misaligned (as shown in the conversation earlier)
# versus densely packed, aligned arrays (Structure of Arrays).

# ------------------------------------------------------------------
# 1. The "Misaligned Object" Approach (AoS / Heap Objects)
# ------------------------------------------------------------------

# Standard mutable struct, allocated on the heap.
# As seen previously, these are typically 16-byte or 32-byte aligned, 
# but rarely 64-byte aligned, and are scattered in memory.
mutable struct HeapObject
    a :: Float64
    b :: Float64
    c :: Float64
    d :: Float64
    result :: Float64
end

struct ObjectComputation
    objects :: Vector{HeapObject}
end

function create_objects( N = 1_000_000 )
    # Create a vector of individual heap objects
    # This creates N separate allocations, scattered in memory
    objects = Vector{HeapObject}(undef, N)
    for i in 1:N
        objects[i] = HeapObject(rand(), rand(), rand(), rand(), 0.0)
    end
    return ObjectComputation(objects)
end

function compute_objects!( s :: ObjectComputation )
    objects = s.objects
    
    # Iterate over the vector of pointers, then dereference each object
    @inbounds for i ∈ eachindex( objects )
        obj = objects[i]
        # Computation logic identical to example3
        temp1 = obj.a * obj.b + obj.c
        temp2 = obj.d * obj.a - obj.b
        obj.result = temp1 * temp2 + sqrt( abs( obj.c * obj.d ) )
    end
    
    # Sum results to ensure work isn't optimized away
    total = 0.0
    @inbounds for obj in objects
        total += obj.result
    end
    return total
end

# ------------------------------------------------------------------
# 2. The "Aligned SoA" Approach (example3 style)
# ------------------------------------------------------------------

struct StridedComputation
    a :: Vector{Float64}
    b :: Vector{Float64}
    c :: Vector{Float64}
    d :: Vector{Float64}
    result :: Vector{Float64}
end

function create_aligned_soa( N = 1_000_000 )
    # Create properly sized and aligned arrays (Structure of Arrays)
    return StridedComputation(
        rand( N ),
        rand( N ),
        rand( N ),
        rand( N ),
        zeros( N )
    )
end

function compute_simd_soa!( s :: StridedComputation )
    a = s.a
    b = s.b
    c = s.c
    d = s.d
    result = s.result
    
    # This loop vectorizes efficiently with aligned memory
    @tturbo for i ∈ eachindex( result )
        temp1 = a[i] * b[i] + c[i]
        temp2 = d[i] * a[i] - b[i]
        result[i] = temp1 * temp2 + sqrt( abs( c[i] * d[i] ) )
    end
    
    return sum( result )
end

# ------------------------------------------------------------------
# Benchmarks
# ------------------------------------------------------------------

println( styled"{bold:Object vs. Aligned Array Performance Demonstration}" )
println( styled"{dim:═══════════════════════════════════════════════════}\n" )

# Setup
N = 100_000 # Use smaller N for objects to keep benchmark reasonable if it's very slow

println( styled"{yellow:1. Heap-Allocated Objects (Misaligned/Scattered):}" )
println( styled"{dim:   Vector of MutableStruct - Array of pointers to heap objects}" )
println( styled"{dim:   Suffers from pointer indirection and cache misses}" )
print( styled"{red:objects (scalar)}: " )
@btime compute_objects!( s ) setup=( s = create_objects($N) )

println( styled"\n{yellow:2. Aligned Structure of Arrays (Contiguous):}" )
println( styled"{dim:   Separate vectors for each field, contiguous memory}" )
println( styled"{dim:   Enables SIMD and spatial locality}" )
print( styled"{green:aligned (SIMD)}: " )
@btime compute_simd_soa!( s ) setup=( s = alignmem( create_objects($N) ) )

println( styled"\n{dim:Note: The performance gap illustrates the cost of:}" )
println( styled"{dim:  • Pointer chasing (dereferencing objects)}" )
println( styled"{dim:  • Lack of memory contiguity (cache misses)}" )
println( styled"{dim:  • Inability to vectorize (no SIMD on scattered objects)}" )
println( styled"{dim:  • Misalignment of individual scalar fields}" )
