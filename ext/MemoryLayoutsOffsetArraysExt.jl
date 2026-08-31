module MemoryLayoutsOffsetArraysExt

using MemoryLayouts
using OffsetArrays

MemoryLayouts.transferable( :: Type{<:OffsetArray{T, N, A}} ) where {T, N, A} = MemoryLayouts.transferable( A )

MemoryLayouts.underlying( x :: OffsetArray ) = MemoryLayouts.underlying( parent( x ) )

MemoryLayouts.newarrayofsametype( old :: OffsetArray, newdata ) = OffsetArray( MemoryLayouts.newarrayofsametype( parent( old ), newdata ), old.offsets... )

end
