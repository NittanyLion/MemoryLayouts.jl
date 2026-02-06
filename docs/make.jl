using MemoryLayouts
using Documenter

DocMeta.setdocmeta!(MemoryLayouts, :DocTestSetup, :(using MemoryLayouts); recursive=true)

makedocs(;
    modules=[MemoryLayouts],
    authors="Joris Pinkse <pinkse@gmail.com> and contributors",
    sitename="MemoryLayouts.jl",
    format=Documenter.HTML(;
        canonical="https://NittanyLion.github.io/MemoryLayouts.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
    warnonly=true,
)

deploydocs(;
    repo="github.com/NittanyLion/MemoryLayouts.jl",
    devbranch="main",
)
