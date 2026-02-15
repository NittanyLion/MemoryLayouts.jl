

alignup( x, a ) = cld( x, a ) * a

"""
    LayoutHandle

A handle that tracks the backing memory for arrays created by `layout`, `layout!`, or `deeplayout`.
Call `release!(handle)` to free the backing memory when the laid-out arrays are no longer needed.

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

If no handle is passed and no `withlayout` scope is active, a global store is used instead
(freed by `release_all!()`).
"""
mutable struct LayoutHandle
    backing  :: IdDict{Vector{UInt8}, Nothing}
    memories :: Vector{Any}
    LayoutHandle() = new( IdDict{Vector{UInt8}, Nothing}(), Any[] )
end

"""
    release!( handle :: LayoutHandle )

Free the backing memory tracked by this handle.
Only call this when you are certain no arrays associated with this handle are still in use.
"""
function release!( handle :: LayoutHandle )
    empty!( handle.backing )
    empty!( handle.memories )
    return nothing
end

# Global stores — used when no LayoutHandle is provided.
const _global_handle = LayoutHandle()
const _layout_scope = ScopedValue( _global_handle )

function _register_backing( ■ :: Vector{UInt8}, store :: IdDict{Vector{UInt8}, Nothing} )
    store[■] = nothing
end

function _pin_memory( arr, memories :: Vector{Any} )
    push!( memories, arr.ref.mem )
end

"""
    release_all!()

Free all backing buffers retained by `layout`, `layout!`, and `deeplayout` that were
created **without** a `LayoutHandle`.  Only call this when you are certain no arrays
created by these functions (without a handle) are still in use.
"""
function release_all!()
    release!( _global_handle )
end

"""
    withlayout( f :: Function )

Run `f` in a scope with a fresh `LayoutHandle`.  All calls to `layout`, `layout!`, and
`deeplayout` inside `f` (that do not pass an explicit `handle`) will use this handle.
The backing memory is released automatically when `f` returns (or throws).

# Example
```julia
result = withlayout() do
    x = deeplayout( a )
    y = deeplayout( b )
    compute( x, y )
end
```

!!! warning
    Arrays created inside the scope are **invalidated** when the scope exits.
    Do not let them escape the block.
"""
function withlayout( f :: Function )
    h = LayoutHandle()
    try
        return with( f, _layout_scope => h )
    finally
        release!( h )
    end
end

# Helpers for cycle detection
function checkcycle( x, stack )
    ismutable( x ) || return false
    any( y -> y ≡ x, stack ) && throw( ArgumentError( "Cyclic dependency detected: $(typeof( x ))" ) )
    push!( stack, x )
    return true
end

popcycle( x, stack, pushed ) = pushed ? pop!(stack) : nothing

function checkaliasingwarn( x, visited )
    ( isbitstype( typeof( x ) ) || isnothing( x ) ) && return nothing
    x ∈ visited && @warn styled"Shared reference detected for object of type {yellow:$(typeof(x))}. Object will be {red:duplicated} in the new layout." maxlog=3 
    push!( visited, x )
    return nothing
end


computesize( :: Any; kwargs... ) = 0
computesize( x :: AbstractArray; alignment :: Int = 1 ) = isbitstype( eltype( x ) ) ? alignup( sizeof( eltype( x ) ) * length( x ), alignment ) + sizeof(eltype(x)) : 0


const importantadmonition = """
!!! warning "important implementation details"
    Users should be mindful of the following important implementation details:
    - aligned arrays share a single contiguous memory block
    - resizing any of the arrays (`push!`, `append!`) will break this contiguity for that array (it will be reallocated elsewhere)
    - contiguity is maintained until an array is resized or reassigned
    - please read the documentation
"""





"""
    newarrayofsametype(old, newdata)

Function *for internal use only* that creates a new array wrapper of the same type and structure as `old`, but wrapping `newdata`.  This function recursively peels off array wrappers (like `KeyedArray`, `OffsetArray`, `NamedDimsArray`) to reach the underlying data, replaces it with `newdata`, and then re-wraps it. 

# Supported Wrappers
- `KeyedArray`: preserves axis keys
- `OffsetArray`: preserves offsets
- `NamedDimsArray`: preserves dimension names
"""
newarrayofsametype( :: Any, newdata ) = newdata



"""
    transferadvance( x, TT, ■, offset, alignment )

The function `transferadvance` is *for internal use only*.  It assigns memory from the memory block and then advances the `offset`.
Returns the new array (or the original if no transfer happened).
"""
transferadvance( x, TT, ■ :: Vector{UInt8}, :: Ref{Int}, :: Int, visited :: Union{IdSet{Any}, Nothing}, livedangerously :: Bool, :: Vector{Any} ) = x


