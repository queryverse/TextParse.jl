using TextParse
import TextParse: tryparsenext, unwrap, failedat, AbstractToken
using Base.Test

# dumb way to compare two AbstractTokens
Base.:(==){T<:AbstractToken}(a::T, b::T) = string(a) == string(b)

import TextParse: eatnewlines
@testset "eatnewlines" begin
    @test eatnewlines("\n\r\nx") == (4, 2)
    @test eatnewlines("x\n\r\nx") == (1, 0)
end


import TextParse: getlineend
@testset "getlineend" begin
    @test getlineend("\n\r\nx") == 0
    @test getlineend("x\n\r\nx") == 1
    @test getlineend("x y\n\r\nxyz", 6) == 5
    @test getlineend("x y\n\r\nxyz", 7) == 9
end


import TextParse: fromtype
@testset "Float parsing" begin
    @test tryparsenext(fromtype(Float64), "21", 1, 2) |> unwrap== (21.0,3)
    @test tryparsenext(fromtype(Float64), ".21", 1, 3) |> unwrap== (.21,4)
    @test tryparsenext(fromtype(Float64), "1.21", 1, 4) |> unwrap== (1.21,5)
    @test tryparsenext(fromtype(Float32), "1.", 1, 2) |> unwrap== (1f0,3)
    @test tryparsenext(fromtype(Float64), "-1.21", 1, 5) |> unwrap== (-1.21,6)
    @test tryparsenext(fromtype(Float64), "-1.5e-12", 1, 8) |> unwrap == (-1.5e-12,9)
    @test tryparsenext(fromtype(Float64), "-1.5E-12", 1, 8) |> unwrap == (-1.5e-12,9)
end


import TextParse: StringToken
@testset "String parsing" begin
    for (s,till) in [("test  ",7), ("\ttest ",7), ("test\nasdf", 5), ("test,test", 5), ("test\\,test", 6)]
        @test tryparsenext(StringToken(String), s) |> unwrap == (s[1:till-1], till)
    end
    for (s,till) in [("test\nasdf", 10), ("te\nst,test", 6)]
        @test tryparsenext(StringToken(String, ',', '"', '"', false, true), s) |> unwrap == (s[1:till-1], till)
    end
    @test tryparsenext(StringToken(String, ',', '"', '"',false, true), "") |> unwrap == ("", 1)
    tok = StringToken(String, '"', '"', '"', false, true)

    @test tryparsenext(Quoted(String), "\"x\"", 1,3) |> unwrap == ("x", 4)
    @test tryparsenext(Quoted(String, includequotes=true), "\"x\"", 1,3) |> unwrap == ("\"x\"", 4)
    @test tryparsenext(Quoted(String, escapechar='"', includequotes=true), "\"x\"", 1,3) |> unwrap == ("\"x\"", 4)
    @test tryparsenext(Quoted(String, includequotes=true, escapechar='"'), "\"x \"\"y\"\" z\"", 1,11) |> unwrap == ("\"x \"\"y\"\" z\"", 12)
    str =  "Owner 2 ”Vicepresident\"\""
    @test tryparsenext(tok, str) |> unwrap == (str, endof(str)+1)
    str1 =  "\"Owner 2 ”Vicepresident\"\"\""
    @test tryparsenext(Quoted(String,quotechar='"', escapechar='"'), str1) |> unwrap == (str, endof(str1)+1)
    str2 =  "\"\"\"\""
    @test tryparsenext(Quoted(String,quotechar='"', escapechar='"'), str2) |> unwrap == ("\"\"", endof(str2)+1)
    str2 =  "\"\"\"\"\"\","
    @test tryparsenext(Quoted(String,quotechar='"', escapechar='"'), str2) |> unwrap == ("\"\"\"\"", endof(str2))

end


