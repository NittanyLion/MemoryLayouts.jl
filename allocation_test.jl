using BenchmarkTools

struct Data
    res::Vector{Float64}
end

function test_allocs(v)
    return sum(s.res for s in v)
end

N = 1103
v = [Data(zeros(2)) for _ in 1:N]

@btime test_allocs($v)
