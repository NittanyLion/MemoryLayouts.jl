module AlignMemoryAxisKeysExt

using AlignMemory
using AxisKeys

AlignMemory.newarrayofsametype( old::KeyedArray, newdata ) = KeyedArray( AlignMemory.newarrayofsametype(parent(old), newdata), axiskeys(old) )

end
