alignup( x, a ) = cld( x, a ) * a

# ---------------------------------------------------------------------------------------------------
# Ownership of the backing memory
# ---------------------------------------------------------------------------------------------------

"""
    LayoutHandle

A handle that tracks the backing memory for arrays created by `layout`, `layout!`, or `deeplayout`.
Call `release!( handle )` to free the backing memory when the laid-out arrays are no longer needed.

Handles are optional.  Without one, the backing memory is managed by the garbage collector: it stays
alive for as long as any of the arrays that point into it is alive, and is freed afterwards.  A handle
trades that safety for *deterministic* release, which can matter for large blocks.

Preferred usage is via `withlayout`, which creates a scoped handle and releases it automatically:

```julia
result = withlayout() do
    x = deeplayout( a )
    y = deeplayout( b )
    compute( x, y )
end
```

Alternatively, pass an explicit handle:

```julia
h = LayoutHandle()
x = deeplayout( a; handle = h )
release!( h )
```

!!! warning
    After `release!`, any array that was created with that handle points into freed memory.  Using
    such an array is undefined behavior (use-after-free): it may return garbage or crash the process.
"""
mutable struct LayoutHandle
    backing :: IdDict{Vector{UInt8}, Nothing}
    lock    :: ReentrantLock
    LayoutHandle() = new( IdDict{Vector{UInt8}, Nothing}(), ReentrantLock() )
end

"""
    release!( handle :: LayoutHandle )

Free the backing memory tracked by this handle.
Only call this when you are certain no arrays associated with this handle are still in use.
"""
function release!( handle :: LayoutHandle )
    @lock handle.lock empty!( handle.backing )
    return nothing
end

const layoutscope = ScopedValue{Union{LayoutHandle, Nothing}}( nothing )

# Arrays created without a handle: each array's `Memory` is a weak key whose value is the backing
# block, so the block is kept alive by the garbage collector for as long as any such array lives and
# is freed once the last one is collected.  (A finalizer closure capturing the block does *not*
# provide this guarantee, so it is not used.)
const keepalive = WeakKeyDict{Any, Vector{UInt8}}()

registerbacking( ■ :: Vector{UInt8}, handle :: LayoutHandle ) = ( @lock handle.lock handle.backing[■] = nothing; nothing )
registerbacking( :: Vector{UInt8}, :: Nothing ) = nothing

pinarray( flat :: Array, ■ :: Vector{UInt8}, :: Nothing ) = ( keepalive[flat.ref.mem] = ■; nothing )
pinarray( :: Array, :: Vector{UInt8}, :: LayoutHandle ) = nothing

"""
    release_all!()

Deprecated and a no-op.  Backing memory of arrays created without a `LayoutHandle` is now managed
by the garbage collector, so there is nothing to release.  Use `withlayout` or an explicit
`LayoutHandle` if deterministic release is required.
"""
function release_all!()
    Base.depwarn( "release_all!() is deprecated and a no-op: memory created without a handle is managed by the garbage collector", :release_all!; force = true )
    return nothing
end

"""
    withlayout( f :: Function )

Run `f` in a scope with a fresh `LayoutHandle`.  All calls to `layout`, `layout!`, and
`deeplayout` inside `f` (that do not pass an explicit `handle`) will use this handle.
The backing memory is released when `f` returns (or throws).

# Example
```julia
result = withlayout() do
    x = deeplayout( a )
    y = deeplayout( b )
    compute( x, y )
end
```

!!! warning
    Arrays created inside the scope point into memory that is freed when the scope exits.  Using
    such an array afterwards is undefined behavior (use-after-free).  Do not let them escape the
    block; return plain results (numbers, copies) instead.
"""
function withlayout( f :: Function )
    h = LayoutHandle()
    try
        return with( f, layoutscope => h )
    finally
        release!( h )
    end
end

resolvehandle( handle :: LayoutHandle ) = handle
resolvehandle( :: Nothing ) = layoutscope[]

# ---------------------------------------------------------------------------------------------------
# Which arrays get moved into the block
# ---------------------------------------------------------------------------------------------------

"""
    transferable( :: Type{A} ) -> Bool

Trait declaring that arrays of type `A` can be moved into a contiguous block and rebuilt via
`newarrayofsametype`.  Only `Array` is transferable by default; the package extensions add
`OffsetArray`, `KeyedArray`, and `NamedDimsArray` (whenever their parent is transferable).
Any other array type (ranges, views, `BitArray`, static arrays, ...) is passed through untouched.
"""
transferable( :: Type ) = false
transferable( :: Type{<:Array} ) = true

# An array is packable when it is transferable, has an isbits element type of nonzero size, and is nonempty.
packable( x ) = false
packable( x :: AbstractArray{T} ) where T = transferable( typeof( x ) ) && isbitstype( T ) && sizeof( T ) > 0 && length( x ) > 0

