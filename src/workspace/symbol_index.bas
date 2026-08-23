'' ############################################################################
''  workspace/symbol_index.bas -- every symbol in the workspace
'' ############################################################################

#include once "symbol_index.bi"
#include once "../utils/uri.bi"
#include once "../utils/position.bi"

sub SymbolIndex.Clear( )
    this.m_files.Clear( )
end sub

function SymbolIndex.FileCount( ) as long
    return this.m_files.Count( )
end function

function SymbolIndex.SymbolCount( ) as long
    dim as long n = 0
    for i as long = 0 to this.m_files.Count( ) - 1
        n += this.m_files[i].Symbols.Count( )
    next
    return n
end function

function SymbolIndex.FileUri( byval fileIndex as long ) as string
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return ""
    return this.m_files[fileIndex].Uri
end function

function SymbolIndex.FilePath( byval fileIndex as long ) as string
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return ""
    return this.m_files[fileIndex].Path_
end function

function SymbolIndex.IsFromBuffer( byval fileIndex as long ) as boolean
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return false
    return this.m_files[fileIndex].FromBuffer
end function

'' The identity of a file, from whichever of the two the caller has.
''
'' NOT the URI. A client sends its own spelling and the workspace scan builds
'' another, and a path written through `build/..` names the same file as one
'' written directly. Comparing absolute paths, case-insensitively as Windows
'' does, is what keeps one file to one entry -- without it a file that is both
'' scanned and opened is indexed twice, and every reference in it is reported
'' twice. That is exactly what the piped session caught.
private function KeyFor( byref uri as string, byref path_ as string ) as string
    dim as string p = path_
    if( len(p) = 0 ) then p = UriToPath( uri )
    if( len(p) = 0 ) then return lcase( uri )
    return lcase( NormalizePath( p ) )
end function

function SymbolIndex.IndexOfUri( byref uri as string ) as long
    dim as string want = KeyFor( uri, "" )
    for i as long = 0 to this.m_files.Count( ) - 1
        if( this.m_files[i].Key_ = want ) then return i
    next
    return -1
end function

function SymbolIndex.SymbolAt( byval fileIndex as long, byval symIndex as long ) byref as SymbolInfo
    static as SymbolInfo empty_
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return empty_
    if( symIndex < 0 orelse symIndex >= this.m_files[fileIndex].Symbols.Count( ) ) then return empty_
    return this.m_files[fileIndex].Symbols.Items[symIndex]
end function

function SymbolIndex.FileSymbolCount( byval fileIndex as long ) as long
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return 0
    return this.m_files[fileIndex].Symbols.Count( )
end function

function SymbolIndex.RangeAt( byval fileIndex as long, byval symIndex as long ) as IndexedRange
    dim as IndexedRange empty_
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return empty_
    if( symIndex < 0 orelse symIndex >= this.m_files[fileIndex].Ranges.Count( ) ) then return empty_
    return this.m_files[fileIndex].Ranges[symIndex]
end function

sub SymbolIndex.IndexText( byref uri as string, byref path_ as string, _
                           byref text_ as string, byval fromBuffer as boolean = false )
    dim as TokenArray tokens
    dim as DiagnosticArray diags
    dim as SymbolTable syms
    AnalyzeFull( text_, tokens, diags, syms )

    '' Every name's range is converted NOW, while the text is in hand. After
    '' this the text is dropped -- see IndexedRange for why.
    dim as LineIndex lines_
    lines_.Rebuild( text_ )

    dim ranges as IndexedRangeArray
    for i as long = 0 to syms.Count( ) - 1
        dim as SourcePosition a = OffsetToSourcePosition( text_, lines_, syms.Items[i].NameStart )
        dim as SourcePosition b = OffsetToSourcePosition( text_, lines_, syms.Items[i].NameEnd )

        dim as IndexedRange r
        r.StartLine = a.Line
        r.StartChar = a.Column
        r.EndLine   = b.Line
        r.EndChar   = b.Column
        ranges.Push( r )
    next

    '' The tokens and the diagnostics are dropped: the index answers "where is
    '' this name declared", and holding a token stream per file would multiply
    '' its memory for nothing. Diagnostics belong to open documents, which
    '' have their own analysis.
    dim as string key_ = KeyFor( uri, path_ )

    dim as long existing = -1
    for i as long = 0 to this.m_files.Count( ) - 1
        if( this.m_files[i].Key_ = key_ ) then
            existing = i
            exit for
        end if
    next

    if( existing >= 0 ) then
        '' The URI is updated too: whoever indexed it LAST is whose spelling
        '' the answers carry, and that is the client whenever the file is open.
        this.m_files[existing].Uri        = uri
        this.m_files[existing].Path_      = path_
        this.m_files[existing].Symbols    = syms
        this.m_files[existing].Ranges     = ranges
        this.m_files[existing].FromBuffer = fromBuffer
        exit sub
    end if

    dim as IndexedFile entry
    entry.Uri        = uri
    entry.Path_      = path_
    entry.Key_       = key_
    entry.Symbols    = syms
    entry.Ranges     = ranges
    entry.FromBuffer = fromBuffer
    this.m_files.Push( entry )
end sub

function SymbolIndex.IndexPath( byref path_ as string ) as boolean
    dim as string body
    if( ReadSourceFile( path_, body ) = false ) then return false

    this.IndexText( PathToUri( path_ ), path_, body, false )
    return true
end function

