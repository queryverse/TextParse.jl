using TextParse

import TextParse: tryparsenext, unwrap, failedat, AbstractToken, LocalOpts
import CodecZlib: GzipCompressorStream
using Test
using Dates, Random
using Nullables

# dumb way to compare two AbstractTokens
Base.:(==)(a::T, b::T) where {T<:AbstractToken} = string(a) == string(b)

@testset "TextParse" begin

import TextParse: eatnewlines
@testset "eatnewlines" begin
    @test eatnewlines("\n\r\nx") == (4, 2)
    @test eatnewlines("x\n\r\nx") == (1, 0)

    # Also test the AbstractString variant
    @test eatnewlines(SubString("\n\r\nx", 1)) == (4, 2)
    @test eatnewlines(SubString("x\n\r\nx", 1)) == (1, 0)
end

import TextParse: eatwhitespaces
@testset "eatwhitespaces" begin
    @test eatwhitespaces("  x") == 3
    @test eatwhitespaces("x  x") == 1

    # Also test the AbstractString variant
    @test eatwhitespaces(SubString("  x", 1)) == 3
    @test eatwhitespaces(SubString("x  x", 1)) == 1
end

import TextParse: getlineend
@testset "getlineend" begin
    @test getlineend("\nx") == 0
    @test getlineend("x\nx") == 1
    @test getlineend("x\ny", 2) == 1
    @test getlineend("x\nyz", 3) == 4
    @test getlineend("xβ\nyz") == 2
end

import TextParse: getrowend
@testset "getrowend" begin
    opts = LocalOpts(',', false, '"', '"', true, true)

    @test getrowend("\nx", 1, lastindex("\nx"), opts, ',') == 0
    @test getrowend("x\nx", 1, lastindex("x\nx"), opts, ',') == 1
    @test getrowend("x\ny", 2, lastindex("x\ny"), opts, ',') == 1
    @test getrowend("x\nyz", 3, lastindex("x\nyz"), opts, ',') == 4
    @test getrowend("\"x\"\nyz", 1, lastindex("x\nyz"), opts, ',') == 3
    @test_throws ErrorException getrowend("\"x\" er", 1, lastindex("\"x\" er"), opts, ',')
    @test getrowend("", 1, lastindex(""), opts, ',') == 0
    @test getrowend("  ", 1, lastindex("  "), opts, ',') == 2
    @test getrowend("a,b,c\nd,e,f", 1, lastindex("a,b,c\nd,e,f"), opts, ',') == 5
    @test getrowend("a,\"b\"\"ef\",c\nd,e,f", 1, lastindex("a,\"b\"\"ef\",c\nd,e,f"), opts, ',') == 11
    @test getrowend("a,\"b\"\"ef\"", 1, lastindex("a,\"b\"\"ef\""), opts, ',') == 9
    @test_throws ErrorException getrowend("\"xy", 1, lastindex("\"xy"), opts, ',')

    opts = LocalOpts(',', false, '"', '\\', true, true)
    @test getrowend("a,\"bef\",f\na,b", 1, lastindex("a,\"bef\",f\na,b"), opts, ',') == 9
    @test_throws ErrorException getrowend("\"xy\\", 1, lastindex("\"xy"), opts, ',')
end

import TextParse: fromtype, Percentage
@testset "Float parsing" begin

    @test tryparsenext(fromtype(Float64), "1", 1, 1) |> unwrap == (1.0, 2)
    @test tryparsenext(fromtype(Float64), "12", 1, 2) |> unwrap == (12.0, 3)
    @test tryparsenext(fromtype(Float64), ".1", 1, 2) |> unwrap == (0.1, 3)
    @test tryparsenext(fromtype(Float64), "1.1", 1, 3) |> unwrap == (1.1, 4)
    @test tryparsenext(fromtype(Float32), "1.", 1, 2) |> unwrap == (1f0,3)
    @test tryparsenext(fromtype(Float64), "-1.1", 1, 4) |> unwrap == (-1.1,5)
    @test tryparsenext(fromtype(Float64), "-1.0e-12", 1, 8) |> unwrap == (-1.0e-12,9)
    @test tryparsenext(fromtype(Float64), "-1e-12") |> unwrap == (-1.0e-12,7)
    @test tryparsenext(fromtype(Float64), "-1.0E-12", 1, 8) |> unwrap == (-1.0e-12,9)
    @test tryparsenext(fromtype(Float64), "5.e-3", 1, 5) |> unwrap == (5.0e-3,6) # 32
    @test tryparsenext(Percentage(), "33%") |> unwrap == (.33,4)
    @test tryparsenext(Percentage(), "3.3%") |> unwrap == (.033,5)

    # Also test AbstractString variant
    @test tryparsenext(fromtype(Float64), SubString("1", 1), 1, 1) |> unwrap == (1.0, 2)
    @test tryparsenext(fromtype(Float64), SubString("12", 1), 1, 2) |> unwrap == (12.0, 3)
    @test tryparsenext(fromtype(Float64), SubString(".1", 1), 1, 2) |> unwrap == (0.1, 3)
    @test tryparsenext(fromtype(Float64), SubString("1.1", 1), 1, 3) |> unwrap == (1.1, 4)
    @test tryparsenext(fromtype(Float32), SubString("1.", 1), 1, 2) |> unwrap == (1f0,3)
    @test tryparsenext(fromtype(Float64), SubString("-1.1", 1), 1, 4) |> unwrap == (-1.1,5)
    @test tryparsenext(fromtype(Float64), SubString("-1.0e-12", 1), 1, 8) |> unwrap == (-1.0e-12,9)
    @test tryparsenext(fromtype(Float64), SubString("-1e-12", 1)) |> unwrap == (-1.0e-12,7)
    @test tryparsenext(fromtype(Float64), SubString("-1.0E-12", 1), 1, 8) |> unwrap == (-1.0e-12,9)
    @test tryparsenext(fromtype(Float64), SubString("5.e-3", 1), 1, 5) |> unwrap == (5.0e-3,6) # 32
    @test tryparsenext(Percentage(), SubString("33%", 1)) |> unwrap == (.33,4)
    @test tryparsenext(Percentage(), SubString("3.3%", 1)) |> unwrap == (.033,5)

    rng = MersenneTwister(0)
    floats = rand(1_000)
    parsed_floats = map(i->get(tryparsenext(fromtype(Float64), i, 1, lastindex(i))[1]), string.(floats))
    @test parsed_floats == floats

    # Also test AbstractString variant
    parsed_floats = map(i->get(tryparsenext(fromtype(Float64), SubString(i,1), 1, lastindex(i))[1]), string.(floats))
    @test parsed_floats == floats
