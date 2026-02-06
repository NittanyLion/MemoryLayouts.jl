module MemoryLayoutsAxisKeysExt

using MemoryLayouts
using AxisKeys

MemoryLayouts.newarrayofsametype( old :: KeyedArray, newdata ) = KeyedArray( MemoryLayouts.newarrayofsametype(parent(old), newdata), axiskeys(old) )

end
