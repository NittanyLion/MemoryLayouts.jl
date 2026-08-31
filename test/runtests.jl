using MemoryLayouts
using Test
using Aqua
using JET
using OffsetArrays, AxisKeys, NamedDims, InlineStrings

@testset "Aqua" begin
    Aqua.test_all( MemoryLayouts )
end

@testset "JET" begin
    JET.test_package( MemoryLayouts; target_modules = ( MemoryLayouts, ) )
end

struct S
    a :: Vector{Float64}
    b :: Vector{Float64}
end

struct DeepS
    x :: S
    y :: Vector{Int}
end

mutable struct Node
    data :: Vector{Float64}
    next :: Union{Node, Nothing}
end

struct WithRange
    r :: UnitRange{Int}
    v :: Vector{Float64}
end

struct WithView
    s :: SubArray{Float64, 1, Vector{Float64}, Tuple{UnitRange{Int}}, true}
    v :: Vector{Float64}
end

struct Positive
    v :: Vector{Float64}
    Positive( v ) = ( all( >( 0 ), v ) || throw( DomainError( v, "not positive" ) ); new( v ) )
end

contiguous( a, b ) = UInt( pointer( b ) ) == UInt( pointer( a ) ) + sizeof( eltype( a ) ) * length( a )
gcs() = foreach( _ -> GC.gc( true ), 1:3 )