end

@testset "Int parsing" begin
    @test tryparsenext(fromtype(Int64), "1", 1, 1) |> unwrap == (1, 2)
    @test tryparsenext(fromtype(Int64), "01", 1, 2) |> unwrap == (1, 3)
    @test tryparsenext(fromtype(Int64), "0001", 1, 4) |> unwrap == (1, 5)
    @test tryparsenext(fromtype(Int64), "123", 1, 3) |> unwrap == (123, 4)
    @test tryparsenext(fromtype(Int64), "00123", 1, 5) |> unwrap == (123, 6)
    @test tryparsenext(fromtype(Int64), "-1", 1, 2) |> unwrap == (-1, 3)
    @test tryparsenext(fromtype(Int64), "-01", 1, 3) |> unwrap == (-1, 4)
    @test tryparsenext(fromtype(Int64), "-0001", 1, 5) |> unwrap == (-1, 6)
    @test tryparsenext(fromtype(Int64), "-123", 1, 4) |> unwrap == (-123, 5)
    @test tryparsenext(fromtype(Int64), "-00123", 1, 6) |> unwrap == (-123, 7)
    @test tryparsenext(fromtype(Int64), "+1", 1, 2) |> unwrap == (1, 3)
    @test tryparsenext(fromtype(Int64), "+01", 1, 3) |> unwrap == (1, 4)
    @test tryparsenext(fromtype(Int64), "+0001", 1, 5) |> unwrap == (1, 6)
    @test tryparsenext(fromtype(Int64), "+123", 1, 4) |> unwrap == (123, 5)
    @test tryparsenext(fromtype(Int64), "+00123", 1, 6) |> unwrap == (123, 7)
    @test tryparsenext(fromtype(Int64), "9223372036854775807", 1, 19) |> unwrap == (9223372036854775807, 20)
    @test tryparsenext(fromtype(Int64), "9223372036854775808", 1, 19) |> failedat == 1
    @test tryparsenext(fromtype(Int64), "19223372036854775808", 1, 20) |> failedat == 1
    @test tryparsenext(fromtype(UInt64), "18446744073709551615", 1, 20) |> unwrap == (0xffffffffffffffff, 21)
    @test tryparsenext(fromtype(UInt64), "18446744073709551616", 1, 20) |> failedat == 1
    @test tryparsenext(fromtype(Int128), "170141183460469231731687303715884105727", 1, 39) |> unwrap == (170141183460469231731687303715884105727, 40)
    @test tryparsenext(fromtype(Int128), "170141183460469231731687303715884105728", 1, 39) |> failedat == 1
    @test tryparsenext(fromtype(UInt128), "340282366920938463463374607431768211455", 1, 39) |> unwrap == (0xffffffffffffffffffffffffffffffff, 40)
    @test tryparsenext(fromtype(UInt128), "340282366920938463463374607431768211456", 1, 39) |> failedat == 1
end

