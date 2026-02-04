using Pkg
Pkg.activate(@__DIR__)
Pkg.develop(PackageSpec(path=joinpath(@__DIR__, "..")))
Pkg.instantiate()

using AlignMemory
using Documenter

DocMeta.setdocmeta!(AlignMemory, :DocTestSetup, :(using AlignMemory); recursive=true)

makedocs(;
    modules=[AlignMemory],
    authors="Joris Pinkse <pinkse@gmail.com> and contributors",
    sitename="AlignMemory.jl",
    warnonly=true,
    format=Documenter.HTML(;
        canonical="https://NittanyLion.github.io/AlignMemory.jl",
        edit_link="main",
        assets=["assets/custom.css"],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/NittanyLion/AlignMemory.jl",
    devbranch="main",
)
