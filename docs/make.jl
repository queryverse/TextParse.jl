using Documenter, TextParse

makedocs(
    modules = [TextParse],
    clean = false,
    format = :html,
    sitename = "TextParse.jl",
    authors = "Shashi Gowda",
    pages = Any["Home" => "index.md"],
)

deploydocs(
    repo = "github.com/JuliaComputing/TextParse.jl.git",
    target = "build",
    deps = nothing,
    make = nothing,
)