import TextParse: StringToken
using WeakRefStrings
@testset "String parsing" begin

    # default options
    @test tryparsenext(StringToken(String), "") |> unwrap == ("", 1)
    x = "x"
    @test tryparsenext(StringToken(WeakRefString), WeakRefString(pointer(x), 1)) |> unwrap == ("x", 2)
    @test tryparsenext(StringToken(String), "x") |> unwrap == ("x", 2)
    @test tryparsenext(StringToken(String), "x ") |> unwrap == ("x ", 3)
    @test tryparsenext(StringToken(String), " x") |> unwrap == (" x", 3)
    @test tryparsenext(StringToken(String), "x\ny") |> unwrap == ("x", 2)
    @test tryparsenext(StringToken(String), "x,y") |> unwrap == ("x", 2) # test escape

    opts = LocalOpts(',', false, '"', '"', true, true)
    @test tryparsenext(StringToken(String), "", opts) |> unwrap == ("", 1)
    @test tryparsenext(StringToken(String), "\"\"", opts) |> unwrap == ("\"\"", 3)
    @test tryparsenext(StringToken(String), "x", opts) |> unwrap == ("x", 2)
    # test including new lines
    @test tryparsenext(StringToken(String), "x\ny", opts) |> unwrap == ("x\ny", 4)
    @test tryparsenext(StringToken(String), "\"x\ny\"", opts) |> unwrap == ("\"x\ny\"", 6)

    opts = LocalOpts(',', false, '"', '"', false, true)
    # test that includequotes option doesn't affect string
    @test tryparsenext(StringToken(String), "\"\"", opts) |> unwrap == ("\"\"", 3)

    opts = LocalOpts(',', false, '"', '\\', false, false)
    str =  "Owner 2 ”Vicepresident\"\""
    @test tryparsenext(Quoted(String, '"', '\\'), str, opts) |> unwrap == (str, lastindex(str)+1)
    str1 =  "\"Owner 2 ”Vicepresident\"\"\""
    @test tryparsenext(Quoted(String, '"', '"'), str1) |> unwrap == ("Owner 2 ”Vicepresident\"", lastindex(str1)+1)
    @test tryparsenext(Quoted(String, '"', '"'), "\"\tx\"") |> unwrap == ("\tx", 5)
    opts = LocalOpts(',', true, '"', '\\', false, false)
    @test tryparsenext(StringToken(String), "x y",1,3, opts) |> unwrap == ("x", 2)

    @test tryparsenext(StringToken(String), "abcβ") |> unwrap == ("abcβ", 6)
end


import TextParse: Quoted, NAToken, Unknown
@testset "Quoted string parsing" begin
    opts = LocalOpts(',', false, '"', '"', true, true)

    @test tryparsenext(Quoted(String, '"', '"'), "\"\"") |> unwrap == ("", 3)
    @test tryparsenext(Quoted(String, '"', '"'), "\"\" ", opts) |> unwrap == ("", 3)
    @test tryparsenext(Quoted(String, '"', '"'), "\"x\"") |> unwrap == ("x", 4)
    @test tryparsenext(Quoted(String, '"', '"', includequotes=true), "\"x\"") |> unwrap == ("\"x\"", 4)
    str2 =  "\"\"\"\""
    @test tryparsenext(Quoted(String, '"', '"'), str2, opts) |> unwrap == ("\"", lastindex(str2)+1)
    str1 =  "\"x”y\"\"\""
    @test tryparsenext(Quoted(StringToken(String), '"', '"', required=true), "x\"y\"") |> failedat == 1

    @test tryparsenext(Quoted(String, '"', '"'), str1) |> unwrap == ("x”y\"", lastindex(str1)+1)
    @test tryparsenext(Quoted(StringToken(String), '"', '\\'), "\"x\\\"yz\"") |> unwrap == ("x\"yz", 8)
    @test tryparsenext(Quoted(NAToken(fromtype(Int)), '"', '"'), "1") |> unwrap == (1,2)

    t = tryparsenext(Quoted(NAToken(fromtype(Int)), '"', '"'), "") |> unwrap
    @test ismissing(t[1])
    @test t[2] == 1

    t = tryparsenext(Quoted(NAToken(fromtype(Int)), '"', '"'), "\"\"") |> unwrap
    @test ismissing(t[1])
    @test t[2] == 3
    @test tryparsenext(Quoted(NAToken(fromtype(Int)), '"', '"'), "\"1\"") |> unwrap == (1, 4)


    @test tryparsenext(Quoted(StringToken(String), '"', '"'), "\"abc\"") |> unwrap == ("abc", 6)
    @test tryparsenext(Quoted(StringToken(String), '"', '"'), "x\"abc\"") |> unwrap == ("x\"abc\"", 7)
    @test tryparsenext(Quoted(StringToken(String), '"', '"'), "\"a\nbc\"") |> unwrap == ("a\nbc", 7)
    @test tryparsenext(Quoted(StringToken(String), '"', '"', required=true), "x\"abc\"") |> failedat == 1
    @test tryparsenext(Quoted(fromtype(Int), '"', '"'), "21") |> unwrap == (21,3)
    @test tryparsenext(Quoted(NAToken(fromtype(Int)), '"', '"'), "21") |> unwrap == (21,3)

    t = tryparsenext(Quoted(NAToken(fromtype(Int)), '"', '"'), "") |> unwrap
    @test ismissing(t[1])
    @test t[2] == 1

    t = tryparsenext(Quoted(NAToken(fromtype(Int)), '"', '"'), "\"\"") |> unwrap
    @test ismissing(t[1])
    @test t[2] == 3

    @test tryparsenext(Quoted(NAToken(fromtype(Int)), '"', '"'), "\"21\"") |> unwrap == (21, 5)
    @test ismissing(tryparsenext(Quoted(NAToken(Unknown()), '"', '"'), " ") |> unwrap |> first)
    opts = LocalOpts(',', false,'"', '"', false, false)
    @test tryparsenext(Quoted(StringToken(String), '"', '"'), "x,", opts) |> unwrap == ("x", 2)

    # stripspaces
    @test tryparsenext(Quoted(Percentage(), '"', '"'), "\" 10%\",", opts) |> unwrap == (0.1, 7)
    @test tryparsenext(Quoted(String, '"', '"'), "\" 10%\",", opts) |> unwrap == (" 10%", 7)
    opts = LocalOpts(',', true,'"', '"', false, false)
    @test tryparsenext(Quoted(StringToken(String), '"', '"'), "\"x y\" y", opts) |> unwrap == ("x y", 6)
    @test tryparsenext(Quoted(StringToken(String), '"', '"'), "x y", opts) |> unwrap == ("x", 2)
