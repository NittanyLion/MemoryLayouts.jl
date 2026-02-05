

alignup( x, a ) = cld( x, a ) * a

computesize( :: Any; kwargs... ) = 0
computesize( x :: AbstractArray; alignment::Int=1 ) = isbitstype( eltype( x ) ) ? alignup( sizeof( eltype( x ) ) * length( x ), alignment ) : 0

const importantadmonition = """
!!! warning "important implementation details"
    Users should be mindful of the following important implementation details:
    - aligned arrays share a single contiguous memory block
    - resizing any of the arrays (`push!`, `append!`) will break this contiguity for that array (it will be reallocated elsewhere)
    - Contiguity is maintained until an array is resized or reassigned
"""





"""
    newarrayofsametype(old, newdata)

Function *for internal use only* that creates a new array wrapper of the same type and structure as `old`, but wrapping `newdata`.  This function recursively peels off array wrappers (like `KeyedArray`, `OffsetArray`, `NamedDimsArray`) to reach the underlying data, replaces it with `newdata`, and then re-wraps it. 

# Supported Wrappers
- `KeyedArray`: preserves axis keys
- `OffsetArray`: preserves offsets
- `NamedDimsArray`: preserves dimension names
"""
newarrayofsametype( ::Any, newdata ) = newdata



"""
    transferadvance( x, TT, ■, offset, alignment )

The function `transferadvance` is *for internal use only*.  It assigns memory from the memory block and then advances the `offset`.
Returns the new array (or the original if no transfer happened).
"""
transferadvance( x, TT, ■ :: Vector{UInt8}, :: Ref{Int}, :: Int ) = x


function transferadvance( x, TT :: Type{𝒯}, ■ :: Vector{UInt8}, offset :: Ref{Int}, alignment :: Int ) where 𝒯 
    # this method is where the hard work is done
    isbitstype( 𝒯 ) || return x               # don't do anything for arrays of nonisbits types
    x isa AbstractArray || return x           # don't bother with nonarrays
    length( x ) == 0 && return x              # don't try to align arrays of length zero
    ▶ = pointer( ■ ) + offset[]               # set the relevant place in memory
    # now grab the memory block that I want, assert ownership if it's the first block, and then give it the correct shape
    dest = reshape( unsafe_wrap( Array, Ptr{𝒯}( ▶ ), length( x ); own = false ), size( x ) )  
    finalizer( _ -> ( ■; nothing ), dest )
    offset[] += alignup( length( x ) * sizeof( 𝒯 ), alignment )        # move the offset counter
    copyto!( dest, x )                                                 # move the data
    return newarrayofsametype( x, dest )                               # return new array
end


function transferadvance( x, ■ :: Vector{UInt8}, offset :: Ref{Int}, alignment :: Int )
    x isa AbstractArray || return x
    return transferadvance( x, eltype( x ), ■, offset, alignment )
end





"""
    alignmem(s; exclude = Symbol[], alignment::Int=1)

`alignmem` aligns the memory of arrays within the object `s`, whose type should be one of `struct`, `AbstractArray`, or `AbstractDict`

`alignmem` creates a new instance of `s` (or copy of `s`) where the arrays are stored contiguously in memory.

The `alignment` keyword argument specifies the memory alignment in bytes. This is particularly useful for SIMD operations, where aligning data to 16, 32, or 64 bytes can improve performance.

Excluded items are preserved as-is (or deep-copied in some contexts) but not packed into the contiguous memory block.

$importantadmonition
"""
function alignmem( s :: AbstractArray{T}; exclude = Symbol[], alignment :: Int = 1 ) where T
    isbitstype( T ) && return s                 # don't do anything for objects that are not isbits
    fn = eachindex( s )                         #
    fnalign = filter( k -> k ∉ exclude, fn )    # omit the fields that are to be excluded
    totalsize = sum( k -> computesize( s[k]; alignment = alignment ), fnalign )
    ■ = Vector{UInt8}( undef, totalsize + alignment )
    ▶raw = pointer( ■ )
    ▶aligned = reinterpret( Ptr{Cvoid}, alignup( UInt( ▶raw ), alignment ) )
    startoffset = Int( ▶aligned - ▶raw )
    offset = Ref( startoffset )
    
    res = similar( s )
    for k ∈ fn
        if k ∈ fnalign
            res[k] = transferadvance( s[k], ■, offset, alignment )
        else
            res[k] = s[k]
        end
    end
    return res
end

