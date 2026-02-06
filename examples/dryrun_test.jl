using MemoryLayouts

function original( A = 10, L = 100, S = 50)
    x = Vector{Vector{Float64}}( undef, A )
    s = Vector{Vector{Float64}}( undef, A )
    for i ∈ 1:A
        x[i] = rand( L )
        s[i] = rand( S )
    end
    return x
end

data = original()
println("Data created.")

stats = layoutstats(data)
println("Shallow stats: ", stats)

deepstats = deeplayoutstats(data)
println("Deep stats: ", deepstats)