end

@testset "NA parsing" begin
    t = tryparsenext(NAToken(fromtype(Float64)), ",") |> unwrap
    @test ismissing(t[1])
    @test t[2] == 1

    t = tryparsenext(NAToken(fromtype(Float64)), "NA,") |> unwrap
    @test ismissing(t[1])
    @test t[2] == 3

    @test tryparsenext(NAToken(fromtype(Float64)), "X,") |> failedat == 1
    @test tryparsenext(NAToken(fromtype(Float64)), "1.212,") |> unwrap == (1.212, 6)
end

import TextParse: Field
@testset "Field parsing" begin
    f = fromtype(Int)
    @test tryparsenext(Field(f), "12,3") |> unwrap == (12, 4)
    @test tryparsenext(Field(f), "12 ,3") |> unwrap == (12, 5)
    @test tryparsenext(Field(f), " 12 ,3") |> unwrap == (12, 6)
    opts = LocalOpts('\t', false, 'x','x',true,false)
    @test tryparsenext(Field(f), "12\t3", 1, 4, opts) |> unwrap == (12, 4)
    @test tryparsenext(Field(f), "12 \t3", 1, 5, opts) |> unwrap == (12, 5)
    @test tryparsenext(Field(f), " 12 \t 3", 1, 6, opts) |> unwrap == (12, 6)
    opts = LocalOpts('\t', true, 'x','x',true,false)
    @test tryparsenext(Field(f), " 12 3", 1, 5, opts) |> unwrap == (12, 5)
    @test tryparsenext(Field(f, ignore_end_whitespace=false), " 12 \t 3", 1,6, opts) |> unwrap == (12, 5)
    opts = LocalOpts(' ', false, 'x','x',false, false)
    @test tryparsenext(Field(f,ignore_end_whitespace=false), "12 3", 1,4,opts) |> unwrap == (12, 4)
#    @test tryparsenext(Field(f,ignore_end_whitespace=false), "12 \t3", 1,5,opts) |> failedat == 3
    opts = LocalOpts('\t', false, 'x','x',false, false)
    @test tryparsenext(Field(f,ignore_end_whitespace=false), " 12\t 3", 1, 6, opts) |> unwrap == (12,5)
    @test tryparsenext(Field(f,eoldelim=true), " 12\n", 1, 4, opts) |> unwrap == (12,5)
    @test tryparsenext(Field(f,eoldelim=true), " 12\n\r\n", 1, 5, opts) |> unwrap == (12,6)
    @test tryparsenext(Field(f,eoldelim=true), " 12") |> unwrap == (12,4)

    # Also test AbstractString variant
    @test tryparsenext(Field(f), SubString("12,3",1)) |> unwrap == (12, 4)
    @test tryparsenext(Field(f), SubString("12 ,3",1)) |> unwrap == (12, 5)
    @test tryparsenext(Field(f), SubString(" 12 ,3",1)) |> unwrap == (12, 6)
    opts = LocalOpts('\t', false, 'x','x',true,false)
    @test tryparsenext(Field(f), SubString("12\t3",1), 1, 4, opts) |> unwrap == (12, 4)
    @test tryparsenext(Field(f), SubString("12 \t3",1), 1, 5, opts) |> unwrap == (12, 5)
    @test tryparsenext(Field(f), SubString(" 12 \t 3",1), 1, 6, opts) |> unwrap == (12, 6)
    opts = LocalOpts('\t', true, 'x','x',true,false)
    @test tryparsenext(Field(f), SubString(" 12 3",1), 1, 5, opts) |> unwrap == (12, 5)
    @test tryparsenext(Field(f, ignore_end_whitespace=false), SubString(" 12 \t 3",1), 1,6, opts) |> unwrap == (12, 5)
    opts = LocalOpts(' ', false, 'x','x',false, false)
    @test tryparsenext(Field(f,ignore_end_whitespace=false), SubString("12 3",1), 1,4,opts) |> unwrap == (12, 4)
#    @test tryparsenext(Field(f,ignore_end_whitespace=false), "12 \t3", 1,5,opts) |> failedat == 3
    opts = LocalOpts('\t', false, 'x','x',false, false)
    @test tryparsenext(Field(f,ignore_end_whitespace=false), SubString(" 12\t 3",1), 1, 6, opts) |> unwrap == (12,5)
    @test tryparsenext(Field(f,eoldelim=true), SubString(" 12\n",1), 1, 4, opts) |> unwrap == (12,5)
    @test tryparsenext(Field(f,eoldelim=true), SubString(" 12\n\r\n",1), 1, 5, opts) |> unwrap == (12,6)
    @test tryparsenext(Field(f,eoldelim=true), SubString(" 12",1)) |> unwrap == (12,4)