# Upper bound on the bytes a packable array needs in the block: its data rounded up to `alignment`,
# plus room for the padding that guarantees the element type's natural alignment.
blocksize( x, alignment ) = packable( x ) ? alignup( sizeof( eltype( x ) ) * length( x ), alignment ) + Base.datatype_alignment( eltype( x ) ) : 0

"""
    newarrayofsametype( old, newdata )

Function *for internal use only* that creates a new array wrapper of the same type and structure as
`old`, but wrapping `newdata`.  This function recursively peels off array wrappers (like
`KeyedArray`, `OffsetArray`, `NamedDimsArray`) to reach the underlying data, replaces it with
`newdata`, and then re-wraps it.

# Supported Wrappers
- `KeyedArray`: preserves axis keys
- `OffsetArray`: preserves offsets
- `NamedDimsArray`: preserves dimension names
"""
newarrayofsametype( :: Any, newdata ) = newdata

"""
    underlying( x )

Function *for internal use only*: the plain `Array` beneath a stack of transferable wrappers
( `pointer` is defined on it; it need not be on the wrappers ).  Extensions add methods that
unwrap their type.
"""
underlying( x ) = x

# ---------------------------------------------------------------------------------------------------
# The block and the bookkeeping shared by the size and transfer passes
# ---------------------------------------------------------------------------------------------------

mutable struct Block
    ■                     :: Vector{UInt8}
    offset                :: Int
    const alignment       :: Int
    const handle          :: Union{LayoutHandle, Nothing}
    const exclude
    const livedangerously :: Bool
    const cache           :: Union{IdDict{Any, Any}, Nothing}      # original object => laid-out object
    const seen            :: Union{IdSet{Any}, Nothing}            # arrays already counted in the size pass
    const stack           :: Vector{Any}                           # objects currently being traversed
end

function Block( exclude, alignment :: Int, handle, livedangerously :: Bool )
    alignment ≥ 1 || throw( ArgumentError( "alignment must be at least 1, got $alignment" ) )
    return Block( UInt8[], 0, alignment, resolvehandle( handle ), exclude, livedangerously, livedangerously ? nothing : IdDict{Any, Any}(), livedangerously ? nothing : IdSet{Any}(), Any[] )
end

function allocate!( b :: Block, totalsize :: Int )
    b.■ = Vector{UInt8}( undef, totalsize + b.alignment )
    ▶raw = UInt( pointer( b.■ ) )
    b.offset = Int( alignup( ▶raw, b.alignment ) - ▶raw )
    return b
end

finish!( b :: Block ) = ( registerbacking( b.■, b.handle ); nothing )

excluded( k, b :: Block ) = k ∈ b.exclude

# Run `f()` with `x` on the traversal stack, throwing if `x` is already there (a cycle).
function withcycle( f, x, b :: Block )
    ( b.livedangerously || !ismutable( x ) ) && return f()
    any( y -> y ≡ x, b.stack ) && throw( ArgumentError( "Cyclic dependency detected: $(typeof( x ))" ) )
    push!( b.stack, x )
    try
        return f()
    finally
        pop!( b.stack )
    end
end

# Return the cached replacement for `x` if it was already laid out, otherwise compute and cache it.
# This preserves sharing: an array referenced from two places is moved once and both places see it.
function cached( f, x, b :: Block )
    isnothing( b.cache ) && return f()
    haskey( b.cache, x ) && return b.cache[x]
    y = f()
    b.cache[x] = y
    return y
end

# Count an array's data once in the size and statistics passes, even if it is referenced from
# several places or through several wrappers.
function sizeonce( f, x, b :: Block, default = 0 )
    isnothing( b.seen ) && return f()
    data = underlying( x )
    data ∈ b.seen && return default
    push!( b.seen, data )
    return f()
end

# Copy the packable array `x` into the block at the next suitably aligned position, advance the
# block's offset, and return an array of the same type wrapping that memory.  Non-packable objects
# are returned unchanged.
function pack( x, b :: Block )
    packable( x ) || return x
    data = underlying( x )                      # the cache is keyed on the data, so two wrappers over one array stay one array
    dest = cached( data, b ) do
        T = eltype( x )
        ■ = b.■
        GC.@preserve ■ begin
            # pad so the data starts at the element type's natural alignment
            natural = Base.datatype_alignment( T )
            addr = UInt( pointer( ■ ) ) + b.offset
            b.offset += Int( ( natural - addr % natural ) % natural )
            ▶ = pointer( ■ ) + b.offset
            @debug styled"moving {yellow:$( div( length( x ) * sizeof( T ), 1024 ) )kb} from {magenta:$(pointer( x ))} to {green:$▶}"
            flat = unsafe_wrap( Array, Ptr{T}( ▶ ), length( x ); own = false )
            dest = reshape( flat, size( x ) )
        end
        b.offset += alignup( length( x ) * sizeof( T ), b.alignment )
        b.offset ≤ length( ■ ) || error( "internal error: block overflow while packing $(typeof( x ))" )
        copyto!( dest, data )
        pinarray( flat, ■, b.handle )
        dest
    end
    return newarrayofsametype( x, dest )
