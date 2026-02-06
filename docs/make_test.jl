using Documenter
using BenchmarkTools

makedocs(;
    sitename="Test",
    format=Documenter.HTML(),
    pages=["Test" => "test_example.md"],
    warnonly=true,
)