function transferadvance( x, TT :: Type{𝒯}, ■ :: Vector{UInt8}, offset :: Ref{Int}, alignment :: Int, visited :: Union{IdSet{Any}, Nothing}, livedangerously :: Bool, memories :: Vector{Any} ) where 𝒯 
    # this method is where the hard work is done
    isbitstype( 𝒯 ) || return x               # don't do anything for arrays of nonisbits types
    x isa AbstractArray || return x           # don't bother with nonarrays
    length( x ) == 0 && return x              # don't try to align arrays of length zero

    !livedangerously && checkaliasingwarn(x, visited)

    # Align the offset to the element type requirement
    # We must ensure that (pointer(■) + offset[]) % sizeof(𝒯) == 0
    GC.@preserve ■ begin
        currentaddr = UInt(pointer(■)) + UInt(offset[])
        pad = (sizeof(𝒯) - (currentaddr % sizeof(𝒯))) % sizeof(𝒯)
        offset[] += pad

        ▶ = pointer( ■ ) + offset[]               # set the relevant place in memory
        @debug styled"""moving {yellow:$( div( length( x ) * sizeof( 𝒯 ), 1024 ) )kb} from {magenta:$(pointer( x ))} to {green:$▶}"""
        flat = unsafe_wrap( Array, Ptr{𝒯}( ▶ ), length( x ); own = false )
        _pin_memory( flat, memories )
        dest = reshape( flat, size( x ) )
    end
    offset[] += alignup( length( x ) * sizeof( 𝒯 ), alignment )        # move the offset counter
    copyto!( dest, x )                                                 # move the data
    return newarrayofsametype( x, dest )                               # return new array
end


transferadvance( x, ■ :: Vector{UInt8}, offset :: Ref{Int}, alignment :: Int, visited :: Union{IdSet{Any}, Nothing}, livedangerously :: Bool, memories :: Vector{Any} ) = x isa AbstractArray ? transferadvance( x, eltype( x ), ■, offset, alignment, visited, livedangerously, memories ) : x





"""
    layout(s; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false)

`layout` aligns the memory of arrays within the object `s`, whose type should be one of `struct`, `AbstractArray`, or `AbstractDict`

`layout` creates a new instance of `s` (or copy of `s`) where the arrays are stored contiguously in memory.

The `alignment` keyword argument specifies the memory alignment in bytes. This is particularly useful for SIMD operations, where aligning data to 16, 32, or 64 bytes can improve performance.

The `livedangerously` keyword argument (default `false`) disables safety checks for:
- Cyclic dependencies (prevents StackOverflow)
- Shared references / aliasing (prevents silent duplication)
Enable this only if you are certain your data is acyclic and you accept duplication of shared arrays.

Excluded items are preserved as-is (or deep-copied in some contexts) but not packed into the contiguous memory block.

$importantadmonition
"""
function layout( s :: AbstractArray{T}; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing ) where T
    isbitstype( T ) && return s                 # don't do anything for objects that are not isbits
    h = something( handle, _layout_scope[] )
    fn = eachindex( s )                         #
    fnalign = filter( k -> k ∉ exclude, fn )    # omit the fields that are to be excluded
    totalsize = sum( k -> computesize( s[k]; alignment = alignment ), fnalign )
    ■ = Vector{UInt8}( undef, totalsize + alignment )
    ▶raw = pointer( ■ )
    ▶aligned = reinterpret( Ptr{Cvoid}, alignup( UInt( ▶raw ), alignment ) )
    startoffset = Int( ▶aligned - ▶raw )
    offset = Ref( startoffset )
    visited = livedangerously ? nothing : IdSet{Any}()
    result = map!( k -> k ∈ fnalign ? transferadvance( s[k], ■, offset, alignment, visited, livedangerously, h.memories ) : s[k], similar( s ), fn )
    _register_backing( ■, h.backing )
    return result
end