import TextParse: Quoted, NAToken
@testset "Quoted string parsing" begin
    @test tryparsenext(Quoted(StringToken(String)), "\"abc\"") |> unwrap == ("abc", 6)
    @test tryparsenext(Quoted(StringToken(String)), "\"a\\\"bc\"") |> unwrap == ("a\\\"bc", 8)
    @test tryparsenext(Quoted(StringToken(String)), "x\"abc\"") |> unwrap == ("x\"abc\"", 7)
    @test tryparsenext(Quoted(StringToken(String)), "\"a\nbc\"") |> unwrap == ("a\nbc", 7)
    @test tryparsenext(Quoted(StringToken(String), required=true), "x\"abc\"") |> failedat == 1
    @test tryparsenext(Quoted(fromtype(Int)), "21") |> unwrap == (21,3)
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "21") |> unwrap |> unwrap == (21,3)
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "") |> unwrap |> failedat == 1
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "\"\"") |> unwrap |> failedat == 3
    @test tryparsenext(Quoted(NAToken(fromtype(Int))), "\"21\"") |> unwrap |> unwrap == (21, 5)
    @test tryparsenext(Quoted(StringToken(String, ',','"','"')), "x,") |> unwrap == ("x", 2)
end

@testset "NA parsing" begin
    @test tryparsenext(NAToken(fromtype(Float64)), ",") |> unwrap |> failedat == 1 # is nullable
    @test tryparsenext(NAToken(fromtype(Float64)), "X,") |> failedat == 1
    @test tryparsenext(NAToken(fromtype(Float64)), "NA,") |> unwrap |> failedat == 3
    @test tryparsenext(NAToken(fromtype(Float64)), "1.212,") |> unwrap |> unwrap == (1.212, 6)
end

import TextParse: Field
@testset "Field parsing" begin
    f = fromtype(Int)
    @test tryparsenext(Field(f,delim=','), "12,3", 1,4) |> unwrap == (12, 4)
    @test tryparsenext(Field(f,delim=','), "12 ,3", 1,5) |> unwrap == (12, 5)
    @test tryparsenext(Field(f,delim=','), " 12 ,3", 1,6) |> unwrap == (12, 6)
    @test tryparsenext(Field(f,delim='\t'), "12\t3", 1,4) |> unwrap == (12, 4)
    @test tryparsenext(Field(f,delim='\t'), "12 \t3", 1,5) |> unwrap == (12, 5)
    @test tryparsenext(Field(f,delim='\t'), " 12 \t 3", 1,7) |> unwrap == (12, 6)
    @test tryparsenext(Field(f,spacedelim=true), " 12 3", 1,5) |> unwrap == (12, 5)
    @test tryparsenext(Field(f,spacedelim=true), " 12 3", 1,5) |> unwrap == (12, 5)
    @test tryparsenext(Field(f,spacedelim=true, ignore_end_whitespace=false), " 12 \t 3", 1,7) |> unwrap == (12, 5)
    @test tryparsenext(Field(f,ignore_end_whitespace=false, delim=' '), "12 3", 1,4) |> unwrap == (12, 4)
    @test tryparsenext(Field(f,ignore_end_whitespace=false, delim='\t'), "12 \t3", 1,5) |> failedat == 3
    @test tryparsenext(Field(f,ignore_end_whitespace=false, delim='\t'), " 12\t 3", 1,5) |> unwrap == (12,5)
    @test tryparsenext(Field(f,eoldelim=true, delim='\t'), " 12\n", 1,4) |> unwrap == (12,5)
    @test tryparsenext(Field(f,eoldelim=true), " 12", 1,3) |> unwrap == (12,4)
    @test tryparsenext(Field(f,eoldelim=true, delim='\t'), " 12\n\r\n", 1,6) |> unwrap == (12,6)
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
    f = UseOne((Field(fromtype(Int), delim=';'), Field(fromtype(Float64)), Field(fromtype(Int), eoldelim=true)), 3)
    @test tryparsenext(f, "1; 33.21, 45", 1, 12) |> unwrap == (45, 13)
end

