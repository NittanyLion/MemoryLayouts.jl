using DataStructures, StyledStrings
# const Collection = Union{AbstractArray, AbstractDict, AbstractSet, Tuple}

export alignmem!, alignmem, deepalignmem

# const SymbolInt = Union{ Symbol, Int }
computesize( :: Any ) = 0
computesize( x :: AbstractArray ) = isbitstype( eltype( x ) ) ? sizeof( eltype( x ) ) * length( x ) : 0



"""
    newarrayofsametype(old, newdata)

Create a new array wrapper of the same type and structure as `old`, but wrapping `newdata`.
This function recursively peels off array wrappers (like `KeyedArray`, `OffsetArray`, `NamedDimsArray`)
to reach the underlying data, replaces it with `newdata`, and then re-wraps it.

# Supported Wrappers
- `KeyedArray`: preserves axis keys.
- `OffsetArray`: preserves offsets.
- `NamedDimsArray`: preserves dimension names.
- `Any`: fallback that returns `newdata` directly (bottom of recursion).
"""
newarrayofsametype( ::Any, newdata ) = newdata




transferadvance!( D :: AbstractDict, x, TT, ▶ :: Ptr, :: Ref{Int} ) = nothing


function transferadvance!( D :: AbstractDict, x, TT :: Type{𝒯}, ▶ :: Ptr, offset :: Ref{Int} ) where 𝒯 <: Number
    @assert D[x] isa AbstractArray
    length( D[x] ) == 0 && return nothing
    ▶now = ▶ + offset[]
    flat = unsafe_wrap( Array, Ptr{𝒯}( ▶now ), length( D[x] ); own = offset[] == 0 )
    dest = reshape( flat, size( D[x] ) )
    offset[] += length( D[x] ) * sizeof( 𝒯 )
    copyto!( dest, D[x] )
    D[x] = newarrayofsametype( D[x], dest )
    return nothing
end


function transferadvance!( D :: AbstractDict, x, ▶ :: Ptr, offset :: Ref{Int} )
    @assert haskey( D, x )
    D[x] isa AbstractArray || return nothing
    return transferadvance!( D, x, eltype( D[x] ), ▶, offset )
end


"""
    alignmem!(D::AbstractDict, X...)

Replaces the arrays stored in dictionary `D` at keys `X` with new arrays that are contiguous in memory.

This function:
1. Calculates the total size needed for all arrays in `X`.
2. Allocates a single block of memory using `Libc.malloc` to hold all the data.
3. Recursively copies the data from the old arrays into this new contiguous block.
4. Replaces `D[x]` with a new array wrapper (preserving type, keys, offsets, etc.) that points to the new memory.

# Arguments
- `D`: The dictionary containing the arrays.
- `X...`: A list of symbols (keys in `D`) identifying which arrays to align.

# Notes
- The first array (with offset 0) takes ownership of the `malloc`'d memory (`own=true`).
- Other arrays point to the same block but do not own it.
- This arrangement is safe as long as the first array is kept alive.
"""
function alignmem!( D :: AbstractDict, X... )
    needed = 0
    for x ∈ X
        @assert haskey( D, x )
        needed += computesize( D[x] )
    end
    ▶ = Base.Libc.malloc( needed )
    offset = Ref(0)
    for x ∈ X
        transferadvance!( D, x, ▶, offset )
    end
    return nothing
end

@info styled"{(fg=white,bg=0x000000),bold:{(fg=0x00ffff):Resizing arrays in structs with aligned memory} will {red:break memory contiguity}: it {italic:can} also be {(fg=0x08FF08,bg=0x000000):unsafe};  (examples are using {(fg=0xfff01f,bg=0x000000):push!} or {(fg=0xfff01f,bg=0x000000):append!}).  Users should implement memory alignment manually in cases in which resizing is desirable.}" 