function layout( s :: T; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing ) where T
    isbitstype( T ) && return s 
    if !isstructtype( T ) || isempty( fieldnames( T ) )
        @warn styled"can only do {green:structs}, {green:array types}, and {green:dicts} at this point; {red:$T} is none of the above" 
        return s 
    end
    h = something( handle, _layout_scope[] )
    fn = fieldnames( T )
    fnalign = filter( k -> k ∉ exclude, fn )
    totalsize = sum( k -> computesize( getfield( s, k ); alignment = alignment ), fnalign )
    ■ = Vector{UInt8}( undef, totalsize + alignment )
    ▶raw = pointer( ■ )
    ▶aligned = reinterpret( Ptr{Cvoid}, alignup( UInt( ▶raw ), alignment ) )
    startoffset = Int( ▶aligned - ▶raw )
    offset = Ref( startoffset )
    visited = livedangerously ? nothing : IdSet{Any}()
    result = constructorof(T)( ( k ∈ fnalign ? transferadvance( getfield( s, k ), ■, offset, alignment, visited, livedangerously, h.memories ) : getfield( s, k ) for k ∈ fn )... )
    _register_backing( ■, h.backing )
    return result
end


"""
    layout!( s :: AbstractDict; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false )

In-place version of `layout` for `AbstractDict`.

`layout!` modifies `s` such that its values are stored contiguously in memory.

The `alignment` keyword argument specifies the memory alignment in bytes. This is particularly useful for SIMD operations, where aligning data to 16, 32, or 64 bytes can improve performance.

The `livedangerously` keyword argument (default `false`) disables safety checks for:
- Cyclic dependencies (prevents StackOverflow)
- Shared references / aliasing (prevents silent duplication)
Enable this only if you are certain your data is acyclic and you accept duplication of shared arrays.

Excluded items are preserved as-is (or deep-copied in some contexts) but not packed into the contiguous memory block.

$importantadmonition
"""
function layout!( s :: AbstractDict; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing )
    h = something( handle, _layout_scope[] )
    keysalign = filter( k -> k ∉ exclude, keys(s) )
    totalsize = sum( k -> computesize( s[k]; alignment = alignment ), keysalign )
    ■ = Vector{UInt8}( undef, totalsize + alignment )
    ▶raw = pointer( ■ )
    ▶aligned = reinterpret( Ptr{Cvoid}, alignup( UInt( ▶raw ), alignment ) )
    startoffset = Int( ▶aligned - ▶raw )
    offset = Ref( startoffset )
    visited = livedangerously ? nothing : IdSet{Any}()
    foreach( k -> s[k] = transferadvance( s[k], ■, offset, alignment, visited, livedangerously, h.memories ), keysalign )
    _register_backing( ■, h.backing )
    return s
end

layout( s :: AbstractDict; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing ) = layout!( copy( s ); exclude = exclude, alignment = alignment, livedangerously = livedangerously, handle = handle )


computesizedeep( x :: Union{AbstractString, Symbol, Number, Function, Module, IO, Type, Regex, Task, Exception}, ■ :: Vector{UInt8}, offset :: Ref{Int}; kwargs... ) = 0

computesizedeep( x :: AbstractArray; stack = Vector{Any}(), exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false ) = isbitstype( eltype( x ) ) ? alignup( sizeof( eltype( x ) ) * length( x ), alignment ) + sizeof(eltype(x)) : begin
    pushed = !livedangerously && checkcycle(x, stack)
    try
        sum( el -> computesizedeep( el; stack = stack, exclude = exclude, alignment = alignment, livedangerously = livedangerously ), x; init=0 )
    finally
        popcycle(x, stack, pushed)
    end
end

function computesizedeep( x :: AbstractDict; stack = Vector{Any}(), exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false )
    pushed = !livedangerously && checkcycle(x, stack)
    try
        sum( k ∈ exclude ? 0 : computesizedeep( x[k]; stack = stack, exclude = exclude, alignment = alignment, livedangerously = livedangerously ) for k ∈ keys(x); init=0 )
    finally
        popcycle( x, stack, pushed )
    end
end

function computesizedeep( x :: T; stack = Vector{Any}(), exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false ) where T 
    isbitstype( T ) || !isstructtype( T ) ?  0 : begin
        pushed = !livedangerously && checkcycle( x, stack )
        try
            sum( k ∈ exclude ? 0 : computesizedeep( getfield( x, k ); stack = stack, exclude = exclude, alignment = alignment, livedangerously = livedangerously ) for k ∈ fieldnames( T ); init=0 )
        finally
            popcycle(x, stack, pushed)
        end
    end
end