@testset "MemoryLayouts.jl" begin
    @testset "layout struct" begin
        s = S( rand( 10 ), rand( 20 ) )
        t = layout( s )
        @test t.a == s.a
        @test t.b == s.b
        @test contiguous( t.a, t.b )
        @test t.a !== s.a                     # a copy was made
        @test s.a == layout( s ).a            # original untouched
    end

    @testset "layout array of arrays" begin
        v = [ rand( 5 ) for _ ∈ 1:4 ]
        w = layout( v )
        @test w == v
        @test all( contiguous( w[i], w[i+1] ) for i ∈ 1:3 )
        r = rand( 3 )                          # isbits arrays are returned as is
        @test layout( r ) === r
    end

    @testset "layout dict" begin
        d = Dict( :a => rand( 10 ), :b => rand( 20 ) )
        e = layout( d )
        @test e[:a] == d[:a]
        @test e[:b] == d[:b]
        @test e[:a] !== d[:a]
        pa, pb = pointer( e[:a] ), pointer( e[:b] )
        @test contiguous( e[:a], e[:b] ) || contiguous( e[:b], e[:a] )

        f = Dict( :a => rand( 10 ), :b => rand( 20 ) )
        old = f[:a]
        @test layout!( f ) === f
        @test f[:a] == old
        @test f[:a] !== old
    end

    @testset "deeplayout" begin
        ds = DeepS( S( rand( 5 ), rand( 5 ) ), rand( Int, 5 ) )
        dt = deeplayout( ds )
        @test dt.x.a == ds.x.a
        @test dt.x.b == ds.x.b
        @test dt.y == ds.y
        @test contiguous( dt.x.a, dt.x.b )
        @test contiguous( dt.x.b, dt.y )

        d = Dict( :a => Dict( :x => rand( 10 ) ), :b => rand( 20 ) )
        e = deeplayout( d )
        @test e[:a][:x] == d[:a][:x]
        @test e[:b] == d[:b]
        @test contiguous( e[:a][:x], e[:b] ) || contiguous( e[:b], e[:a][:x] )

        nested = [ [ rand( 3 ) for _ ∈ 1:2 ] for _ ∈ 1:2 ]
        flat = deeplayout( nested )
        @test flat == nested
        @test contiguous( flat[1][1], flat[1][2] ) && contiguous( flat[1][2], flat[2][1] )

        @test deeplayout( ( rand( 3 ), rand( 4 ) ) ) isa Tuple
        nt = deeplayout( ( a = rand( 3 ), b = rand( 4 ) ) )
        @test nt isa NamedTuple && contiguous( nt.a, nt.b )
        @test deeplayout( "text" ) == "text"
        @test deeplayout( 3 ) == 3
    end

    @testset "matrices and mixed element types" begin
        m = layout( [ rand( 2, 3 ), rand( Int32, 4 ), rand( Float32, 5 ) ] )
        @test m[1] isa Matrix{Float64} && size( m[1] ) == ( 2, 3 )
        @test m[2] isa Vector{Int32}
        @test m[3] isa Vector{Float32}
        @test UInt( pointer( m[3] ) ) % 4 == 0
    end

    @testset "alignment option" begin
        s = S( rand( 10 ), rand( 20 ) )
        t = layout( s, alignment = 64 )
        @test mod( UInt( pointer( t.a ) ), 64 ) == 0
        @test mod( UInt( pointer( t.b ) ), 64 ) == 0
        diff = UInt( pointer( t.b ) ) - UInt( pointer( t.a ) )
        @test diff ≥ sizeof( t.a ) && mod( diff, 64 ) == 0

        # alignment smaller than the natural alignment of the element type is still honored
        u = layout( [ rand( Int8, 3 ), rand( 4 ) ]; alignment = 1 )
        @test UInt( pointer( u[2] ) ) % 8 == 0
        @test u[2] isa Vector{Float64}

        @test_throws ArgumentError layout( s; alignment = 0 )
    end

    @testset "unsupported array types are passed through" begin
        s = WithRange( 1:10, rand( 3 ) )
        t = layout( s )
        @test t.r === s.r
        @test t.v == s.v && t.v !== s.v
        u = deeplayout( s )
        @test u.r === s.r && u.v == s.v

        base = rand( 10 )
        w = layout( WithView( view( base, 1:5 ), rand( 3 ) ) )
        @test w.s isa SubArray

        b = layout( [ trues( 4 ), rand( 2 ) ] )
        @test b[1] isa BitVector

        @test layoutstats( [ 1:10, 1:20 ] ).summary.blocks == 0
        @test deeplayoutstats( WithRange( 1:10, rand( 3 ) ) ).summary.blocks == 1
    end

    @testset "zero-size and empty arrays" begin
        z = layout( [ fill( nothing, 3 ), rand( 2 ) ] )
        @test z[1] == fill( nothing, 3 )
        @test z[2] isa Vector{Float64}
        e = layout( S( Float64[], rand( 2 ) ) )
        @test isempty( e.a )
        @test deeplayout( Dict{Symbol, Vector{Float64}}() ) == Dict()
    end

    @testset "errors are informative, not swallowed" begin
        p = Positive( [ 1.0, 2.0 ] )
        @test deeplayout( p ).v == p.v
        # a constructor that rejects the rebuilt fields surfaces as an ArgumentError carrying the cause
        err = try
            MemoryLayouts.rebuild( p, ( [ -1.0 ], ) )
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin( "not positive", err.msg ) && occursin( "exclude", err.msg )
    end

    @testset "aliasing preserves sharing" begin
        shared = rand( 100 )
        c = S( shared, shared )
        t = @test_nowarn layout( c )
        @test t.a === t.b
        @test t.a == shared

        d = deeplayout( DeepS( S( shared, shared ), rand( Int, 2 ) ) )
        @test d.x.a === d.x.b

        inner = rand( 4 )
        v = deeplayout( [ inner, inner, rand( 4 ) ] )
        @test v[1] === v[2] && v[1] !== v[3]

        # container identity is preserved too
        arr = [ rand( 3 ) ]
        pair = deeplayout( ( arr, arr ) )
        @test pair[1] === pair[2]

        # livedangerously duplicates instead
        u = layout( c; livedangerously = true )
        @test u.a !== u.b && u.a == u.b
    end

    @testset "cycles" begin
        a = Node( rand( 3 ), nothing )
        b = Node( rand( 3 ), a )
        a.next = b
        @test_throws ArgumentError deeplayout( a )
        @test_throws ArgumentError deeplayoutstats( a )
        @test_throws ArgumentError deepvisualizelayout( devnull, a )
        chain = Node( rand( 3 ), Node( rand( 3 ), nothing ) )
        c = deeplayout( chain )
        @test c.data == chain.data && c.next.data == chain.next.data
        @test contiguous( c.data, c.next.data )
        d = Dict( :a => rand( 3 ) )
        @test deeplayout( d; livedangerously = true )[:a] == d[:a]
    end

    @testset "exclude" begin
        s = S( rand( 3 ), rand( 4 ) )
        t = layout( s; exclude = [:a] )
        @test t.a === s.a                    # shallow: excluded fields are shared
        @test t.b !== s.b

        ds = DeepS( S( rand( 3 ), rand( 4 ) ), rand( Int, 2 ) )
        dt = deeplayout( ds; exclude = [:a] )
        @test dt.x.a == ds.x.a && dt.x.a !== ds.x.a   # deep: excluded fields are deep-copied
        @test contiguous( dt.x.b, dt.y )

        d = Dict( :a => rand( 3 ), :b => rand( 3 ) )
        e = deeplayout( d; exclude = [:a] )
        @test e[:a] == d[:a] && e[:a] !== d[:a]
        f = layout( d; exclude = [:a] )
        @test f[:a] === d[:a]

        @test layoutstats( s; exclude = [:a] ).summary.blocks == 1
        @test deeplayoutstats( ds; exclude = [:a] ).summary.blocks == 2
    end

    @testset "handles and withlayout" begin
        h = LayoutHandle()
        s = layout( S( rand( 3 ), rand( 3 ) ); handle = h )
        @test length( h.backing ) == 1
        @test contiguous( s.a, s.b )
        release!( h )
        @test isempty( h.backing )

        captured = Ref{Any}( nothing )
        result = withlayout() do
            x = deeplayout( S( rand( 3 ), rand( 3 ) ) )
            y = layout( Dict( :a => rand( 2 ) ) )
            captured[] = MemoryLayouts.layoutscope[]
            @test length( captured[].backing ) == 2
            sum( x.a ) + sum( y[:a] )
        end
        @test result isa Float64
        @test isempty( captured[].backing )
        @test isnothing( MemoryLayouts.layoutscope[] )

        # a throwing body still releases
        h2 = Ref{Any}( nothing )
        @test_throws ErrorException withlayout() do
            h2[] = MemoryLayouts.layoutscope[]
            layout( S( rand( 3 ), rand( 3 ) ) )
            error( "boom" )
        end
        @test isempty( h2[].backing )

        @test_deprecated release_all!()
    end

    @testset "memory is kept alive and released without a handle" begin
        function make()
            t = layout( S( rand( 1000 ), rand( 1000 ) ) )
            return t.b, WeakRef( t.a )
        end
        b, wa = make()
        gcs()
        @test length( b ) == 1000 && all( 0 .≤ b .≤ 1 )     # still readable after the rest was collected

        before = length( MemoryLayouts.keepalive )
        function churn()
            for _ ∈ 1:200
                t = layout( S( rand( 1024 ), rand( 1024 ) ) )
                t.a[1] = 1.0
            end
        end
        churn()
        gcs()
        @test length( MemoryLayouts.keepalive ) ≤ before + 2     # entries are cleaned up, no leak
    end

    @testset "stats" begin
        data = [ rand( 10 ) for _ ∈ 1:5 ]
        st = layoutstats( data )
        @test st.summary.bytes == 400
        @test st.summary.blocks == 5
        @test st.levels[1].blocks == 5
        @test occursin( "packed=400 b", repr( st ) )
        @test !occursin( "Level", repr( st ) )
        @test occursin( "Level 1", sprint( show, MIME"text/plain"(), st ) )
        @test layoutstats( rand( 3 ) ).summary.blocks == 0
        @test layoutstats( S( rand( 3 ), rand( 4 ) ); alignment = 64 ).summary.bytes == 128

        ds = DeepS( S( rand( 5 ), rand( 5 ) ), rand( Int, 5 ) )
        dst = deeplayoutstats( ds )
        @test dst.summary.blocks == 3
        @test dst.levels[1].blocks == 1 && dst.levels[2].blocks == 2
        @test deeplayoutstats( Dict( :a => Dict( :x => rand( 2 ) ) ) ).summary.blocks == 1

        @test MemoryLayouts.prsz( 1023 ) == "1023 b"
        @test MemoryLayouts.prsz( 1024 ) == "1.0 kb"
        @test MemoryLayouts.prsz( 1536 ) == "1.5 kb"
        @test MemoryLayouts.prsz( 3 * 1024^2 ) == "3.0 mb"
    end

    @testset "visualization" begin
        data = [ rand( 10 ) for _ ∈ 1:5 ]
        out = sprint( visualizelayout, data )
        @test occursin( "Memory Layout Visualization", out )
        @test occursin( "█", out )
        @test isnothing( visualizelayout( devnull, data ) )
        @test occursin( "No memory blocks", sprint( visualizelayout, rand( 3 ) ) )
        deep = sprint( deepvisualizelayout, DeepS( S( rand( 5 ), rand( 5 ) ), rand( Int, 5 ) ) )
        @test occursin( "Span", deep )
    end

    @testset "extensions" begin
        o = OffsetArray( rand( 4 ), -1 )
        t = layout( [ o, rand( 2 ) ] )
        @test t[1] isa OffsetArray && axes( t[1] ) == axes( o ) && t[1] == o
        @test contiguous( parent( t[1] ), t[2] )
        @test layoutstats( [ o ] ).summary.blocks == 1
        om = OffsetArray( rand( 2, 3 ), -1, -1 )              # OffsetMatrix defines no `pointer`; stats must peel it
        @test layoutstats( [ om ] ).summary.blocks == 1
        km = KeyedArray( parent( om ), ( [ :a, :b ], [ :x, :y, :z ] ) )             # shares om's data
        @test occursin( "Span", sprint( deepvisualizelayout, ( om, km ) ) )
        @test deeplayoutstats( ( om, km ) ).summary.blocks == 1                       # same data, counted once
        tw = deeplayout( ( om, km ) )
        @test parent( parent( tw[1] ) ) === parent( tw[2] )                            # ... and moved once: still shared
        ro = OffsetArray( 1:4, -1 )                          # offset view of a range: not transferable
        @test layout( [ ro, rand( 2 ) ] )[1] === ro

        k = KeyedArray( rand( 3 ), ( [ :a, :b, :c ], ) )
        tk = layout( [ k, rand( 2 ) ] )
        @test tk[1] isa KeyedArray && axiskeys( tk[1] ) == axiskeys( k ) && tk[1] == k
        @test contiguous( parent( tk[1] ), tk[2] )
        named = KeyedArray( rand( 3 ); time = [ :a, :b, :c ] )     # KeyedArray over NamedDimsArray over Vector
        tnamed = layout( [ named, rand( 2 ) ] )
        @test tnamed[1] isa KeyedArray && tnamed[1] == named && dimnames( tnamed[1] ) == ( :time, )
        @test contiguous( parent( parent( tnamed[1] ) ), tnamed[2] )

        n = NamedDimsArray( rand( 2, 2 ), ( :row, :col ) )
        tn = deeplayout( ( n, rand( 2 ) ) )
        @test tn[1] isa NamedDimsArray && dimnames( tn[1] ) == ( :row, :col ) && tn[1] == n
        @test contiguous( parent( tn[1] ), tn[2] )

        st = layout( [ [ String3( "ab" ), String3( "cd" ) ], rand( 2 ) ] )
        @test st[1] == [ String3( "ab" ), String3( "cd" ) ]
        @test contiguous( st[1], st[2] ) || UInt( pointer( st[2] ) ) > UInt( pointer( st[1] ) )
    end

    @testset "large struct" begin
        big = [ rand( 1000 ) for _ ∈ 1:500 ]
        t = layout( big )
        @test t == big
        @test all( contiguous( t[i], t[i+1] ) for i ∈ 1:499 )
        @test layoutstats( big ).summary.bytes == 500 * 8000
    end

    @testset "mixed dict" begin
        d = Dict{Any, Any}( :a => rand( 3 ), :b => "text", :c => 1, :d => [ "x", "y" ], :e => rand( Int, 2 ) )
        e = layout( d )
        @test e[:b] == "text" && e[:c] == 1 && e[:d] == [ "x", "y" ]
        @test e[:a] == d[:a] && e[:e] == d[:e]
        @test layoutstats( d ).summary.blocks == 2
    end
end
