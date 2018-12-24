using Documenter, TextParse

makedocs(
    modules = [TextParse],
    sitename = "TextParse.jl",
    authors = "Shashi Gowda",
    pages = Any["Home" => "index.md"],
)

deploydocs(
    repo = "github.com/JuliaComputing/TextParse.jl.git"
)
