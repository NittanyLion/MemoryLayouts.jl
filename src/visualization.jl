struct MemoryBlock
    addr :: UInt
    size :: Int
end

getblock( x ) = packable( x ) ? [ MemoryBlock( UInt( pointer( underlying( x ) ) ), sizeof( eltype( x ) ) * length( x ) ) ] : MemoryBlock[]

function collectblocks( x :: AbstractArray{T}; exclude = Symbol[] ) where T
    isbitstype( T ) && return MemoryBlock[]
    return mapreduce( k -> getblock( x[k] ), vcat, filter( k -> k ∉ exclude, eachindex( x ) ); init = MemoryBlock[] )
end

function collectblocks( x :: T; exclude = Symbol[] ) where T
    ( isbitstype( T ) || !isstructtype( T ) ) && return MemoryBlock[]
    return mapreduce( k -> getblock( getfield( x, k ) ), vcat, filter( k -> k ∉ exclude, fieldnames( T ) ); init = MemoryBlock[] )
end

collectblocks( x :: AbstractDict; exclude = Symbol[] ) = mapreduce( k -> getblock( x[k] ), vcat, filter( k -> k ∉ exclude, keys( x ) ); init = MemoryBlock[] )

deepblocks( :: Leaf, :: Block ) = MemoryBlock[]

function deepblocks( x :: AbstractArray, b :: Block )
    packable( x ) && return getblock( x )
    traversable( x ) || return MemoryBlock[]
    withcycle( x, b ) do
        mapreduce( el -> deepblocks( el, b ), vcat, x; init = MemoryBlock[] )
    end
end

function deepblocks( x :: AbstractDict, b :: Block )
    withcycle( x, b ) do
        mapreduce( k -> excluded( k, b ) ? MemoryBlock[] : deepblocks( x[k], b ), vcat, keys( x ); init = MemoryBlock[] )
    end
end

function deepblocks( x :: T, b :: Block ) where T
    ( isbitstype( T ) || !isstructtype( T ) ) && return MemoryBlock[]
    withcycle( x, b ) do
        mapreduce( k -> excluded( k, b ) ? MemoryBlock[] : deepblocks( getfield( x, k ), b ), vcat, fieldnames( T ); init = MemoryBlock[] )
    end
end

function renderblocks( io :: IO, blocks :: Vector{MemoryBlock}; width :: Int = 80 )
    if isempty( blocks )
        println( io, styled"{yellow:No memory blocks found for visualization.}" )
        return nothing
    end

    minaddr = minimum( b -> b.addr, blocks )
    maxend = maximum( b -> b.addr + b.size, blocks )
    span = maxend - minaddr

    println( io, styled"{bold:Memory Layout Visualization}" )
    println( io, "  Span: $(prsz( span ))" )
    println( io, "  Min : 0x$(string( minaddr, base = 16 )) (leftmost point)" )
    println( io, "  Max : 0x$(string( maxend, base = 16 )) (rightmost point)" )

    scale = span / width
    println( io, "  Scale: $(prsz( ceil( Int, scale ) )) / char" )

    line = fill( '░', width )
    for b ∈ blocks
        relstart = b.addr - minaddr
        relend = relstart + b.size
        sidx = clamp( floor( Int, relstart / scale ) + 1, 1, width )
        eidx = clamp( floor( Int, ( relend - 1 ) / scale ) + 1, 1, width )
        line[sidx:eidx] .= '█'
    end
    println( io, styled"{(fg=cyan):$(String( line ))}" )
    return nothing
end

"""
    visualizelayout( [io :: IO], x; exclude = Symbol[], width = 80 )

Like `layoutstats` but prints a graphical representation of the current memory distribution of `x`
to `io` (default `stdout`).  Returns `nothing`.
"""
visualizelayout( io :: IO, x; exclude = Symbol[], width :: Int = 80 ) = renderblocks( io, collectblocks( x; exclude = exclude ); width = width )
visualizelayout( x; kwargs... ) = visualizelayout( stdout, x; kwargs... )

"""
    deepvisualizelayout( [io :: IO], x; exclude = Symbol[], width = 80 )

Like `deeplayoutstats` but prints a graphical representation of the current memory distribution of
`x` to `io` (default `stdout`).  Returns `nothing`.
"""
deepvisualizelayout( io :: IO, x; exclude = Symbol[], width :: Int = 80 ) = renderblocks( io, deepblocks( x, Block( exclude, 1, nothing, false ) ); width = width )
deepvisualizelayout( x; kwargs... ) = deepvisualizelayout( stdout, x; kwargs... )