"""
    alignmem(s; exclude = [])

Align the memory of arrays within structure `s`.

This function creates a new instance of `s` (or copy of `s`) where the arrays are stored contiguously in memory.
It handles `AbstractArray`, `AbstractDict`, and struct types.

# Arguments
- `s`: The object to align (Array, Dict, or Struct).
- `exclude`: A list of keys (for Dicts/Arrays) or field names (for Structs) to exclude from alignment.
           Excluded items are preserved as-is (or deep-copied in some contexts) but not packed into the contiguous memory block.
"""
function alignmem( s :: AbstractArray{T}; exclude = [] ) where T
    isbitstype( T ) && return s
    fn = eachindex( s )
    fnalign = filter( k -> k ∉ exclude, fn )
    D = OrderedDict( k => s[k] for k ∈ fn )
    alignmem!( D, fnalign... )
    res = similar(s)
    for k ∈ fn
        res[k] = D[k]
    end
    return res
end

function alignmem( s :: T; exclude = Symbol[] ) where T
    isbitstype( T ) && return s 
    if !isstructtype( T ) 
        @warn styled"can only {red:struct types} and {red:array types} at this point" maxlog = 1
        return s 
    end
    fn = fieldnames( T )
    fnalign = filter( k -> k ∉ exclude, fn )
    D = OrderedDict( k => getfield( s, k ) for k ∈ fn )
    alignmem!( D, fnalign... )
    return T( ( D[k] for k ∈ fn )... )
end


function alignmem( s :: AbstractDict; exclude = [] )
    D = copy( s )
    keysalign = filter( k -> k ∉ exclude, keys(D) )
    alignmem!( D, keysalign... )
    return D
end

computesizedeep( x :: AbstractArray; exclude = Symbol[] ) = isbitstype( eltype( x ) ) ? sizeof( eltype( x ) ) * length( x ) : sum( computesizedeep, x )
function computesizedeep( x :: T; exclude = Symbol[] ) where T
    isbitstype( T ) && return 0
    isstructtype( T ) || return 0
    return sum( k ∈ exclude ? 0 : computesizedeep( getfield( x, k ) ) for k ∈ fieldnames( T ) )
end


function deeptransfer( x :: AbstractArray{T}, ▶ :: Ptr, offset :: Ref{Int}, owned :: Ref{Bool}; exclude = Symbol[] ) where T
    if isbitstype( T )
         sz = sizeof( T ) * length( x )
         sz == 0 && return x
         ▶now = ▶ + offset[]
         shouldown = !owned[]
         flat = unsafe_wrap( Array, Ptr{T}( ▶now ), length( x ); own = shouldown )
         if shouldown
             owned[] = true
         end
         dest = reshape( flat, size( x ) )
         offset[] += sz
         copyto!( dest, x )
         return newarrayofsametype( x, dest )
    else
        return map( el -> deeptransfer( el, ▶, offset, owned ), x )
    end
end

function deeptransfer( x :: T, ▶ :: Ptr, offset :: Ref{Int}, owned :: Ref{Bool}; exclude = Symbol[] ) where T
    isbitstype( T ) && return x
    if isstructtype( T )
        return T( ( k ∈ exclude ? deepcopy( getfield( x, k ) ) : deeptransfer( getfield( x, k ), ▶, offset, owned ) for k ∈ fieldnames( T ) )... )
    end
    return x
end

"""
    deepalignmem(x; exclude = [])

Recursively align memory of arrays within `x` and its fields.

Unlike `alignmem`, which only aligns the immediate fields/elements of `x`, `deepalignmem` traverses
the structure recursively.

# Arguments
- `x`: The object to recursively align.
- `exclude`: A list of field names to exclude from recursion and alignment.
           Excluded fields are `deepcopy`'d instead of being processed.
"""
function deepalignmem( x; exclude = Symbol[] )
    sz = computesizedeep( x; exclude = exclude )
    sz == 0 && return deepcopy( x )
    ▶ = Base.Libc.malloc( sz )
    offset = Ref( 0 )
    owned = Ref( false )
    return deeptransfer( x, ▶, offset, owned; exclude = exclude )
end




