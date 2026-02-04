module AlignMemoryNamedDimsExt

using AlignMemory
using NamedDims

AlignMemory.newarrayofsametype( old::NamedDimsArray, newdata ) = NamedDimsArray( AlignMemory.newarrayofsametype(parent(old), newdata), dimnames(old) )

end
