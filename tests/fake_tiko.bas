'' ############################################################################
''  tests/fake_tiko.bas -- a stand-in for `tiko metadata` and `tiko --print-cincludes`
''
''  Answers exactly what tiko-lsp asks -- `metadata --manifest . --format json`,
''  run IN the manifest's directory -- by printing that directory's
''  tiko-metadata.json; and `--print-cincludes ... file` from the
''  cinclude-answer.txt beside that file (below). Anything else is refused with exit 2, so a server that
''  asks differently, or from the wrong directory, fails the tests that use it.
''  One line to stderr each time, which the server must keep off its stdout.
'' ############################################################################

'' `--print-cincludes [-i dir]... file`: the bindings of file's #cinclude lines, from
'' cinclude-answer.txt beside it -- one `header<TAB>binding` per line, the binding relative
'' to that folder and empty for a header that cannot be imported (tiko then exits 1).
private function JsonText( byref s as string ) as string
    dim as string o = ""
    for i as long = 0 to len( s ) - 1
        if( s[i] = 92 orelse s[i] = 34 ) then o &= chr( 92 )
        o &= chr( s[i] )
    next
    return chr( 34 ) & o & chr( 34 )
end function

if( command( 1 ) = "--print-cincludes" ) then
    dim as long n = 2
    while( len( command( n + 1 ) ) > 0 )
        n += 1
    wend
    dim as string file_ = command( n )
    dim as string dir_ = left( file_, instrrev( file_, any "\/" ) )
    dim as long g = freefile( )
    if( open( dir_ & "cinclude-answer.txt" for input as #g ) <> 0 ) then
        open err for output as #1
        print #1, "fake_tiko: no cinclude-answer.txt beside " & file_
        close #1
        end 2
    end if
    dim as string o = "{" & JsonText( "format" ) & ":1," & JsonText( "cincludes" ) & ":["
    dim as long lineNo = 0, rc = 0
    dim as string ln
    while( eof( g ) = false )
        line input #g, ln
        ln = trim( ln, any chr(13) )
        if( len( ln ) = 0 ) then continue while
        lineNo += 1
        dim as long t = instr( ln, chr(9) )
        dim as string header = left( ln, t - 1 ), rel = mid( ln, t + 1 )
        if( lineNo > 1 ) then o &= ","
        o &= "{" & JsonText( "file" ) & ":" & JsonText( file_ ) & "," & _
             JsonText( "line" ) & ":" & lineNo & "," & _
             JsonText( "header" ) & ":" & JsonText( header ) & "," & JsonText( "binding" ) & ":"
        if( len( rel ) ) then
            o &= JsonText( dir_ & rel ) & "}"
        else
            o &= JsonText( "" ) & "," & JsonText( "error" ) & ":" & _
                 JsonText( "unable to import C header " & header ) & "}"
            rc = 1
        end if
    wend
    close #g
    print o & "]}"
    end rc
end if

dim as string want = "metadata --manifest . --format json"
dim as string got = command( 1 ) & " " & command( 2 ) & " " & command( 3 ) & " " & _
                    command( 4 ) & " " & command( 5 )
if( got <> want orelse len( command( 6 ) ) > 0 ) then
    open err for output as #1
    print #1, "fake_tiko: unexpected arguments: " & command( )
    close #1
    end 2
end if

dim as long f = freefile( )
if( open( "tiko-metadata.json" for binary access read as #f ) <> 0 ) then
    open err for output as #1
    print #1, "fake_tiko: no tiko-metadata.json in " & curdir( )
    close #1
    end 2
end if
dim as string text_ = space( lof( f ) )
get #f, , text_
close #f

open err for output as #1
print #1, "fake_tiko: answered for " & curdir( )
close #1
print text_;
end 0
