using MemoryLayouts, BenchmarkTools, StyledStrings, LoopVectorization

struct SimdStruct
    x :: Vector{Float64}
    y :: Vector{Float64}
    z :: Vector{Float64}
end

function original( N = 10000003 )
    return SimdStruct( rand( N ), rand( N ), zeros( N ) )
end

function computeme( S )
    x = S.x
    y = S.y
    z = S.z
    @turbo for i ∈ eachindex( x )
        z[i] = x[i] * y[i] + x[i]
    end
    return nothing
end

println( "Benchmarking SIMD performance with different alignments:" )
print( styled"{red:original}: " ); @btime computeme( S ) setup=( S = original() )
print( styled"{green:alignmem (default)}: " ); @btime computeme( S ) setup=( S = alignmem( original() ) )
print( styled"{blue:alignmem (32-byte)}: " ); @btime computeme( S ) setup=( S = alignmem( original(); alignment = 32 ) )
