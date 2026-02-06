using MemoryLayouts, BenchmarkTools, StyledStrings

struct 𝒮{X, Y, Z}
    x::X
    y::Y
    z::Z
end

function original(A = 10_000, L = 100, S = 5000)
    x = Vector{Vector{Float64}}(undef, A)
    s = Vector{Vector{Float64}}(undef, A)
    for i in 1:A
        x[i] = rand(L)
        s[i] = rand(S)
    end
    return 𝒮(
        [x[i] for i in 1:div(A, 3)],
        [x[i] for i in (div(A, 3) + 1):div(2 * A, 3)],
        [x[i] for i in (div(2 * A, 3) + 1):A],
    )
end

function computeme(X)
    Σ = 0.0
    for x in X.x
        Σ += x[5]
    end
    for y in X.y
        Σ += y[37]
    end
    for z in X.z
        Σ += z[5]
    end
    return Σ
end

println(layoutstats(original()))
println(deeplayoutstats(original()))

print(styled"{red  :original     }: ");
@btime computeme(X) setup = (X = original());
print(styled"{green:layout       }: ");
@btime computeme(X) setup = (X = layout(original()));
print(styled"{blue :deeplayout   }: ");
@btime computeme(X) setup = (X = deeplayout(original()));
