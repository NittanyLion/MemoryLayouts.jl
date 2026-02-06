using MemoryLayouts, BenchmarkTools, StyledStrings, LoopVectorization

# Example demonstrating SIMD realignment benefits for strided memory access patterns
# This example shows how realignment helps when working with multiple arrays that
# need to be processed together in SIMD operations

struct StridedComputation
    a::Vector{Float64}
    b::Vector{Float64}
    c::Vector{Float64}
    d::Vector{Float64}
    result::Vector{Float64}
end

function create_misaligned(N = 1_000_000)
    # Create intentionally misaligned arrays by using odd sizes and offsets
    # This simulates real-world scenarios where arrays come from different sources
    a = Vector{Float64}(undef, N + 3)
    b = Vector{Float64}(undef, N + 7)
    c = Vector{Float64}(undef, N + 11)
    d = Vector{Float64}(undef, N + 13)

    # Fill with data, using views to create misalignment
    a[1:N] .= rand(N)
    b[1:N] .= rand(N)
    c[1:N] .= rand(N)
    d[1:N] .= rand(N)

    # Return views that start at different offsets, creating misalignment
    return StridedComputation(
        view(a, 2:(N + 1)),  # offset by 1 element (8 bytes)
        view(b, 3:(N + 2)),  # offset by 2 elements (16 bytes)
        view(c, 4:(N + 3)),  # offset by 3 elements (24 bytes)
        view(d, 2:(N + 1)),  # offset by 1 element (8 bytes)
        zeros(N),
    )
end

function create_aligned(N = 1_000_000)
    # Create properly sized and aligned arrays
    return StridedComputation(rand(N), rand(N), rand(N), rand(N), zeros(N))
end

# Complex SIMD computation that benefits from alignment
function compute_simd!(s::StridedComputation)
    a = s.a
    b = s.b
    c = s.c
    d = s.d
    result = s.result

    # This loop vectorizes better with aligned memory
    @tturbo for i in eachindex(result)
        # Complex computation that uses all four input arrays
        temp1 = a[i] * b[i] + c[i]
        temp2 = d[i] * a[i] - b[i]
        result[i] = temp1 * temp2 + sqrt(abs(c[i] * d[i]))
    end

    return sum(result)
end

# Alternative non-SIMD version for comparison
function compute_scalar!(s::StridedComputation)
    a = s.a
    b = s.b
    c = s.c
    d = s.d
    result = s.result

    @inbounds for i in eachindex(result)
        temp1 = a[i] * b[i] + c[i]
        temp2 = d[i] * a[i] - b[i]
        result[i] = temp1 * temp2 + sqrt(abs(c[i] * d[i]))
    end

    return sum(result)
end

println(styled"{bold:SIMD Memory Realignment Performance Demonstration}")
println(styled"{dim:═══════════════════════════════════════════════}\n")

println(styled"{yellow:Testing with misaligned memory access:}")
print(styled"{red:misaligned (scalar)}: ")
@btime compute_scalar!(s) setup = (s = create_misaligned())
print(styled"{red:misaligned (SIMD)}: ")
@btime compute_simd!(s) setup = (s = create_misaligned())

println(styled"\n{yellow:Testing with naturally aligned memory:}")
print(styled"{green:aligned (scalar)}: ")
@btime compute_scalar!(s) setup = (s = create_aligned())
print(styled"{green:aligned (SIMD)}: ")
@btime compute_simd!(s) setup = (s = create_aligned())

println(styled"\n{yellow:Testing with MemoryLayouts alignment:}")
print(styled"{blue:layout (16-byte)}: ")
@btime compute_simd!(s) setup = (s = layout(create_aligned(); alignment = 16))
print(styled"{blue:layout (32-byte)}: ")
@btime compute_simd!(s) setup = (s = layout(create_aligned(); alignment = 32))
print(styled"{magenta:layout (64-byte)}: ")
@btime compute_simd!(s) setup = (s = layout(create_aligned(); alignment = 64))

println(styled"\n{dim:Note: SIMD performance is highly dependent on memory alignment.}")
println(styled"{dim:Misaligned access can cause significant slowdowns due to:}")
println(styled"{dim:  • Additional memory loads across cache line boundaries}")
println(styled"{dim:  • CPU stalls waiting for unaligned memory operations}")
println(styled"{dim:  • Inability to use optimal SIMD instructions}")
