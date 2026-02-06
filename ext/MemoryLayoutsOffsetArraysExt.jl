module MemoryLayoutsOffsetArraysExt

using MemoryLayouts
using OffsetArrays

MemoryLayouts.newarrayofsametype( old :: OffsetArray, newdata ) = OffsetArray( MemoryLayouts.newarrayofsametype(parent(old), newdata), old.offsets... )

end
