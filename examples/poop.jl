using AlignMemory
using Random
using BenchmarkTools


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


@btime computeme( X ) setup=(X = original())
@btime computeme( X ) setup=(X = alignmem( original()))