sub SymbolIndex.Absorb( byref other as SymbolIndex )
    for i as long = 0 to other.m_files.Count( ) - 1
        dim as long existing = -1
        for k as long = 0 to this.m_files.Count( ) - 1
            if( this.m_files[k].Key_ = other.m_files[i].Key_ ) then
                existing = k
                exit for
            end if
        next

        if( existing >= 0 ) then
            this.m_files[existing] = other.m_files[i]
        else
            this.m_files.Push( other.m_files[i] )
        end if
    next
end sub

sub SymbolIndex.Remove( byref uri as string )
    dim as long i = this.IndexOfUri( uri )
    if( i < 0 ) then exit sub
    this.m_files.Remove( i )
end sub

'' ----------------------------------------------------------------------------
''  Query
'' ----------------------------------------------------------------------------

'' Every character of `needle`, in order, somewhere in `hay`. This is what lets
'' "dsym" find "DocumentSymbol", which is how every symbol picker is used.
private function IsSubsequence( byref hay as string, byref needle as string ) as boolean
    dim as long h = 0
    dim as long n = 0

    while( h < len(hay) andalso n < len(needle) )
        if( hay[h] = needle[n] ) then n += 1
        h += 1
    wend

    return n >= len(needle)
end function

private function MatchScore( byref lowerName as string, byref lowerQuery as string ) as long
    if( len(lowerQuery) = 0 ) then return 1

    if( lowerName = lowerQuery ) then return 100
    if( left( lowerName, len(lowerQuery) ) = lowerQuery ) then return 80
    if( instr( lowerName, lowerQuery ) > 0 ) then return 60
    if( IsSubsequence( lowerName, lowerQuery ) ) then return 40
    return 0
end function

sub SymbolIndex.Query( byref queryText as string, byval limit as long, byref hits as IndexHitArray )
    hits.Clear( )

    dim as string q = lcase( trim( queryText ) )
    dim as long cap_ = limit
    if( cap_ <= 0 ) then cap_ = 200

    for f as long = 0 to this.m_files.Count( ) - 1
        for i as long = 0 to this.m_files[f].Symbols.Count( ) - 1
            dim as SymbolInfo s = this.m_files[f].Symbols.Items[i]

            '' Locals never appear in a workspace picker: they are not
            '' addressable from outside the procedure they live in.
            if( s.IsLocal ) then continue for

            dim as long score = MatchScore( s.LowerName, q )
            if( score = 0 ) then continue for

            '' A definition outranks a prototype at the same score.
            if( s.IsDeclaration = false ) then score += 5

            dim as IndexHit hit
            hit.FileIndex = f
            hit.SymIndex  = i
            hit.Score     = score
            hits.Push( hit )
        next
    next

    '' Insertion sort by score, descending. The list is capped straight after,
    '' so this only ever orders what a picker will actually show.
    for i as long = 1 to hits.Count( ) - 1
        dim as IndexHit key_ = hits[i]
        dim as long j = i - 1
        while( j >= 0 andalso hits[j].Score < key_.Score )
            hits[j + 1] = hits[j]
            j -= 1
        wend
        hits[j + 1] = key_
    next

    while( hits.Count( ) > cap_ )
        hits.Pop( )
    wend
end sub

function SymbolIndex.FindDefinition( byref lowerName as string, byref hit as IndexHit ) as boolean
    if( len(lowerName) = 0 ) then return false

    dim as long bestFile = -1
    dim as long bestSym  = -1
    dim as long bestRank = -1

    for f as long = 0 to this.m_files.Count( ) - 1
        for i as long = 0 to this.m_files[f].Symbols.Count( ) - 1
            dim as SymbolInfo s = this.m_files[f].Symbols.Items[i]
            if( s.IsLocal ) then continue for
            if( s.LowerName <> lowerName ) then continue for

            '' A body beats a prototype, and a file the editor has open beats
            '' one read from disk -- the buffer is the truth, and the disk copy
            '' may be a save behind.
            dim as long rank = 0
            if( s.IsDeclaration = false ) then rank += 2
            if( this.m_files[f].FromBuffer ) then rank += 1

            if( rank > bestRank ) then
                bestRank = rank
                bestFile = f
                bestSym  = i
            end if
        next
    next

    if( bestFile < 0 ) then return false

    hit.FileIndex = bestFile
    hit.SymIndex  = bestSym
    hit.Score     = bestRank
    return true
end function

'' ----------------------------------------------------------------------------
''  References
'' ----------------------------------------------------------------------------

sub FindIdentifierOffsets( byref text_ as string, byref lowerName as string, _
                           byref offsets as FB.Array( of long ) )
    offsets.Clear( )
    if( len(lowerName) = 0 ) then exit sub

    '' A whole-text substring test first. Most files in a workspace do not
    '' contain the name at all, and skipping the lexer for those is the
    '' difference between a search that feels instant and one that does not.
    if( instr( lcase( text_ ), lowerName ) = 0 ) then exit sub

    '' Then the lexer, because a substring is not an identifier: `count` occurs
    '' inside `counter`, inside "a count of", and inside ' count them.
    dim as TokenArray tokens
    dim as DiagnosticArray diags
    LexSource( text_, tokens, diags )

    for i as long = 0 to tokens.Count( ) - 1
        if( tokens[i].Kind <> TK_IDENT ) then continue for
        if( lcase( TokenText( text_, tokens[i] ) ) <> lowerName ) then continue for
        offsets.Push( tokens[i].Start_ )
    next
end sub
