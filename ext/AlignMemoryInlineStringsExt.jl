module AlignMemoryInlineStringsExt

using AlignMemory
using InlineStrings

function AlignMemory.transferadvance!( D :: AbstractDict, x, TT :: Type{𝒯}, ▶ :: Ptr, offset :: Ref{Int} ) where 𝒯 <: InlineString
    @assert D[x] isa AbstractArray
    length( D[x] ) == 0 && return nothing
    ▶now = ▶ + offset[]
    flat = unsafe_wrap( Array, Ptr{𝒯}( ▶now ), length( D[x] ); own = offset[] == 0 )
    dest = reshape( flat, size( D[x] ) )
    offset[] += length( D[x] ) * sizeof( 𝒯 )
    copyto!( dest, D[x] )
    D[x] = AlignMemory.newarrayofsametype( D[x], dest )
    return nothing
end

end