function deeptransfer( x :: AbstractArray{T}, ■ :: Vector{UInt8}, offset :: Ref{Int}; stack = Vector{Any}(), visited = IdSet{Any}(), exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, memories :: Vector{Any} = _layout_scope[].memories ) where T
    if !isbitstype(T)
        pushed = !livedangerously && checkcycle(x, stack)
        !livedangerously && checkaliasingwarn(x, visited)
        try
            return map( el -> deeptransfer( el, ■, offset; stack = stack, visited = visited, exclude = exclude, alignment = alignment, livedangerously = livedangerously, memories = memories ), x )
        finally
            popcycle( x, stack, pushed )
        end
    end
    sz = sizeof( T ) * length( x )
    sz == 0 && return x
    # Align the offset to the element type requirement
    GC.@preserve ■ begin
        currentaddr = UInt( pointer( ■ ) ) + offset[]
        pad = ( sizeof(T) - ( currentaddr % sizeof( T ) ) ) % sizeof( T )
        offset[] += pad
        ▶now = pointer( ■ ) + offset[]
        flat = unsafe_wrap( Array, Ptr{T}( ▶now ), length( x ); own = false )
        _pin_memory( flat, memories )
        dest = reshape( flat, size( x ) )
    end
    offset[] += alignup( sz, alignment )
    copyto!( dest, x )
    return newarrayofsametype( x, dest )
end

function deeptransfer( x :: AbstractDict, ■ :: Vector{UInt8}, offset :: Ref{Int}; stack = Vector{Any}(), visited = IdSet{Any}(), exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, memories :: Vector{Any} = _layout_scope[].memories )
    pushed = livedangerously || checkcycle( x, stack )
    livedangerously || checkaliasingwarn( x, visited )
    try
        D = copy( x )
        foreach( k -> D[k] = deeptransfer( D[k], ■, offset; stack = stack, visited = visited, exclude = exclude, alignment = alignment, livedangerously = livedangerously, memories = memories ), filter( k -> k ∉ exclude, keys(D) ) )
        return D
    finally
        popcycle( x, stack, pushed )
    end
end

deeptransfer( x :: Union{AbstractString, Symbol, Number, Function, Module, IO, Type, Regex, Task, Exception}, ■ :: Vector{UInt8}, offset :: Ref{Int}; kwargs... ) = x

function deeptransfer( x :: T, ■ :: Vector{UInt8}, offset :: Ref{Int}; stack = Vector{Any}(), visited = IdSet{Any}(), exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, memories :: Vector{Any} = _layout_scope[].memories ) where T
    ( isbitstype( T ) || !isstructtype( T ) ) && return x
    pushed = !livedangerously && checkcycle( x, stack )
    !livedangerously && checkaliasingwarn( x, visited )
    try
        return constructorof(T)( ( k ∈ exclude ? deepcopy( getfield( x, k ) ) : deeptransfer( getfield( x, k ), ■, offset; stack = stack, visited = visited, exclude = exclude, alignment = alignment, livedangerously = livedangerously, memories = memories ) for k ∈ fieldnames( T ) )... )
    catch
        println( "I choked on a field of type $T; please exclude fields with such types from the layout procedure" )
    finally
        popcycle( x, stack, pushed )
    end
end

"""
    deeplayout( x; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false )

`deeplayout` recursively aligns memory of arrays within `x` and its fields

Unlike `layout`, which only aligns the immediate fields/elements of `x`, `deeplayout` traverses the structure recursively.  In other words, `deeplayout` is to `layout` what `deepcopy` is to `copy`.

The `alignment` keyword argument specifies the memory alignment in bytes. This is particularly useful for SIMD operations, where aligning data to 16, 32, or 64 bytes can improve performance.

The `livedangerously` keyword argument (default `false`) disables safety checks for:
- cyclic dependencies (prevents StackOverflow)
- shared references / aliasing (prevents silent duplication)
Enable this only if you are certain your data is acyclic and you accept duplication of shared arrays.

Excluded items are preserved as-is (or deep-copied in some contexts) but not packed into the contiguous memory block.

$importantadmonition
"""
function deeplayout( x; exclude = Symbol[], alignment :: Int = 1, livedangerously :: Bool = false, handle :: Union{LayoutHandle, Nothing} = nothing )
    sz = computesizedeep( x; exclude = exclude, alignment = alignment, livedangerously = livedangerously )
    sz == 0 && return deepcopy( x )
    h = something( handle, _layout_scope[] )
    ■ = Vector{UInt8}( undef, sz + alignment )
    
    ▶raw = pointer( ■ )
    ▶aligned = reinterpret( Ptr{Cvoid}, alignup( UInt( ▶raw ), alignment ) )
    startoffset = Int( ▶aligned - ▶raw )
    offset = Ref( startoffset )
    
    result = deeptransfer( x, ■, offset; exclude = exclude, alignment = alignment, livedangerously = livedangerously, memories = h.memories )
    _register_backing( ■, h.backing )
    return result
end