import TextParse: Repeated
@testset "Repeated" begin
    f = Repeated(Field(fromtype(Int), delim=';'), 3)
    @test tryparsenext(f, "1; 33; 45;", 1, 12) |> unwrap == ((1,33,45), 11)

    inp = join(map(string, [1:45;]), "; ") * "; "
    out = ntuple(identity, 45)
    f2 = Repeated(Field(fromtype(Int), delim=';'), 45)
    @test tryparsenext(f2, inp, 1, length(inp)) |> unwrap == (out, length(inp))
    #@benchmark tryparsenext($f2, $inp, 1, length($inp))
end


import TextParse: quotedsplit
@testset "quotedsplit" begin
    @test quotedsplit("x", ',', '"','\\',false, 1, 1) == ["x"]
    @test quotedsplit("x, y", ',', '"','\\',false, 1, 4) == ["x", "y"]
    @test quotedsplit("\"x\", \"y\"", ',', '"','\\',false, 1, 8) == ["x", "y"]
    @test quotedsplit("\"x\", \"y\"", ',', '"','\\',true, 1, 8) == ["\"x\"", "\"y\""]
    str = """x\nx,"s,", "\\",x" """
    @test quotedsplit(str, ',','"','\\', false, 3, length(str)) == ["x", "s,", "\\\",x"]
    @test quotedsplit(",", ',','"','\\', true, 1, 1) == ["", ""]
    @test quotedsplit(", ", ',','"','\\', false, 1, 2) == ["", ""]
    str = "1, \"x \"\"y\"\" z\", 1"
    @test quotedsplit(str, ',', '"','"',true, 1, endof(str)) == ["1", "\"x \"\"y\"\" z\"", "1"]
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
    opts = LocalOpts(',', '"', '\\', false, false)
    @test readcolnames(str1, opts, 1, String[]) == (["a", "b", "c d", "e"], 13)
    @test readcolnames("\n\r$str1", opts, 3, Dict(3=>"x")) == (["a", "b", "x", "e"], 15)
    #@test readcolnames("$str2", opts, 3, Dict(3=>"x")) == (["a", "b", "x", "d\" e"], 24)
end

import TextParse: guesscoltypes, StrRange
@testset "CSV type detect" begin
    str1 = """
     a, b,c d, e
    x,1,1,1
    x,1,1,1
    x,1,1.,1
    x y,1.0,1,
    ,1.0,,1
    """
    opts = LocalOpts(',', '"', '\\', false, false)
    _, pos = readcolnames(str1, opts, 1, String[])
    testtill(i, coltypes=[]) = guesscoltypes(str1, String[], opts, pos, i, coltypes)
    @test testtill(0) |> first == Any[]
    @test testtill(1) |> first == map(fromtype, [StrRange, Int, Int, Int])
    @test testtill(2) |> first == map(fromtype, [StrRange, Int, Int, Int])
    @test testtill(3) |> first == map(fromtype, [StrRange, Int, Float64, Int])
    @test testtill(4) |> first == map(fromtype, [StrRange, Float64, Float64, Nullable{Int}])
    @test testtill(5) |> first == map(fromtype, [StrRange, Float64, Nullable{Float64}, Nullable{Int}])
end


import TextParse: getlineat
@testset "getlineat" begin
    str = "abc\ndefg"
    @test str[getlineat(str,1)] == "abc\n"
    @test str[getlineat(str,4)] == "abc\n"
    @test str[getlineat(str,5)] == "defg"
    @test str[getlineat(str,endof(str))] == "defg"
end

