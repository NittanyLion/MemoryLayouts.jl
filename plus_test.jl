using BenchmarkTools

a = zeros(2)
b = zeros(2)
@btime $a + $b