end

# ---------------------------------------------------------------------------------------------------
# Shallow layout
# ---------------------------------------------------------------------------------------------------

const importantadmonition = """
!!! warning "important implementation details"
    Users should be mindful of the following important implementation details:
    - aligned arrays share a single contiguous memory block
    - resizing any of the arrays (`push!`, `append!`) will break this contiguity for that array (it will be reallocated elsewhere)
    - contiguity is maintained until an array is resized or reassigned
    - please read the documentation
"""

"""
    layout( s; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle = nothing )

`layout` aligns the memory of arrays within the object `s`, whose type should be one of `struct`, `AbstractArray`, or `AbstractDict`

`layout` creates a new instance of `s` (or copy of `s`) where the arrays are stored contiguously in memory.

Only arrays whose type is `transferable` (plain `Array`s, plus the wrappers supported by the package
extensions) with an `isbits` element type are moved; everything else is left as is.

The `alignment` keyword argument specifies the memory alignment in bytes. This is particularly useful for SIMD operations, where aligning data to 16, 32, or 64 bytes can improve performance.

The `livedangerously` keyword argument (default `false`) disables safety checks for:
- Cyclic dependencies (prevents StackOverflow)
- Shared references / aliasing (with the checks on, an array referenced from several places is moved once and stays shared; with them off it is duplicated)
Enable this only if you are certain your data is acyclic and you accept duplication of shared arrays.

Excluded items (by field name or dictionary key) are shared with the original, not packed.

The `handle` keyword argument selects a `LayoutHandle` for deterministic release of the backing
memory; see `LayoutHandle` and `withlayout`.  Without one, the backing memory is managed by the
garbage collector.

$importantadmonition
"""
function layout( s :: AbstractArray{T}; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing ) where T
    isbitstype( T ) && return s                 # nothing inside to move
    b = Block( exclude, alignment, handle, livedangerously )
    allocate!( b, sum( k -> excluded( k, b ) ? 0 : sizeonce( () -> blocksize( s[k], alignment ), s[k], b ), eachindex( s ); init = 0 ) )
    result = similar( s )
    for k ∈ eachindex( s )
        result[k] = excluded( k, b ) ? s[k] : pack( s[k], b )
    end
    finish!( b )
    return result
end

function layout( s :: T; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing ) where T
    isbitstype( T ) && return s
    if !isstructtype( T ) || isempty( fieldnames( T ) )
        @warn styled"can only do {green:structs}, {green:array types}, and {green:dicts} at this point; {red:$T} is none of the above"
        return s
    end
    b = Block( exclude, alignment, handle, livedangerously )
    allocate!( b, sum( k -> excluded( k, b ) ? 0 : sizeonce( () -> blocksize( getfield( s, k ), alignment ), getfield( s, k ), b ), fieldnames( T ); init = 0 ) )
    result = rebuild( s, ( excluded( k, b ) ? getfield( s, k ) : pack( getfield( s, k ), b ) for k ∈ fieldnames( T ) ) )
    finish!( b )
    return result
end

"""
    layout!( s :: AbstractDict; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle = nothing )

In-place version of `layout` for `AbstractDict`.

`layout!` modifies `s` such that its values are stored contiguously in memory.

The `alignment` keyword argument specifies the memory alignment in bytes. This is particularly useful for SIMD operations, where aligning data to 16, 32, or 64 bytes can improve performance.

The `livedangerously` keyword argument (default `false`) disables safety checks for:
- Cyclic dependencies (prevents StackOverflow)
- Shared references / aliasing (with the checks on, an array referenced from several places is moved once and stays shared; with them off it is duplicated)
Enable this only if you are certain your data is acyclic and you accept duplication of shared arrays.

Excluded keys are left untouched.

$importantadmonition
"""
function layout!( s :: AbstractDict; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing )
    b = Block( exclude, alignment, handle, livedangerously )
    ks = [ k for k ∈ keys( s ) if !excluded( k, b ) ]
    allocate!( b, sum( k -> sizeonce( () -> blocksize( s[k], alignment ), s[k], b ), ks; init = 0 ) )
    for k ∈ ks
        s[k] = pack( s[k], b )
    end
    finish!( b )
    return s
end

