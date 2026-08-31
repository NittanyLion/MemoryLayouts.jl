module MemoryLayouts
using DataStructures, StyledStrings
using ConstructionBase
using Base.ScopedValues: ScopedValue, with

export layout, deeplayout, layoutstats, deeplayoutstats, layout!, visualizelayout, deepvisualizelayout, release_all!, LayoutHandle, release!, withlayout

include( "layout.jl" )
include( "stats.jl" )
include( "visualization.jl" )

"""
    banner()

Print the startup banner.  It is shown automatically when the package is loaded in an interactive
session, unless the environment variable `MEMORYLAYOUTS` is set to `"false"` or `"no"`.
"""
function banner()
    width = 80
    stars = "*"^width

    # Helper to pad text with stars on both sides
    function line( str )
        pad = width - 4 - textwidth( String( str ) )
        padl = div( pad, 2 )
        padr = pad - padl
        return styled"{(fg=0x00FF00):**}" * ( " " ^ padl ) * str * ( " " ^ padr ) * styled"{(fg=0x00FF00):**}"
    end

    println( styled"\n{(fg=0x00FF00):$stars}" )
    println( line( styled"{bold,cyan:MemoryLayouts.jl} 🧠⚡" ) )
    println( line( styled"{italic:Optimize memory layout for maximum cache efficiency}" ) )
    println( line( "" ) )
    println( line( styled"{bold:Available Functions:}" ) )
    println( line( styled"• {magenta:layout( x )}" ) )
    println( line( styled"• {magenta:deeplayout( x )}" ) )
    println( line( styled"• {magenta:layout!( x )}" ) )
    println( line( styled"• {magenta:withlayout( f )}" ) )
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
    println( styled"{(fg=0x00FF00):$stars}\n" )
end

function __init__()
    isinteractive() || return
    get( ENV, "MEMORYLAYOUTS", "" ) ∈ ( "false", "no" ) && return
    banner()
end

end
