module MemoryLayoutsNamedDimsExt

using MemoryLayouts
using NamedDims

MemoryLayouts.newarrayofsametype( old :: NamedDimsArray, newdata ) = NamedDimsArray( MemoryLayouts.newarrayofsametype(parent(old), newdata), dimnames(old) )

end