function alignmem( s :: T; exclude = Symbol[], alignment :: Int = 1 ) where T
    isbitstype( T ) && return s 
    if !isstructtype( T ) 
        @warn styled"can only do {green:structs}, {green:array types}, and {green:dicts} at this point; {red:$T} is none of the above" 
        return s 
    end
    fn = fieldnames( T )
    fnalign = filter( k -> k ∉ exclude, fn )
    totalsize = sum( k -> computesize( getfield( s, k ); alignment = alignment ), fnalign )
    ■ = Vector{UInt8}( undef, totalsize + alignment )
    ▶raw = pointer( ■ )
    ▶aligned = reinterpret( Ptr{Cvoid}, alignup( UInt( ▶raw ), alignment ) )
    startoffset = Int( ▶aligned - ▶raw )
    offset = Ref( startoffset )
    return constructorof(T)( ( k ∈ fnalign ? transferadvance( getfield( s, k ), ■, offset, alignment ) : getfield( s, k ) for k ∈ fn )... )
end


function alignmem( s :: AbstractDict; exclude = Symbol[], alignment::Int=1 )
    D = copy( s )
    keysalign = filter( k -> k ∉ exclude, keys(D) )
    totalsize = sum( k -> computesize( D[k]; alignment=alignment ), keysalign )
    ■ = Vector{UInt8}( undef, totalsize + alignment )
    ▶raw = pointer( ■ )
    ▶aligned = reinterpret( Ptr{Cvoid}, alignup( UInt( ▶raw ), alignment ) )
    startoffset = Int( ▶aligned - ▶raw )
    offset = Ref( startoffset )
    for k ∈ keysalign
        D[k] = transferadvance( D[k], ■, offset, alignment )
    end
    return D
end

computesizedeep( x :: AbstractArray; exclude = Symbol[], alignment :: Int = 1 ) = isbitstype( eltype( x ) ) ? alignup( sizeof( eltype( x ) ) * length( x ), alignment ) : sum( el -> computesizedeep( el; exclude = exclude, alignment = alignment ), x )
computesizedeep( x :: T; exclude = Symbol[], alignment::Int=1 ) where T = isbitstype( T ) || !isstructtype( T ) ?  0 :  sum( k ∈ exclude ? 0 : computesizedeep( getfield( x, k ); exclude=exclude, alignment=alignment ) for k ∈ fieldnames( T ) )


function deeptransfer( x :: AbstractArray{T}, ■ :: Vector{UInt8}, offset :: Ref{Int}; exclude = Symbol[], alignment::Int=1 ) where T
    isbitstype( T ) || return map( el -> deeptransfer( el, ■, offset; exclude = exclude, alignment = alignment ), x )
    sz = sizeof( T ) * length( x )
    sz == 0 && return x
    ▶now = pointer( ■ ) + offset[]
    flat = unsafe_wrap( Array, Ptr{T}( ▶now ), length( x ); own = false )
    finalizer(_ -> ( ■; nothing ), flat)
    dest = reshape( flat, size( x ) )
    offset[] += alignup( sz, alignment )
    copyto!( dest, x )
    return newarrayofsametype( x, dest )
end

deeptransfer( x :: T, ■ :: Vector{UInt8}, offset :: Ref{Int}; exclude = Symbol[], alignment :: Int = 1 ) where T =
    isbitstype( T ) || !isstructtype( T ) ? x : constructorof(T)( ( k ∈ exclude ? deepcopy( getfield( x, k ) ) : deeptransfer( getfield( x, k ), ■, offset; exclude=exclude, alignment=alignment ) for k ∈ fieldnames( T ) )... ) 

"""
    deepalignmem( x; exclude = Symbol[], alignment::Int=1 ) 

`deepalignmem` recursively aligns memory of arrays within `x` and its fields

Unlike `alignmem`, which only aligns the immediate fields/elements of `x`, `deepalignmem` traverses the structure recursively.  In other words, `deepalignmem` is to `alignmem` what `deepcopy` is to `copy`.

The `alignment` keyword argument specifies the memory alignment in bytes. This is particularly useful for SIMD operations, where aligning data to 16, 32, or 64 bytes can improve performance.

Excluded items are preserved as-is (or deep-copied in some contexts) but not packed into the contiguous memory block.

$importantadmonition
"""
function deepalignmem( x; exclude = Symbol[], alignment::Int=1 )
    sz = computesizedeep( x; exclude = exclude, alignment=alignment )
    sz == 0 && return deepcopy( x )
    ■ = Vector{UInt8}( undef, sz + alignment )
    
    ▶raw = pointer( ■ )
    ▶aligned = reinterpret( Ptr{Cvoid}, alignup( UInt( ▶raw ), alignment ) )
    startoffset = Int( ▶aligned - ▶raw )
    offset = Ref( startoffset )
    
    return deeptransfer( x, ■, offset; exclude = exclude, alignment=alignment )
end




