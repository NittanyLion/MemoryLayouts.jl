using Documenter
using BenchmarkTools

makedocs(;
    sitename="Test Semicolon",
    format=Documenter.HTML(),
    pages=["Test" => "test_example_semicolon.md"],
    warnonly=true,
)
