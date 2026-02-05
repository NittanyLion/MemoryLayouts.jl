module MemoryLayouts
using DataStructures, StyledStrings
using ConstructionBase

export alignmem, deepalignmem

include( "align.jl" )

function __init__()
    println( styled"""
    {bold,cyan:MemoryLayouts.jl} 🧠⚡
      {italic:Optimize memory layout for maximum cache efficiency.}

      {bold:Available Functions:}
        • {magenta:alignmem( x )}      {grey:Aligns immediate fields of x}
        • {magenta:deepalignmem( x )}  {grey:Recursively aligns nested structures}

      {bold,yellow:Usage Note:}
      Aligned arrays share a single contiguous memory block.
      {italic:Resizing an array (e.g. push!) will break contiguity for that array.}

      {bold:Performance Tip:}
      Use the {magenta:alignment} keyword (e.g. {cyan:alignment=64}) to optimize for SIMD (AVX-512).""" )
end

end
