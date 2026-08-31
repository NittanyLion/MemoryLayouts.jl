struct LevelStats
    bytes   :: Int
    blocks  :: Int
    minaddr :: UInt
    maxaddr :: UInt
end

Base.:+( a :: LevelStats, b :: LevelStats ) = LevelStats( a.bytes + b.bytes, a.blocks + b.blocks, min( a.minaddr, b.minaddr ), max( a.maxaddr, b.maxaddr ) )
Base.zero( :: Type{LevelStats} ) = LevelStats( 0, 0, typemax( UInt ), typemin( UInt ) )

struct LayoutStats
    summary :: LevelStats
    levels  :: Dict{Int, LevelStats}
end

Base.:+( a :: LayoutStats, b :: LayoutStats ) = LayoutStats( a.summary + b.summary, merge( +, a.levels, b.levels ) )
Base.zero( :: Type{LayoutStats} ) = LayoutStats( zero( LevelStats ), Dict{Int, LevelStats}() )

const sizedescriptor = [ "b", "kb", "mb", "gb", "tb", "pb" ]

# human-readable byte count: exact below 1 kb, one decimal above
function prsz( units :: Integer )
    level = 1
    x = float( units )
    while x ≥ 1024 && level < length( sizedescriptor )
        x /= 1024
        level += 1
    end
    return level == 1 ? "$units b" : "$(round( x; digits = 1 )) $(sizedescriptor[level])"
end

function describe( io :: IO, s :: LevelStats )
    span = s.maxaddr > s.minaddr ? Int( s.maxaddr - s.minaddr ) : 0
    reduction = span - s.bytes
    reductionpct = span > 0 ? round( 100 * reduction / span; digits = 1 ) : 0.0
    print( io, "packed=$( prsz( s.bytes ) ), blocks=$( s.blocks ), span=$( prsz( span ) ), reduction=$( prsz( reduction ) ) ($reductionpct%)" )
end

Base.show( io :: IO, ls :: LayoutStats ) = ( print( io, "LayoutStats( " ); describe( io, ls.summary ); print( io, " )" ) )

function Base.show( io :: IO, :: MIME"text/plain", ls :: LayoutStats )
    show( io, ls )
    for level ∈ sort( collect( keys( ls.levels ) ) )
        print( io, "\n  Level $level: " )
        describe( io, ls.levels[level] )
    end
end

function blockstats( x, alignment :: Int, level :: Int )
    packable( x ) || return zero( LayoutStats )
    ptr = UInt( pointer( underlying( x ) ) )
    stats = LevelStats( alignup( sizeof( eltype( x ) ) * length( x ), alignment ), 1, ptr, ptr + sizeof( eltype( x ) ) * length( x ) )
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
    return mapreduce( k -> blockstats( s[k], alignment, 1 ), +, filter( k -> k ∉ exclude, eachindex( s ) ); init = zero( LayoutStats ) )
end

function layoutstats( s :: T; exclude = Symbol[], alignment :: Int = 1 ) where T
    ( isbitstype( T ) || !isstructtype( T ) ) && return zero( LayoutStats )
    return mapreduce( k -> blockstats( getfield( s, k ), alignment, 1 ), +, filter( k -> k ∉ exclude, fieldnames( T ) ); init = zero( LayoutStats ) )
end

layoutstats( s :: AbstractDict; exclude = Symbol[], alignment :: Int = 1 ) = mapreduce( k -> blockstats( s[k], alignment, 1 ), +, filter( k -> k ∉ exclude, keys( s ) ); init = zero( LayoutStats ) )

# Deep statistics reuse the traversal bookkeeping of deeplayout (cycle detection, exclusion).
deepstats( :: Leaf, :: Block, :: Int ) = zero( LayoutStats )

function deepstats( x :: AbstractArray, b :: Block, level :: Int )
    packable( x ) && return sizeonce( () -> blockstats( x, b.alignment, level ), x, b, zero( LayoutStats ) )
    traversable( x ) || return zero( LayoutStats )
    withcycle( x, b ) do
        mapreduce( el -> deepstats( el, b, level + 1 ), +, x; init = zero( LayoutStats ) )
    end
end

function deepstats( x :: AbstractDict, b :: Block, level :: Int )
    withcycle( x, b ) do
        mapreduce( k -> excluded( k, b ) ? zero( LayoutStats ) : deepstats( x[k], b, level + 1 ), +, keys( x ); init = zero( LayoutStats ) )
    end
end

function deepstats( x :: T, b :: Block, level :: Int ) where T
    ( isbitstype( T ) || !isstructtype( T ) ) && return zero( LayoutStats )
    withcycle( x, b ) do
        mapreduce( k -> excluded( k, b ) ? zero( LayoutStats ) : deepstats( getfield( x, k ), b, level + 1 ), +, fieldnames( T ); init = zero( LayoutStats ) )
    end
end

"""
    deeplayoutstats( x; exclude = Symbol[], alignment :: Int = 1 )

Returns a `LayoutStats` object containing statistics about the memory layout if `deeplayout( x )` were called.

The returned object includes:
- `bytes`: Total size (in bytes) of the data that would be packed.
- `blocks`: Number of individual arrays identified.
- `span`: The distance between the minimum and maximum memory addresses of the data.
- `reduction`: The potential reduction in memory span (span - bytes).
"""
deeplayoutstats( x; exclude = Symbol[], alignment :: Int = 1 ) = deepstats( x, Block( exclude, alignment, nothing, false ), 0 )
