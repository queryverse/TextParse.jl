using BenchmarkTools
using TextParse
VERSION >= v"0.7" && using Dates

const SUITE = BenchmarkGroup()

SUITE["util"] = BenchmarkGroup(["string", "unicode"])

our_lastindex(x) = VERSION >= v"0.7" ? lastindex(x) : endof(x)

float64str = "456.254"
float64strlen = our_lastindex(float64str)
negfloat64str = "-456.254"
negfloat64strlen = our_lastindex(negfloat64str)

intstr = "9823345"
intstrlen = our_lastindex(intstr)
negintstr = "-9823345"
negintstrlen = our_lastindex(negintstr)

SUITE["util"]["tryparsenext_base10_digit"] = BenchmarkGroup()
SUITE["util"]["tryparsenext_base10_digit"]["Float64"] = @benchmarkable TextParse.tryparsenext_base10_digit(Float64, $float64str, 3, $float64strlen)
SUITE["util"]["tryparsenext_base10_digit"]["Int64"] = @benchmarkable TextParse.tryparsenext_base10_digit(Int64, $intstr, 3, $intstrlen)

SUITE["util"]["tryparsenext_base10"] = BenchmarkGroup()
SUITE["util"]["tryparsenext_base10"]["Float64"] = @benchmarkable TextParse.tryparsenext_base10(Float64, $float64str, 3, $float64strlen)
SUITE["util"]["tryparsenext_base10"]["Int64"] = @benchmarkable TextParse.tryparsenext_base10(Int64, $intstr, 3, $intstrlen)

SUITE["util"]["tryparsenext_sign"] = BenchmarkGroup()
SUITE["util"]["tryparsenext_sign"]["nosign"] = BenchmarkGroup()
SUITE["util"]["tryparsenext_sign"]["nosign"]["Float64"] = @benchmarkable TextParse.tryparsenext_sign($float64str, 1, $float64strlen)
SUITE["util"]["tryparsenext_sign"]["nosign"]["Int64"] = @benchmarkable TextParse.tryparsenext_sign($intstr, 1, $intstrlen)
SUITE["util"]["tryparsenext_sign"]["neg"] = BenchmarkGroup()
SUITE["util"]["tryparsenext_sign"]["neg"]["Float64"] = @benchmarkable TextParse.tryparsenext_sign($negfloat64str, 1, $negfloat64strlen)
SUITE["util"]["tryparsenext_sign"]["neg"]["Int64"] = @benchmarkable TextParse.tryparsenext_sign($negintstr, 1, $negintstrlen)

whitespacestring = "abc  de"
nowhitespacestring = "abcde"

SUITE["util"]["eatwhitespaces"] = BenchmarkGroup()
SUITE["util"]["eatwhitespaces"]["withwhitespace"] = @benchmarkable TextParse.eatwhitespaces($whitespacestring, 4, $(lastindex(whitespacestring)))
SUITE["util"]["eatwhitespaces"]["nowhitespacestring"] = @benchmarkable TextParse.eatwhitespaces($whitespacestring, 4, $(lastindex(whitespacestring)))

newlinestring = "ab\r\n\r\r"

SUITE["util"]["eatnewlines"] = BenchmarkGroup()
SUITE["util"]["eatnewlines"]["default"] = @benchmarkable TextParse.eatnewlines($newlinestring, 3, $(lastindex(newlinestring)))

SUITE["util"]["getlineend"] = BenchmarkGroup()
SUITE["util"]["getlineend"]["default"] = @benchmarkable TextParse.getlineend($newlinestring)

percentagestring = "35.35%"
percentagestringlen = our_lastindex(percentagestring)
somestring = "foo something,"
somestringlen = our_lastindex(somestring)
somequotedstring =  "\"Owner 2 ”Vicepresident\"\"\""
somequotedstringlen = our_lastindex(somequotedstring)

longfloat64str = "2344345.1232353459389238738435"
longfloat64strlen = our_lastindex(longfloat64str)

tok = TextParse.DateTimeToken(DateTime, dateformat"yyyy-mm-dd HH:MM:SS")
opts = TextParse.LocalOpts('y', false, '"', '\\', false, false)
datetimestr = "1970-02-02 02:20:20"
datetimestrlen = our_lastindex(datetimestr)

SUITE["util"]["tryparsenext"] = BenchmarkGroup()
SUITE["util"]["tryparsenext"]["NumericFloat64"] = @benchmarkable TextParse.tryparsenext($(TextParse.Numeric(Float64)), $float64str,1,$float64strlen)
SUITE["util"]["tryparsenext"]["LongNumericFloat64"] = @benchmarkable TextParse.tryparsenext($(TextParse.Numeric(Float64)), $longfloat64str,1,$longfloat64strlen)
SUITE["util"]["tryparsenext"]["UInt64"] = @benchmarkable TextParse.tryparsenext($(TextParse.Numeric(UInt64)), $intstr,1,$intstrlen)
SUITE["util"]["tryparsenext"]["NegInt64"] = @benchmarkable TextParse.tryparsenext($(TextParse.Numeric(Int64)), $negintstr,1,$negintstrlen)
SUITE["util"]["tryparsenext"]["Percentage"] = @benchmarkable TextParse.tryparsenext($(TextParse.Percentage()), $percentagestring,1,$percentagestringlen, TextParse.default_opts)
SUITE["util"]["tryparsenext"]["StringToken"] = @benchmarkable TextParse.tryparsenext($(TextParse.StringToken(String)), $somestring,1,$somestringlen, TextParse.default_opts)
SUITE["util"]["tryparsenext"]["DateTimeToken"] = @benchmarkable TextParse.tryparsenext($tok, $datetimestr,1,$datetimestrlen, $opts)
SUITE["util"]["tryparsenext"]["QuotedStringToken"] = @benchmarkable TextParse.tryparsenext($(Quoted(String,quotechar='"', escapechar='"')), $somequotedstring)

somefieldstring = " 12,3"
f = TextParse.fromtype(Int)
SUITE["util"]["tryparsenext"]["Field"] = @benchmarkable TextParse.tryparsenext($(TextParse.Field(f)), $somefieldstring)
