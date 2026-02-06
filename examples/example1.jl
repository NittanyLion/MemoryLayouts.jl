using MemoryLayouts, BenchmarkTools, StyledStrings, Random

function original( A = 10_000, L = 100, S = 5000)
    x = Vector{Vector{Float64}}(undef, A)
    s = Vector{Vector{Float64}}(undef, A)
    for i ∈ 1:A
        x[i] = rand( L )
        s[i] = rand( S )
        v = randstring( 33 )
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

X = original()
@info "layout statistics:" deeplayoutstats( X )


print( styled"{red:original}: " ); @btime computeme( X ) setup=(X = original())
print( styled"{green:layout}: " ); @btime computeme( X ) setup=(X = layout( original()))
print( styled"{blue:layout with 16 byte alignment}: " ); @btime computeme( X ) setup=(X = layout( original(); alignment = 16 ) )
print( styled"{blue:layoutmem with 64 byte alignment}: " ); @btime computeme( X ) setup=(X = layoutmem( original(); alignment = 64 ) )
