using MemoryLayouts, BenchmarkTools, StyledStrings, LoopVectorization

# Example 5: Impact of Memory Contiguity and Alignment
# This example compares three memory layouts for Structure of Arrays (SoA):
# 1. Standard: Separate allocations for each array (non-contiguous).
# 2. Contiguous (Standard Alignment): Arrays packed into a single memory block with 16-byte alignment.
# 3. Contiguous (Cache Aligned): Arrays packed and strictly aligned to 64-byte boundaries.

struct Data
    a::Vector{Float64}
    b::Vector{Float64}
    c::Vector{Float64}
    d::Vector{Float64}
    res::Vector{Float64}
end

# 1. Standard independent allocations
function create_standard(N)
    return Data(
        rand(N),
        rand(N),
        rand(N),
        rand(N),
        zeros(N)
    )
end

# Computation function (SIMD optimized)
# Uses same logic as example3 to ensure stability with LoopVectorization
function compute!(s::Data)
    a, b, c, d, res = s.a, s.b, s.c, s.d, s.res
    @tturbo for i in eachindex(res)
        # Complex computation requiring multiple streams
        temp1 = a[i] * b[i] + c[i]
        temp2 = d[i] * a[i] - b[i]
        res[i] = temp1 * temp2 + sqrt( abs( c[i] * d[i] ) )
    end
    return sum(res)
end

# Use standard even size to avoid alignment edge cases with LoopVectorization
N = 1_000_003 

println(styled"{bold:Contiguity and Alignment Benchmark (N=$N)}\n")

# Benchmark 1: Standard
println(styled"{yellow:1. Non-contiguous (Standard Separate Allocations)}")
println(styled"{dim:   Arrays are allocated separately on the heap.}")
print(styled"{red:Standard}:   ")
data_std = create_standard(N)
@btime compute!(s) setup=( s = create_standard(N) )

# Benchmark 2: Contiguous (alignment=16)
println(styled"\n{yellow:2. Contiguous (Packed, alignment=1)}")
println(styled"{dim:   Arrays packed into one block with standard 16-byte alignment.}")
print(styled"{blue:alignmem(16)}: ")
@btime compute!(s) setup=(s = alignmem(create_standard(N); alignment=1))

# Benchmark 3: Contiguous (Aligned, alignment=64)
println(styled"\n{yellow:3. Contiguous (Aligned, alignment=64)}")
println(styled"{dim:   Arrays packed into one block. Forced 64-byte (cache line) alignment.}")
print(styled"{green:alignmem(64)}: ")
@btime compute!(s) setup=(s = alignmem(create_standard(N); alignment=64))