end


import TextParse: Record
@testset "Record parsing" begin
    r=Record((Field(fromtype(Int)), Field(fromtype(UInt)), Field(fromtype(Float64))))
    @test tryparsenext(r, "12,21,21,", 1, 9) |> unwrap == ((12, UInt(21), 21.0), 10)
    @test tryparsenext(r, "12,21.0,21,", 1, 9) |> failedat == 6
    s = "12   ,  21,  21.23,"
    @test tryparsenext(r, s, 1, length(s)) |> unwrap == ((12, UInt(21), 21.23), length(s)+1)
end


import TextParse: UseOne
@testset "UseOne" begin
    f = UseOne((Field(fromtype(Int)), Field(fromtype(Float64)), Field(fromtype(Int), eoldelim=true)), 3)
    @test tryparsenext(f, "1, 33.21, 45", 1, 12) |> unwrap == (45, 13)
end

import TextParse: Repeated
@testset "Repeated" begin
    f = Repeated(Field(fromtype(Int)), 3)
    @test tryparsenext(f, "1, 33, 45,", 1, 12) |> unwrap == ((1,33,45), 11)

    inp = join(map(string, [1:45;]), ", ") * ", "
    out = ntuple(identity, 45)
    f2 = Repeated(Field(fromtype(Int)), 45)
    @test tryparsenext(f2, inp, 1, length(inp)) |> unwrap == (out, length(inp))
    #@benchmark tryparsenext($f2, $inp, 1, length($inp))
end


import TextParse: quotedsplit
@testset "quotedsplit" begin
    opts = LocalOpts(',', false, '"', '\\', false, false)
    @test quotedsplit("x", opts, false, 1, 1) == ["x"]
    @test quotedsplit("x, y", opts, false, 1, 4) == ["x", "y"]
    @test quotedsplit("\"x\", \"y\"", opts,false, 1, 8) == ["x", "y"]
    @test quotedsplit("\"x\", \"y\"", opts,true, 1, 8) == ["\"x\"", "\"y\""]
    str = """x\nx,"s,", "\\",x" """
    @test quotedsplit(str, opts, false, 3, length(str)) == ["x", "s,", "\",x"]
    @test quotedsplit(",", opts, true, 1, 1) == ["", ""]
    @test quotedsplit(", ", opts, false, 1, 2) == ["", ""]
    str = "1, \"x \"\"y\"\" z\", 1"
    qopts = LocalOpts(',', false,'"', '"', false, false)
    @test quotedsplit(str, qopts,true, 1, lastindex(str)) == ["1", "\"x \"y\" z\"", "1"]
end

import TextParse: LocalOpts, readcolnames
@testset "CSV column names" begin
    str1 = """
     a, b,c d, e
    x,1,1,1
    ,1,1,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """

    str2 = """
     a, " b", "c", "d\\" e "
    """
    opts = LocalOpts(',', false, '"', '\\', false, false)
    @test readcolnames(str1, opts, 1, String[]) == (["a", "b", "c d", "e"], 13)
    @test readcolnames("\n\r$str1", opts, 3, Dict(3=>"x")) == (["a", "b", "x", "e"], 15)
    #@test readcolnames("$str2", opts, 3, Dict(3=>"x")) == (["a", "b", "x", "d\" e"], 24)
end

