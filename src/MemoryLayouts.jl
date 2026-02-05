module MemoryLayouts
using DataStructures, StyledStrings
using ConstructionBase

export alignmem, deepalignmem

include( "align.jl" )

function __init__()
    width = 80
    stars_h = "*"^width
    
    # Helper to pad text with stars on both sides
    function line(str)
        s_len = textwidth(String(str))
        pad = width - 4 - s_len
        pad_l = div(pad, 2)
        pad_r = pad - pad_l
        return styled"{(fg=0xFF5F00):**}" * (" " ^ pad_l) * str * (" " ^ pad_r) * styled"{(fg=0xFF5F00):**}"
    end

    println( styled"{(fg=0xFF5F00):$stars_h}" )
    println( line( styled"{bold,cyan:MemoryLayouts.jl} 🧠⚡" ) )
    println( line( styled"{italic:Optimize memory layout for maximum cache efficiency}" ) )
    println( line( "" ) )
    println( line( styled"{bold:Available Functions:}" ) )
    println( line( styled"• {magenta:alignmem( x )}" ) )
    println( line( styled"• {magenta:deepalignmem( x )}" ) )
    println( line( "" ) )
    println( line( styled"{bold,yellow:Usage Note:}" ) )
    println( line( "Aligned arrays share a single contiguous memory block" ) )
    println( line( styled"{italic:Resizing (e.g. push!) breaks contiguity}" ) )
    println( line( "" ) )
    println( line( styled"{bold:Performance Tip:}" ) )
    println( line( styled"Use {magenta:alignment = 64} for AVX-512 SIMD" ) )
    println( styled"{(fg=0xFF5F00):$stars_h}" )
end

end
