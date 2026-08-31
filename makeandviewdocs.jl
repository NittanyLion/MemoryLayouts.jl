# Build the documentation locally and serve it in the browser.
# Run with:  julia makeandviewdocs.jl
#
# Everything happens in the docs/ environment so that nothing is added to the
# package's own Project.toml.

using Pkg
Pkg.activate( "docs" )
Pkg.develop( path = "." )
haskey( Pkg.project().dependencies, "LiveServer" ) || Pkg.add( "LiveServer" )
Pkg.instantiate()

include( "docs/make.jl" )

using LiveServer
LiveServer.serve( dir = "docs/build" )