import TextParse: guesstoken, Unknown, Numeric, DateTimeToken
@testset "guesstoken" begin
    opts = LocalOpts(',', '"', '\\', false, false)
    @test guesstoken("21", opts) == fromtype(Int)
    @test guesstoken("", opts) == NAToken(Unknown())
    @test guesstoken("NA", opts) == NAToken(Unknown())
    @test guesstoken("21", opts, NAToken(Unknown())) == NAToken(fromtype(Int))
    @test guesstoken("", opts, fromtype(Int)) == NAToken(fromtype(Int))
    @test guesstoken("", opts, NAToken(fromtype(Int))) == NAToken(fromtype(Int))
    @test guesstoken("21", opts, fromtype(Float64)) == fromtype(Float64)
    @test guesstoken("\"21\"", opts, fromtype(Float64)) == Quoted(Numeric(Float64), required=false)
    @test guesstoken("abc", opts, fromtype(Float64), String) == fromtype(String)
    @test guesstoken("\"abc\"", opts, fromtype(Float64), String) == Quoted(fromtype(String))
    @test guesstoken("abc", opts, Quoted(fromtype(Float64)), String) == Quoted(fromtype(String))
    @test guesstoken("abc", opts, NAToken(Unknown()), String) == StringToken(String)
    @test guesstoken("abc", opts, NAToken(fromtype(Int)), String) == StringToken(String)
    @test guesstoken("20160909 12:12:12", opts, Unknown()) |> typeof == DateTimeToken(DateTime, dateformat"yyyymmdd HH:MM:SS.s") |> typeof
    @test guesstoken("\"12\"", opts, NAToken(Unknown()), String) == Quoted(NAToken(fromtype(Int)))
    @test guesstoken("\"\"", opts, Quoted(fromtype(Int)), String) == Quoted(NAToken(fromtype(Int)))
end

import TextParse: guessdateformat
@testset "date detection" begin
    @test guessdateformat("2016") |> typeof == DateTimeToken(Date, dateformat"yyyy-mm-dd") |> typeof
    @test guessdateformat("09/09/2016") |> typeof == DateTimeToken(Date, dateformat"mm/dd/yyyy") |> typeof
    @test guessdateformat("24/09/2016") |> typeof == DateTimeToken(Date, dateformat"dd/mm/yyyy") |> typeof
end

@testset "date parsing" begin
    tok = DateTimeToken(DateTime, dateformat"yyyy-mm-dd HH:MM:SS")
    opts = LocalOpts('y', '"', '\\', false, false)
    str = "1970-02-02 02:20:20"
    @test tryparsenext(tok, str, 1, length(str), opts) |> unwrap == (DateTime("1970-02-02T02:20:20"), length(str)+1)
    @test tryparsenext(tok, str*"x", 1, length(str)+1, opts) |> unwrap == (DateTime("1970-02-02T02:20:20"), length(str)+1)
    @test tryparsenext(tok, str[1:end-3]*"x", 1, length(str)-2, opts) |> failedat == length(str)-2
    @test tryparsenext(tok, str[1:end-3]*"y", 1, length(str)-2, opts) |> unwrap == (DateTime("1970-02-02T02:20"), length(str)-2)
end


using NullableArrays
import TextParse: _csvread
@testset "_csvread" begin

    str1 = """
     a, b,c d, e
    x,1,1,1
    ,1,1,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """
    data = (
            (["x", "","x","x y","x"],
              ones(5),
              NullableArray(ones(5), Bool[0,0,0,0,1]),
              NullableArray(ones(Int,5), Bool[0,0,0,1,0])),
              ["a", "b", "c d", "e"])
    @test isequal(_csvread(str1, ','), data)
    coltype_test1 = _csvread(str1,
                            coltypes=Dict("b"=>Nullable{Float64},
                                          "e"=>Nullable{Float64}))
    coltype_test2 = _csvread(str1,
                            coltypes=Dict(2=>Nullable{Float64},
                                          4=>Nullable{Float64}))
    str2 = """
    x,1,1,1
    ,1,1,1
    x,1,1.,1
    x y,1.0,1,
    x,1.0,,1
    """
    coltype_test3 = _csvread(str2, header_exists=false,
                            coltypes=Dict(2=>Nullable{Float64},
                                          4=>Nullable{Float64}))
    @test eltype(coltype_test1[1][2]) == Nullable{Float64}
    @test eltype(coltype_test1[1][4]) == Nullable{Float64}
    @test eltype(coltype_test2[1][2]) == Nullable{Float64}
    @test eltype(coltype_test2[1][4]) == Nullable{Float64}
    @test eltype(coltype_test3[1][2]) == Nullable{Float64}
    @test eltype(coltype_test3[1][4]) == Nullable{Float64}
end