layout( s :: AbstractDict; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing ) = layout!( copy( s ); exclude = exclude, alignment = alignment, livedangerously = livedangerously, handle = handle )

# Rebuild a struct of type `T` from an iterable of new field values, with an informative error if the
# constructor rejects them (e.g. a field whose declared type does not match the laid-out array).
function rebuild( s :: T, fields ) where T
    values = collect( Any, fields )
    try
        return constructorof( T )( values... )
    catch e
        throw( ArgumentError( "could not rebuild a $T from its laid-out fields ($(sprint( showerror, e ))); exclude the offending field via `exclude`" ) )
    end
end

# ---------------------------------------------------------------------------------------------------
# Deep layout
# ---------------------------------------------------------------------------------------------------

# Types that are never traversed.
const Leaf = Union{AbstractString, Symbol, Number, Function, Module, IO, Type, Regex, Task, Exception}

# Containers whose *elements* are traversed by deeplayout (as opposed to being packed as a whole).
traversable( x :: AbstractArray ) = !isbitstype( eltype( x ) ) && transferable( typeof( x ) )

deepsize( :: Leaf, :: Block ) = 0

function deepsize( x :: AbstractArray, b :: Block )
    packable( x ) && return sizeonce( () -> blocksize( x, b.alignment ), x, b )
    traversable( x ) || return 0
    withcycle( x, b ) do
        sum( el -> deepsize( el, b ), x; init = 0 )
    end
end

function deepsize( x :: AbstractDict, b :: Block )
    withcycle( x, b ) do
        sum( ( deepsize( x[k], b ) for k ∈ keys( x ) if !excluded( k, b ) ); init = 0 )
    end
end

function deepsize( x :: T, b :: Block ) where T
    ( isbitstype( T ) || !isstructtype( T ) ) && return 0
    withcycle( x, b ) do
        sum( ( deepsize( getfield( x, k ), b ) for k ∈ fieldnames( T ) if !excluded( k, b ) ); init = 0 )
    end
end

deeptransfer( x :: Leaf, :: Block ) = x

function deeptransfer( x :: AbstractArray, b :: Block )
    packable( x ) && return pack( x, b )
    traversable( x ) || return x
    cached( x, b ) do
        withcycle( x, b ) do
            y = similar( x )
            for i ∈ eachindex( x )
                y[i] = deeptransfer( x[i], b )
            end
            y
        end
    end
end

function deeptransfer( x :: AbstractDict, b :: Block )
    cached( x, b ) do
        withcycle( x, b ) do
            D = copy( x )
            for k ∈ keys( D )
                D[k] = excluded( k, b ) ? deepcopy( D[k] ) : deeptransfer( D[k], b )
            end
            D
        end
    end
end

function deeptransfer( x :: T, b :: Block ) where T
    ( isbitstype( T ) || !isstructtype( T ) ) && return x
    build = () -> withcycle( x, b ) do
        rebuild( x, ( excluded( k, b ) ? deepcopy( getfield( x, k ) ) : deeptransfer( getfield( x, k ), b ) for k ∈ fieldnames( T ) ) )
    end
    return ismutable( x ) ? cached( build, x, b ) : build()
end

"""
    deeplayout( x; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle = nothing )

`deeplayout` recursively aligns memory of arrays within `x` and its fields

Unlike `layout`, which only aligns the immediate fields/elements of `x`, `deeplayout` traverses the structure recursively.  In other words, `deeplayout` is to `layout` what `deepcopy` is to `copy`.

Only arrays whose type is `transferable` (plain `Array`s, plus the wrappers supported by the package
extensions) with an `isbits` element type are moved; everything else is left as is.

The `alignment` keyword argument specifies the memory alignment in bytes. This is particularly useful for SIMD operations, where aligning data to 16, 32, or 64 bytes can improve performance.

The `livedangerously` keyword argument (default `false`) disables safety checks for:
- cyclic dependencies (prevents StackOverflow)
- shared references / aliasing (with the checks on, an object referenced from several places is laid out once and stays shared, as with `deepcopy`; with them off it is duplicated)
Enable this only if you are certain your data is acyclic and you accept duplication of shared arrays.

Excluded items (by field name or dictionary key, at any depth) are deep-copied rather than packed.

The `handle` keyword argument selects a `LayoutHandle` for deterministic release of the backing
memory; see `LayoutHandle` and `withlayout`.  Without one, the backing memory is managed by the
garbage collector.

$importantadmonition
"""
function deeplayout( x; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing )
    b = Block( exclude, alignment, handle, livedangerously )
    sz = deepsize( x, b )
    sz == 0 && return deepcopy( x )
    allocate!( b, sz )
    result = deeptransfer( x, b )
    finish!( b )
    return result
end