import TextParse: guesstoken, Unknown, Numeric, DateTimeToken, StrRange
@testset "guesstoken" begin
    opts = LocalOpts(UInt8(','), false, UInt8('"'), UInt8('"'), false, false)
    # Test null values
    @test guesstoken("", opts, false, Unknown()) == NAToken(Unknown())
    @test guesstoken("null", opts, false, Unknown()) == NAToken(Unknown())
    @test guesstoken("", opts, false, NAToken(Unknown())) == NAToken(Unknown())
    @test guesstoken("null", opts, false, NAToken(Unknown())) == NAToken(Unknown())

    # Test NA
    @test guesstoken("1", opts, false, NAToken(Unknown())) == NAToken(Numeric(Int))
    @test guesstoken("1", opts, false, NAToken(Numeric(Int))) == NAToken(Numeric(Int))
    @test guesstoken("", opts, false, NAToken(Numeric(Int))) == NAToken(Numeric(Int))
    @test guesstoken("1%", opts, false, NAToken(Unknown())) == NAToken(Percentage())

    # Test non-null numeric
    @test guesstoken("1", opts, false, Unknown()) == Numeric(Int)
    @test guesstoken("1", opts, false, Numeric(Int)) == Numeric(Int)
    @test guesstoken("", opts, false, Numeric(Int)) == NAToken(Numeric(Int))
    @test guesstoken("1.0", opts, false, Numeric(Int)) == Numeric(Float64)

    # Test strings
    @test guesstoken("x", opts, false, Unknown()) == Quoted(StringToken(StrRange), opts.quotechar, opts.escapechar)

    # Test nullable to string
    @test guesstoken("x", opts, false, NAToken(Unknown())) == Quoted(StringToken(StrRange), opts.quotechar, opts.escapechar)

    # Test string to non-null (short circuit)
    @test guesstoken("1", opts, false, StringToken(StrRange)) == StringToken(StrRange)

    # Test quoting
    @test guesstoken("\"1\"", opts, false, Unknown()) == Quoted(Numeric(Int), opts.quotechar, opts.escapechar)
    @test guesstoken("\"1\"", opts, false, Quoted(Numeric(Int), opts.quotechar, opts.escapechar)) == Quoted(Numeric(Int), opts.quotechar, opts.escapechar)

    # Test quoting with Nullable tokens
    @test guesstoken("\"\"", opts, false, Quoted(Unknown(), opts.quotechar, opts.escapechar)) == Quoted(StringToken(StrRange), opts.quotechar, opts.escapechar)
    @test guesstoken("\"\"", opts, false, Quoted(NAToken(Unknown()), opts.quotechar, opts.escapechar)) == Quoted(StringToken(StrRange), opts.quotechar, opts.escapechar)
    @test guesstoken("\"\"", opts, false, Quoted(Numeric(Int), opts.quotechar, opts.escapechar)) == Quoted(StringToken(StrRange), opts.quotechar, opts.escapechar)
    @test guesstoken("\"\"", opts, false, Unknown()) == Quoted(StringToken(StrRange), opts.quotechar, opts.escapechar)
    @test guesstoken("\"\"", opts, false, Numeric(Int)) == Quoted(StringToken(StrRange), opts.quotechar, opts.escapechar)
    @test guesstoken("", opts, false, Quoted(Numeric(Int), opts.quotechar, opts.escapechar)) == Quoted(NAToken(Numeric(Int)), opts.quotechar, opts.escapechar)
    @test guesstoken("", opts, false, Quoted(NAToken(Numeric(Int)), opts.quotechar, opts.escapechar)) == Quoted(NAToken(Numeric(Int)), opts.quotechar, opts.escapechar)
    @test guesstoken("1", opts, false, Quoted(NAToken(Numeric(Int)), opts.quotechar, opts.escapechar)) == Quoted(NAToken(Numeric(Int)), opts.quotechar, opts.escapechar)
    @test guesstoken("\"1\"", opts, false, Quoted(NAToken(Numeric(Int)), opts.quotechar, opts.escapechar)) == Quoted(NAToken(Numeric(Int)), opts.quotechar, opts.escapechar)

    # Test DateTime detection:
    tok = guesstoken("2016-01-01 10:10:10.10", opts, false, Unknown())
    @test tok == DateTimeToken(DateTime, dateformat"yyyy-mm-dd HH:MM:SS.s")
    @test guesstoken("2016-01-01 10:10:10.10", opts, false, tok) == tok
    @test guesstoken("2016-01-01 10:10:10.10", opts, false, Quoted(NAToken(Unknown()), opts.quotechar, opts.escapechar)) == Quoted(NAToken(tok), opts.quotechar, opts.escapechar)
end

import TextParse: guesscolparsers
@testset "CSV type detect" begin
    str1 = """
     a, b,c d, e
    x,1,1,1
    x,1,1,1
    x,1,1.,1
    x y,1.0,1,
    ,1.0,,1
    """
    opts = LocalOpts(',', false, '"', '\\', false, false)
    _, pos = readcolnames(str1, opts, 1, String[])
    testtill(i, colparsers=[]) = guesscolparsers(str1, lastindex(str1), String[], opts, pos, i, colparsers, StringArray)
    @test testtill(0) |> first == Any[]
    @test testtill(1) |> first == Any[Quoted(StringToken(StrRange), '"', '"'), fromtype(Int), fromtype(Int), fromtype(Int)]
    @test testtill(2) |> first == Any[Quoted(StringToken(StrRange), '"', '"'), fromtype(Int), fromtype(Int), fromtype(Int)]
    @test testtill(3) |> first == Any[Quoted(StringToken(StrRange), '"', '"'), fromtype(Int), fromtype(Float64), fromtype(Int)]
    @test testtill(4) |> first == Any[Quoted(StringToken(StrRange), '"', '"'), fromtype(Float64), fromtype(Float64), NAToken(fromtype(Int))]
    @test testtill(5) |> first == Any[Quoted(StringToken(StrRange), '"', '"'), fromtype(Float64), NAToken(fromtype(Float64)), NAToken(fromtype(Int))]
end


import TextParse: getlineat
@testset "getlineat" begin
    str = "abc\ndefg"
    @test str[getlineat(str,1)] == "abc\n"
    @test str[getlineat(str,4)] == "abc\n"
    @test str[getlineat(str,5)] == "defg"
    @test str[getlineat(str,lastindex(str))] == "defg"
    @test getlineat("x", 5) == 1:1
end


import TextParse: guessdateformat
@testset "date detection" begin
    @test guessdateformat("2016") |> typeof == DateTimeToken(Date, dateformat"yyyy-mm-dd") |> typeof
    @test guessdateformat("09/09/2016") |> typeof == DateTimeToken(Date, dateformat"mm/dd/yyyy") |> typeof
    @test guessdateformat("24/09/2016") |> typeof == DateTimeToken(Date, dateformat"dd/mm/yyyy") |> typeof
end

