module MemoryLayoutsNamedDimsExt

using MemoryLayouts
using NamedDims

MemoryLayouts.transferable( :: Type{<:NamedDimsArray{L, T, N, A}} ) where {L, T, N, A} = MemoryLayouts.transferable( A )

MemoryLayouts.underlying( x :: NamedDimsArray ) = MemoryLayouts.underlying( parent( x ) )

MemoryLayouts.newarrayofsametype( old :: NamedDimsArray, newdata ) = NamedDimsArray( MemoryLayouts.newarrayofsametype( parent( old ), newdata ), dimnames( old ) )

end
