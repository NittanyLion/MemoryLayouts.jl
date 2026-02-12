# Example 1: Basic Usage of MemoryLayouts
#
# This example demonstrates the basic usage of `layout` to optimize
# a Vector of Vectors (Jagged Array).
#
# It compares the performance of a simple summation function on:
# 1. Original standard vector of vectors (scattered in memory)
# 2. Layout-optimized version (contiguous memory)
# 3. Layout-optimized with specific memory alignments (16 and 64 bytes)
#
# The `layout` function transforms the data into a more cache-friendly format
# while maintaining the same interface (AbstractArray).

using MemoryLayouts, BenchmarkTools, StyledStrings, Random

function original(A = 10_000, L = 100, S = 5000)
    x = Vector{Vector{Float64}}(undef, A)
    s = Vector{Vector{Float64}}(undef, A)
    for i in 1:A
        x[i] = rand(L)
        s[i] = rand(S)
        v = randstring(33)
    end
    return x
end

function computeme(X)
    Σ = 0.0
    for x in X
        Σ += x[5]
    end
    return Σ
end

X = original()
@info "layout statistics:" deepvisualizelayout(X)