@testset "date parsing" begin
    tok = DateTimeToken(DateTime, dateformat"yyyy-mm-dd HH:MM:SS")
    opts = LocalOpts('y', false, '"', '\\', false, false)
    str = "1970-02-02 02:20:20"
    @test tryparsenext(tok, str, 1, length(str), opts) |> unwrap == (DateTime("1970-02-02T02:20:20"), length(str)+1)
    @test tryparsenext(tok, str*"x", 1, length(str)+1, opts) |> unwrap == (DateTime("1970-02-02T02:20:20"), length(str)+1)
    @test tryparsenext(tok, str[1:end-3]*"x", 1, length(str)-2, opts) |> failedat == length(str)-2
    @test tryparsenext(tok, str[1:end-3]*"y", 1, length(str)-2, opts) |> unwrap == (DateTime("1970-02-02T02:20"), length(str)-2)
end


import TextParse: _csvread
@testset "csvread" begin

    str1 = """
     a, b,c d, e
    x,1,1,1
    ,1,,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """
    data = ((["x", "","x","x y","x"],
              ones(5),
              [1,missing,1,1,missing],
              [1,1,1,missing,1]),
              ["a", "b", "c d", "e"])
    @test isequal(_csvread(str1, ','), data)
    coltype_test1 = _csvread(str1,
                            colparsers=Dict("b"=>Union{Missing, Float64},
                                          "e"=>Union{Missing,Float64}))
    coltype_test2 = _csvread(str1,
                            colparsers=Dict(2=>Union{Missing, Float64},
                                          4=>Union{Missing,Float64}))

    str2 = """
    x,1,1,1
    ,1,,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """
    coltype_test3 = _csvread(str2, header_exists=false,
                            colparsers=Dict(2=>Union{Missing,Float64},
                                          4=>Union{Missing,Float64}))
    @test eltype(coltype_test1[1][2]) == Union{Missing, Float64}
    @test eltype(coltype_test1[1][4]) == Union{Missing, Float64}
    @test eltype(coltype_test2[1][2]) == Union{Missing, Float64}
    @test eltype(coltype_test2[1][4]) == Union{Missing, Float64}
    @test eltype(coltype_test3[1][2]) == Union{Missing, Float64}
    @test eltype(coltype_test3[1][4]) == Union{Missing, Float64}

    @test isequal(data, _csvread(str1, type_detect_rows=1))
    @test isequal(data, _csvread(str1, type_detect_rows=2))
    @test isequal(data, _csvread(str1, type_detect_rows=3))
    @test isequal(data, _csvread(str1, type_detect_rows=4))
    # But we can't go from a non-string column to a string column
    str3 = """
     a, b,c d, e
    1,1,1,1
    x,1,1,1
    """
    @test_throws TextParse.CSVParseError _csvread(str3, type_detect_rows=1)

    # test growing of columns if prediction is too low
    @test _csvread("x,y\nabcd, defg\n,\n,\n", type_detect_rows=1) ==
        ((String["abcd", "", ""], String["defg", "", ""]), String["x", "y"])

    # #19
    s="""
    x,y,z
    1,1,x
    "2",2,x
    1,2,"x \"\"y\"\""
    """

    res = (([1, 2, 1], [1, 2, 2], String["x", "x", "x \"y\""]), String["x", "y", "z"])
    @test_broken _csvread(s, type_detect_rows=1, escapechar='"') == res
    @test_broken _csvread(s, type_detect_rows=2, escapechar='"') == res
    @test _csvread(s, type_detect_rows=1, escapechar='"', stringarraytype=Array) == res
    @test _csvread(s, type_detect_rows=2, escapechar='"', stringarraytype=Array) == res

    @test csvread(IOBuffer("x\n1")) == (([1],),["x"])

    @test _csvread("x\n1\n") == (([1],),["x"])

    # test detection of newlines in fields
    s = """x, y
        abc, def
        g
        hi,jkl
        mno,pqr
        """

    @test _csvread(s, type_detect_rows=1) == ((["abc", "g\nhi", "mno"], ["def", "jkl", "pqr"]), ["x", "y"])
    # test custom na strings
    s = """
    x,y
    1,2
    ?,3
    4,*
    """
    nullness = ([false, true, false], [false, false, true])
    @test map(x->map(ismissing, x), first(_csvread(s, nastrings=["?","*"]))) == nullness
    @test map(x->map(ismissing, x), first(_csvread(s, nastrings=["?","*"], type_detect_rows=1))) == nullness

    @test isequal(csvread(["data/a.csv", "data/b.csv"]),
                  (([1.0, 2.0, 1.0, 2.0, 3.0], [2, 2, missing, missing, missing],
                    [missing, missing, missing, 2, 1]), String["x", "y", "z"], [2, 3]))
    @test isequal(csvread(["data/a.csv", "data/b.csv"], samecols=[("y","z")]),
                  (([1.0, 2.0, 1.0, 2.0, 3.0], [2, 2, missing, 2, 1]), String["x", "y"], [2,3]))

    # shouldn't fail because y doesn't exist
    @test _csvread("x\n1", colparsers=Dict("y"=>String)) == (([1],), ["x"])

    # Don't try to guess type if it's provided by user. Issue JuliaDB.jl#109
    s="""
    time,value
    "2017-11-09T07:00:07.391101180",0
    """
    @test _csvread(s) == ((String["2017-11-09T07:00:07.391101180"], [0]), String["time", "value"])
    @test _csvread(s, colparsers=Dict(:time=>String)) == ((String["2017-11-09T07:00:07.391101180"], [0]), String["time", "value"])

    @test _csvread("") == ((), String[])

    @test _csvread("""x""y"", z
                   a""b"", 1""", stringarraytype=Array) == ((["a\"\"b\"\""], [1]), ["x\"\"y\"\"", "z"])
