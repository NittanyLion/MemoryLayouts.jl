using AlignMemory
using Documenter

DocMeta.setdocmeta!(AlignMemory, :DocTestSetup, :(using AlignMemory); recursive=true)

makedocs(;
    modules=[AlignMemory],
    authors="Joris Pinkse <pinkse@gmail.com> and contributors",
    sitename="AlignMemory.jl",
    format=Documenter.HTML(;
        canonical="https://NittanyLion.github.io/AlignMemory.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/NittanyLion/AlignMemory.jl",
    devbranch="main",
)
