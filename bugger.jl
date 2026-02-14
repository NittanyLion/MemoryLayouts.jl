using MemoryLayouts


struct S2
    X   :: Vector{ Vector{ Float64 } }
    Y   :: String
end


struct S
    X   :: Vector{ Vector{ Float64 } }
    Y   :: S2 
    Z   :: S2
    N   :: String
end



function failuretest()
    s2 = S2( [ randn(40) for i ∈ 1:10 ], "poop" )
    s = S( [ randn(4) for i ∈ 1:100 ], s2, s2, "pee" )
    ss = deeplayout( s )
    return ss
end



function whoops()
    s = failuretest()
    GC.gc()
    s.Y.X[1] .= 0.0
    return s 
end


for i ∈ 1:1_000
    i % 10 == 0 && println( i )
    whoops()
end

