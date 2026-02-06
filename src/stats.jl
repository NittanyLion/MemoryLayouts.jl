struct LevelStats
    bytes :: Int
    blocks :: Int
    minaddr :: UInt
    maxaddr :: UInt
end

Base.:+( a :: LevelStats, b :: LevelStats ) = LevelStats( a.bytes + b.bytes, a.blocks + b.blocks, min( a.minaddr, b.minaddr ), max( a.maxaddr, b.maxaddr ) )
Base.zero( :: Type{LevelStats} ) = LevelStats( 0, 0, typemax( UInt ), typemin( UInt ) )

struct LayoutStats
    summary :: LevelStats
    levels :: Dict{Int, LevelStats}
end

function Base.:+( a :: LayoutStats, b :: LayoutStats )
    summary = a.summary + b.summary
    levels = merge( +, a.levels, b.levels )
    LayoutStats( summary, levels )
end

Base.zero( :: Type{LayoutStats} ) = LayoutStats( zero( LevelStats ), Dict{Int, LevelStats}() )

const sizedescriptor = [ "b", "kb", "mb", "gb", "tb", "pb" ]

function prsz( units, level = 1 )
    d = div( units, 1_024, RoundNearestTiesUp ) 
    @assert 1 ≤ level ≤ length( sizedescriptor )
    return  ( d ≥ 2 || ( d == 1 && ( level ≥ 2 && units ≥ 1024 ) ) ) ? prsz( div( units, 1_024 ), level + 1 ) : "$units $(sizedescriptor[level])"    
end


function Base.show( io :: IO, ls :: LayoutStats )
    s = ls.summary
    span = ( s.maxaddr > s.minaddr ) ? Int( s.maxaddr - s.minaddr ) : 0
    reduction = span - s.bytes
    reductionpct = span > 0 ? round( 100 * reduction / span; digits = 1 ) : 0.0
    print( io, "LayoutStats(packed=$(prsz(s.bytes)), blocks=$(s.blocks), span=$(prsz(span)), reduction=$(prsz(reduction)) ($reductionpct%))" )
    for level ∈ sort( collect( keys( ls.levels ) ) )
        ℓ = ls.levels[level]
        ℓspan = ( ℓ.maxaddr > ℓ.minaddr ) ? Int( ℓ.maxaddr - ℓ.minaddr ) : 0
        ℓreduction = ℓspan - ℓ.bytes
        ℓreductionpct = ℓspan > 0 ? round( 100 * ℓreduction / ℓspan; digits = 1 ) : 0.0
        print( io, "\n  Level $level: bytes=$(prsz(ℓ.bytes)), blocks=$(ℓ.blocks), span=$(prsz(ℓspan)), reduction=$(prsz(ℓreduction)) ($ℓreductionpct%)" )
    end
end

computestats( :: Any; kwargs... ) = zero( LayoutStats )

function computestats( x :: AbstractArray; alignment :: Int = 1, level :: Int = 1 )
    (isbitstype( eltype( x ) ) && length( x ) > 0) || return zero( LayoutStats )
    sz = alignup( sizeof( eltype( x ) ) * length( x ), alignment )
    ptr = UInt( pointer( x ) )
    stats = LevelStats( sz, 1, ptr, ptr + sizeof( x ) )
    return LayoutStats( stats, Dict( level => stats ) )
end

"""
    layoutstats( s; exclude = Symbol[], alignment :: Int = 1 )

Returns a `LayoutStats` object containing statistics about the memory layout if `layout( s )` were called.

The returned object includes:
- `bytes`: Total size (in bytes) of the data that would be packed.
- `blocks`: Number of individual arrays identified.
- `span`: The distance between the minimum and maximum memory addresses of the data.
- `reduction`: The potential reduction in memory span (span - bytes).
"""
function layoutstats( s :: AbstractArray{T}; exclude = Symbol[], alignment :: Int = 1 ) where T
    isbitstype( T ) && return zero( LayoutStats )
    fnalign = filter( k -> k ∉ exclude, eachindex( s ) )
    return mapreduce( k -> computestats( s[k]; alignment = alignment ), +, fnalign; init = zero( LayoutStats ) )
end

function layoutstats( s :: T; exclude = Symbol[], alignment :: Int = 1 ) where T
    (isbitstype( T ) || !isstructtype( T ) ) && return zero( LayoutStats )
    fn = fieldnames( T )
    fnalign = filter( k -> k ∉ exclude, fn )
    return mapreduce( k -> computestats( getfield( s, k ); alignment = alignment ), +, fnalign; init = zero( LayoutStats ) )
end

function layoutstats( s :: AbstractDict; exclude = Symbol[], alignment :: Int = 1 )
    keysalign = filter( k -> k ∉ exclude, keys( s ) )
    return mapreduce( k -> computestats( s[k]; alignment = alignment ), +, keysalign; init = zero( LayoutStats ) )
end

function computestatsdeep( x :: AbstractArray; exclude = Symbol[], alignment :: Int = 1, level :: Int = 0 )
    if isbitstype( eltype( x ) ) && length( x ) > 0
        sz = alignup( sizeof( eltype( x ) ) * length( x ), alignment )
        ptr = UInt( pointer( x ) )
        stats = LevelStats( sz, 1, ptr, ptr + sizeof( x ) )
        return LayoutStats( stats, Dict( level => stats ) )
    end
    return mapreduce( el -> computestatsdeep( el; exclude = exclude, alignment = alignment, level = level + 1 ), +, x; init = zero( LayoutStats ) )
end

computestatsdeep( x :: AbstractDict; exclude = Symbol[], alignment :: Int = 1, level :: Int = 0 ) = 
    mapreduce( k -> k ∈ exclude ? zero( LayoutStats ) : computestatsdeep( x[k]; exclude = exclude, alignment = alignment, level = level + 1 ), +, keys(x); init = zero( LayoutStats ) )

computestatsdeep( x :: T; exclude = Symbol[], alignment :: Int = 1, level :: Int = 0 ) where T = isbitstype( T ) || !isstructtype( T ) ? zero( LayoutStats ) : mapreduce( k -> k ∈ exclude ? zero( LayoutStats ) : computestatsdeep( getfield( x, k ); exclude = exclude, alignment = alignment, level = level + 1 ), +, fieldnames( T ); init = zero( LayoutStats ) )

"""
    deeplayoutstats( x; exclude = Symbol[], alignment :: Int = 1 )

Returns a `LayoutStats` object containing statistics about the memory layout if `deeplayout( x )` were called.

The returned object includes:
- `bytes`: Total size (in bytes) of the data that would be packed.
- `blocks`: Number of individual arrays identified.
- `span`: The distance between the minimum and maximum memory addresses of the data.
- `reduction`: The potential reduction in memory span (span - bytes).
"""
deeplayoutstats( x; exclude = Symbol[], alignment :: Int = 1 ) = computestatsdeep( x; exclude = exclude, alignment = alignment )
