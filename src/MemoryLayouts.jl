module MemoryLayouts
using DataStructures, StyledStrings
using ConstructionBase
using Base.ScopedValues: ScopedValue, with

export layout, deeplayout, layoutstats, deeplayoutstats, layout!, visualizelayout, deepvisualizelayout, release_all!, LayoutHandle, release!, withlayout

include( "layout.jl" )
include( "stats.jl" )
include( "visualization.jl" )

"""
    MEMORYLAYOUTS

Set `ENV[ "MEMORYLAYOUTS" ]` to `"true"` or `"yes"` **before** loading this package to print the
greeting below on load.  It is off by default: `__init__` runs whenever anything anywhere in the
session depends on this package, including transitively, and a package that announces itself
unbidden is noise in every log of every dependent.  A dependent cannot switch it off from its own
code either -- this `__init__` runs before any of the dependent's own top-level code does -- so
opt-in is the only setting that leaves the choice with the person at the terminal.
"""
bannerwanted() = get( ENV, "MEMORYLAYOUTS", "" ) ∈ ( "true", "yes" )

function __init__()
    bannerwanted() || return

    width = 80
    stars_h = "*"^width
    
    # Helper to pad text with stars on both sides
    function line(str)
        s_len = textwidth(String(str))
        pad = width - 4 - s_len
        pad_l = div(pad, 2)
        pad_r = pad - pad_l
        return styled"{(fg=0x00FF00):**}" * (" " ^ pad_l) * str * (" " ^ pad_r) * styled"{(fg=0x00FF00):**}"
    end

    println( styled"\n{(fg=0x00FF00):$stars_h}" )
    println( line( styled"{bold,cyan:MemoryLayouts.jl} 🧠⚡" ) )
    println( line( styled"{italic:Optimize memory layout for maximum cache efficiency}" ) )
    println( line( "" ) )
    println( line( styled"{bold:Available Functions:}" ) )
    println( line( styled"• {magenta:layout( x )}" ) )
    println( line( styled"• {magenta:deeplayout( x )}" ) )
    println( line( styled"• {magenta:layout!( x )}" ) )
    println( line( styled"• {cyan:layoutstats( x )}" ) )
    println( line( styled"• {cyan:deeplayoutstats( x )}" ) )
    println( line( styled"• {green:visualizelayout( x )}" ) )
    println( line( styled"• {green:deepvisualizelayout( x )}" ) )
    println( line( "" ) )
    println( line( styled"{bold,yellow:Usage Notes:}" ) )
    println( line( "Aligned arrays share a single contiguous memory block" ) )
    println( line( styled"{italic:Please {red:read the docs for gotchas}}" ) )
    println( line( "" ) )
    println( line( styled"{bold:Performance Tip:}" ) )
    println( line( styled"Use {magenta:alignment = 64} for AVX-512 SIMD" ) )
    println( styled"{(fg=0x00FF00):$stars_h}\n" )
end

end
