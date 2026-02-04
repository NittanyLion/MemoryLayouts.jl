module AlignMemoryOffsetArraysExt

using AlignMemory
using OffsetArrays

AlignMemory.newarrayofsametype( old::OffsetArray, newdata ) = OffsetArray( AlignMemory.newarrayofsametype(parent(old), newdata), old.offsets... )

end