end

import TextParse: _csvread
@testset "commentchar" begin

    # First line a comment.
    str1 = """
    x,y,z
    #1,1,1
    2,2,2
    """

    @test _csvread(str1, commentchar='#') == (([2], [2], [2]), String["x", "y","z"])

    # Last line a comment.
    str2 = """
    x,y,z
    1,1,1
    #2,2,2
    """

    @test _csvread(str2, commentchar='#') == (([1], [1], [1]), String["x", "y","z"])

    # Multiple comments.
    str3 = """
    x,y,z
    1,1,1
    #2,2,2
    #3,3,3
    #4,4,4
    5,5,5
    #6,6,6
    """

    @test _csvread(str3, commentchar='#') == (([1, 5], [1, 5], [1, 5]), String["x", "y","z"])

    # Comments before headers.
    str4 = """
    #foo
    #bar
    x,y,z
    1,1,1
    #2,2,2
    """

    @test _csvread(str4, commentchar='#') == (([1], [1], [1]), String["x", "y","z"])

    # No comments.
    str5 = """
    x,y,z
    1,1,1
    2,2,2
    """

    @test _csvread(str5, commentchar='#') == (([1, 2], [1, 2], [1, 2]), String["x", "y","z"])

    # Non-default comment.
    str6 = """
    %test
    x,y,z
    1,1,1
    %2,2,2
    2,2,2
    """

    @test _csvread(str6, commentchar='%') == (([1, 2], [1, 2], [1, 2]), String["x", "y","z"])

    # Do not skip commented lines (commentchar=nothing).
    str7 = """
    x,y,z
    1,1,1
    #2,2,2
    """

    # Since we are not skipping commented lines the '#' character is considered 
    # data. This will force parsing to treat columns with '#'s as String columns.
    # Here, we verify this behavior.
    result = _csvread(str7)
    @test eltype(result[1][1]) == String
    @test result == ((["1", "#2"], [1, 2], [1, 2]), String["x", "y","z"])
end

@testset "skiplines_begin" begin
    str1 = """
    hello

    world
    x,y,z
    1,1,1
    """
    @test _csvread(str1, skiplines_begin=3) == (([1], [1], [1]), String["x", "y","z"])

    s = """
    x,y z
    a,b 1
    e  	3
    """
    @test _csvread(s, spacedelim=true) == ((["a,b", "e"],[1,3]), ["x,y","z"])
end

@testset "skipfield" begin
    str1 = """
    x,y,z
    1,2.1,"John"
    4,5.2,"Sally"
    """

    @test _csvread(str1, colparsers=Dict(1=>nothing)) == (([2.1,5.2], ["John", "Sally"]), String["y","z"])
    @test _csvread(str1, colparsers=Dict(2=>nothing)) == (([1,4], ["John", "Sally"]), String["x","z"])
    @test _csvread(str1, colparsers=Dict(3=>nothing)) == (([1,4], [2.1,5.2]), String["x","y"])

    @test _csvread(str1, colparsers=Dict(1=>nothing,2=>nothing)) == ((["John", "Sally"],), String["z"])
    @test _csvread(str1, colparsers=Dict(1=>nothing,3=>nothing)) == (([2.1,5.2],), String["y"])
    @test _csvread(str1, colparsers=Dict(2=>nothing,3=>nothing)) == (([1,4],), String["x"])

    @test _csvread(str1, colparsers=Dict(1=>nothing,2=>nothing,3=>nothing)) == ((), String[])
end

import TextParse: eatwhitespaces
@testset "custom parser" begin
    floatparser = Numeric(Float64)
    percentparser = CustomParser(Float64) do str, i, len, opts
        num, ii = tryparsenext(floatparser, str, i, len, opts)
        if num === nothing
            return num, ii
        else
            # parse away the % char
            ii = eatwhitespaces(str, ii, len)
            c, k = iterate(str, ii)
            if c != '%'
                return Nullable{Float64}(), ii # failed to parse %
            else
                return num, k # the point after %
            end
        end
    end

    @test tryparsenext(percentparser, "10%")  |> unwrap == (10.0, 4)
    @test tryparsenext(percentparser, "10.32 %") |> unwrap == (10.32, 8)
    @test tryparsenext(percentparser, "2k%") |> failedat ==  2
end

@testset "read gzipped files" begin
    fn   = joinpath(@__DIR__, "data", "a.csv")
    fngz = fn*".gz"
    open(fn, "r") do ior
        open(GzipCompressorStream, fngz, "w") do iow
            write(iow, ior)
        end
    end
    @test csvread(fn)   == csvread(fngz)
    @test csvread([fn]) == csvread([fngz])
    if isfile(fngz)
        rm(fngz)
    end
end

include("test_vectorbackedstrings.jl")

end
