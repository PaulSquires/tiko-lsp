'' ############################################################################
''  tests/fake_tiko.bas -- a stand-in for `tiko metadata`
''
''  Answers exactly what tiko-lsp asks -- `metadata --manifest . --format json`,
''  run IN the manifest's directory -- by printing that directory's
''  tiko-metadata.json. Anything else is refused with exit 2, so a server that
''  asks differently, or from the wrong directory, fails the tests that use it.
''  One line to stderr each time, which the server must keep off its stdout.
'' ############################################################################

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
