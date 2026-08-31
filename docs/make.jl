using Documenter, TextParse

makedocs(
    modules = [TextParse],
    sitename = "TextParse.jl",
    authors = "Shashi Gowda",
    warnonly = [:missing_docs],
    pages = Any["Home" => "index.md"],
)

deploydocs(
    repo = "github.com/JuliaComputing/TextParse.jl.git"
)
