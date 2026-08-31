module MemoryLayoutsAxisKeysExt

using MemoryLayouts
using AxisKeys

MemoryLayouts.transferable( :: Type{<:KeyedArray{T, N, A}} ) where {T, N, A} = MemoryLayouts.transferable( A )

MemoryLayouts.underlying( x :: KeyedArray ) = MemoryLayouts.underlying( parent( x ) )

MemoryLayouts.newarrayofsametype( old :: KeyedArray, newdata ) = KeyedArray( MemoryLayouts.newarrayofsametype( parent( old ), newdata ), axiskeys( old ) )

end
