struct MemoryBlock
    addr :: UInt
    size :: Int
end

getblock( x :: AbstractArray ) = ( isbitstype( eltype( x ) ) && length( x ) > 0 ) ? MemoryBlock( UInt( pointer( x ) ), sizeof( x ) ) : nothing
getblock( :: Any ) = nothing

function collectblocks( x :: AbstractArray{T}; exclude = Symbol[] ) where T
    isbitstype( T ) && return MemoryBlock[]
    fnalign = filter( k -> k ∉ exclude, eachindex( x ) )
    return mapreduce( k -> ( b = getblock( x[k] ); isnothing( b ) ? MemoryBlock[] : [b] ), vcat, fnalign; init = MemoryBlock[] )
end

function collectblocks( x :: T; exclude = Symbol[] ) where T
    ( isbitstype( T ) || !isstructtype( T ) ) && return MemoryBlock[]
    fnalign = filter( k -> k ∉ exclude, fieldnames( T ) )
    return mapreduce( k -> ( b = getblock( getfield( x, k ) ); isnothing( b ) ? MemoryBlock[] : [b] ), vcat, fnalign; init = MemoryBlock[] )
end

collectblocks( x :: AbstractDict; exclude = Symbol[] ) = mapreduce( k -> ( b = getblock( x[k] ); isnothing( b ) ? MemoryBlock[] : [b] ), vcat, filter( k -> k ∉ exclude, keys( x ) ); init = MemoryBlock[] )

function collectblocksdeep( x :: AbstractArray; exclude = Symbol[] )
    ( isbitstype( eltype( x ) ) && length( x ) > 0 ) && return [ MemoryBlock( UInt( pointer( x ) ), sizeof( x ) ) ]
    return mapreduce( el -> collectblocksdeep( el; exclude = exclude ), vcat, x; init = MemoryBlock[] )
end

collectblocksdeep( x :: AbstractDict; exclude = Symbol[] ) = mapreduce( k -> k ∈ exclude ? MemoryBlock[] : collectblocksdeep( x[k]; exclude = exclude ), vcat, keys( x ); init = MemoryBlock[] )

collectblocksdeep( x :: T; exclude = Symbol[] ) where T = ( isbitstype( T ) || !isstructtype( T ) ) ? MemoryBlock[] : mapreduce( k -> k ∈ exclude ? MemoryBlock[] : collectblocksdeep( getfield( x, k ); exclude = exclude ), vcat, fieldnames( T ); init = MemoryBlock[] )

function renderblocks( blocks :: Vector{MemoryBlock}; width = 80 )
    isempty( blocks ) && ( println( styled"{yellow:No memory blocks found for visualization.}" ); return "" )
    
    minaddr = minimum( b -> b.addr, blocks )
    maxend = maximum( b -> b.addr + b.size, blocks )
    span = maxend - minaddr
    
    println( styled"{bold:Memory Layout Visualization}" )
    println( "  Span: $(prsz( span ))" )
    println( "  Min : 0x$(string( minaddr, base = 16 )) (leftmost point)" )
    println( "  Max : 0x$(string( maxend, base = 16 )) (rightmost point)" )
    
    scale = span / width
    println( "  Scale: $(prsz( Int( ceil( scale ) ) )) / char" )
    
    line = fill( '░', width )
    
    for b ∈ blocks
        rel_start = b.addr - minaddr
        rel_end = rel_start + b.size
        
        s_idx = floor( Int, rel_start / scale ) + 1
        e_idx = floor( Int, (rel_end - 1) / scale ) + 1
        
        s_idx = clamp( s_idx, 1, width )
        e_idx = clamp( e_idx, 1, width )
        
        for i ∈ s_idx:e_idx
            line[i] = '█'
        end
    end
    
    println( styled"{(fg=cyan):$(String( line ))}" )
end

"""
    visualizelayout( x; exclude = Symbol[], width = 80 )

like `layoutstats` but also provides a graphical representation of the current memory distribution of `x`.
"""
visualizelayout( x; exclude = Symbol[], width = 80 ) = renderblocks( collectblocks( x; exclude = exclude ); width = width )

"""
    deepvisualizelayout( x; exclude = Symbol[], width = 80 )

like `deeplayoutstats` but also provides a graphical representation of the current memory distribution of `x`.
"""
deepvisualizelayout( x; exclude = Symbol[], width = 80 ) = renderblocks( collectblocksdeep( x; exclude = exclude ); width = width )
