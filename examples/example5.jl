using MemoryLayouts, BenchmarkTools, StyledStrings, LoopVectorization, Random, Plots

# Example 5: Misalignment Penalties and Alignment Fixes

struct ArrayContainer
    a :: Vector{Float64}
    b :: Vector{Float64}
    c :: Vector{Float64}
    d :: Vector{Float64}
    res :: Vector{Float64}
end

const K = 1000

function original( N )
    x = [ randn(N) for i ∈ 1:K ]
    return ArrayContainer( x[rand(1:K)], x[rand(1:K)], x[rand(1:K)], x[rand(1:K)], x[rand(1:K)] )
end

function computeme!( ac )
    a, b, c, d, res = ac.a, ac.b, ac.c, ac.d, ac.res
    
    @turbo for i ∈ eachindex( res )
        v1 = a[i] * b[i]
        v2 = c[i] + d[i]
        v3 = v1 - v2
        res[i] = v3 * v3
    end
    return sum( res )
end

# N chosen so that N * 8 is not divisible by 64 (cache line)
N = 10_007

println( styled"{bold:Demonstrating MemoryLayouts Performance (N=$N)}\n" )

println( styled"{yellow:1. Standard Allocations (Baseline)}" )
println( styled"{dim:   Allocated separately. Usually 16-64 byte aligned by system allocator.}" )
print( styled"{red:Standard}:   " )
bstd = @benchmark computeme!( datastd ) setup=(datastd = original( N ))
display( bstd )

println( styled"\n{yellow:2. Contiguous (layoutmem 1)}" )
println( styled"{dim:   Packed withouut padding.}" )
print( styled"{green:layoutmem(1)}: " )

baligned1 = @benchmark computeme!( dataaligned ) setup=( dataaligned = deeplayoutmem( original( N ); alignment = 1 ) )
display( baligned1 )


println( styled"\n{yellow:3. Contiguous and Aligned (layoutmem 64)}" )
println( styled"{dim:   Packed with padding to ensure 64-byte alignment for all arrays.}" )
println( styled"{dim:   Safe for AVX-512 SIMD operations.}" )
print( styled"{green:layoutmem(64)}: " )
# dataaligned = deeplayoutmem( original( N ); alignment = 64 )
baligned64 = @benchmark computeme!( dataaligned ) setup=( dataaligned = deeplayoutmem( original( N ); alignment = 64 ) )
display( baligned64 )


tstd = median( bstd ).time
taligned = median( baligned64 ).time

diffaligned = ( tstd - taligned ) / tstd * 100

println( "\n" * "="^60 )
println( styled"Speedup from layoutmem(64): {bold,green:$(round(diffaligned, digits=1))%}" )
println( "="^60 )

println( styled"\n{bold:Generating plot...}" )
timesstd = bstd.times ./ 1000
timesaligned1 = baligned1.times ./ 1000
timesaligned64 = baligned64.times ./ 1000

p = histogram( timesstd; label = "Standard", alpha = 0.5, xlabel = "Time (μs)", ylabel = "Frequency", title = "Benchmark Comparison" )
histogram!( p, timesaligned1; label = "Aligned (1)", alpha = 0.5 )
histogram!( p, timesaligned64; label = "Aligned (64)", alpha = 0.5 )
display( p )
