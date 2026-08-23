'' ############################################################################
''  workspace/symbol_index.bas -- every symbol in the workspace
'' ############################################################################

#include once "symbol_index.bi"
#include once "fb/map.bi"
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

'' The directory part of a path, without its trailing separator. "" when the
'' path has none, which is what a bare file name looks like.
private function DirOf( byref path_ as string ) as string
    for i as long = len(path_) - 1 to 0 step -1
        if( path_[i] = asc( "\" ) orelse path_[i] = asc( "/" ) ) then
            return left( path_, i )
        end if
    next
    return ""
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

    '' The include directives, with their positions converted now for the same
    '' reason the name ranges are: the text is in hand here and nowhere else.
    dim refs as IncludeRefArray
    FindIncludes( text_, tokens, refs )

    dim edges as IncludeEdgeArray
    for i as long = 0 to refs.Count( ) - 1
        dim as SourcePosition a = OffsetToSourcePosition( text_, lines_, refs[i].Start_ )
        dim as SourcePosition b = OffsetToSourcePosition( text_, lines_, refs[i].Start_ + refs[i].Length_ )

        dim as IncludeEdge e
        e.Target    = refs[i].Target
        e.ToFile    = -1          '' filled in by ResolveIncludes
        e.Line      = a.Line
        e.StartChar = a.Column
        e.EndChar   = b.Column
        edges.Push( e )
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
        this.m_files[existing].Includes   = edges
        this.m_files[existing].FromBuffer = fromBuffer
        exit sub
    end if

    dim as IndexedFile entry
    entry.Uri        = uri
    entry.Path_      = path_
    entry.Key_       = key_
    entry.Symbols    = syms
    entry.Ranges     = ranges
    entry.Includes   = edges
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

'' ############################################################################
''  The include graph
'' ############################################################################

sub SymbolIndex.SetSearchPaths( byref paths as PathArray )
    this.m_searchPaths.Clear( )
    for i as long = 0 to paths.Count( ) - 1
        this.m_searchPaths.Push( paths[i] )
    next
end sub

'' A path written in an include, made native and absolute against `base`.
'' `base` would be a reserved word here -- BASE is FreeBASIC's constructor
'' chaining keyword, and a parameter cannot be called one.
private function CandidateKey( byref baseDir as string, byref target as string ) as string
    if( len(baseDir) = 0 orelse len(target) = 0 ) then return ""

    '' FreeBASIC accepts either separator on Windows, and so must this.
    dim as string t = target
    for i as long = 0 to len(t) - 1
        if( t[i] = asc( "/" ) ) then t[i] = asc( "\" )
    next

    return lcase( NormalizePath( baseDir + "\" + t ) )
end function

'' The last component of a path, lower-cased.
private function FileNameOf( byref path_ as string ) as string
    for i as long = len(path_) - 1 to 0 step -1
        if( path_[i] = asc( "\" ) orelse path_[i] = asc( "/" ) ) then
            return lcase( mid( path_, i + 2 ) )
        end if
    next
    return lcase( path_ )
end function

sub SymbolIndex.ResolveIncludes( )
    if( this.m_files.IsEmpty( ) ) then exit sub

    '' One pass to know what exists, so the resolution below is a probe rather
    '' than a scan. Without this a workspace of n files with e includes each
    '' costs n*e*n comparisons -- seconds, on the tree this server is meant to
    '' keep up with.
    dim byKey as FB.Map( of string, long )
    for i as long = 0 to this.m_files.Count( ) - 1
        byKey.Put( this.m_files[i].Key_, i )
    next

    '' And one by FILE NAME, for the last resort below. -1 marks a name two
    '' files share, which is the case where guessing is not allowed.
    dim byName as FB.Map( of string, long )
    for i as long = 0 to this.m_files.Count( ) - 1
        dim as string nm = FileNameOf( this.m_files[i].Path_ )
        if( byName.Contains( nm ) ) then
            byName.Put( nm, -1 )
        else
            byName.Put( nm, i )
        end if
    next

    for i as long = 0 to this.m_files.Count( ) - 1
        dim as string here = DirOf( this.m_files[i].Path_ )

        for k as long = 0 to this.m_files[i].Includes.Count( ) - 1
            dim as long found = -1

            '' RELATIVE TO THE INCLUDER FIRST, which is what fbc does and what
            '' a reader assumes: two directories can each have a `shared.bi`,
            '' and the one next door is the one meant.
            dim as string cand = CandidateKey( here, this.m_files[i].Includes[k].Target )
            if( len(cand) > 0 ) then
                if( byKey.TryGet( cand, found ) = false ) then found = -1
            end if

            '' Then the workspace folders, which stand in for fbc's -i paths.
            '' The server is never told the real ones -- they live in a build
            '' script it does not read -- so this is a guess, and a wrong guess
            '' here shows up as an edge to nowhere rather than as a wrong edge.
            if( found < 0 ) then
                for p as long = 0 to this.m_searchPaths.Count( ) - 1
                    cand = CandidateKey( this.m_searchPaths[p], this.m_files[i].Includes[k].Target )
                    if( len(cand) = 0 ) then continue for
                    if( byKey.TryGet( cand, found ) ) then exit for
                    found = -1
                next
            end if

            '' LAST RESORT: the file NAME, and only when the workspace holds
            '' exactly one file with it.
            ''
            '' This is a guess, and it is the guess that makes the graph worth
            '' having on real code. AfxNova writes `#include once
            '' "AfxNova/DWSTRING.inc"` and relies on an -i path pointing at the
            '' compiler's include directory -- a path this server is never told
            '' and cannot infer. Without this step 4,654 of AfxNova's 4,654
            '' includes are edges to nowhere and the graph knows nothing about
            '' it at all.
            ''
            '' The uniqueness condition is what keeps it honest: two files
            '' called `common.bi` in different folders resolve to NEITHER, and
            '' the file is marked as having an unresolved include -- which is
            '' what every caller treats as "visibility unknown".
            if( found < 0 ) then
                dim as long byname_ = -1
                if( byName.TryGet( FileNameOf( this.m_files[i].Includes[k].Target ), byname_ ) ) then
                    if( byname_ >= 0 andalso byname_ <> i ) then found = byname_
                end if
            end if

            this.m_files[i].Includes[k].ToFile = found
        next
    next
end sub

function SymbolIndex.IncludeCount( byval fileIndex as long ) as long
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return 0
    return this.m_files[fileIndex].Includes.Count( )
end function

function SymbolIndex.IncludeAt( byval fileIndex as long, byval i as long ) as IncludeEdge
    dim as IncludeEdge none_
    none_.ToFile = -1
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return none_
    if( i < 0 orelse i >= this.m_files[fileIndex].Includes.Count( ) ) then return none_
    return this.m_files[fileIndex].Includes[i]
end function

function SymbolIndex.HasUnresolvedIncludes( byval fileIndex as long ) as boolean
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then return false
    for i as long = 0 to this.m_files[fileIndex].Includes.Count( ) - 1
        if( this.m_files[fileIndex].Includes[i].ToFile < 0 ) then return true
    next
    return false
end function

sub SymbolIndex.VisibleFrom( byval fileIndex as long, byref out_ as FB.Array( of long ) )
    out_.Clear( )
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then exit sub

    '' Breadth first, with the queue and the visited set in one array: an entry
    '' is pushed when it is first seen and read when its turn comes, so a cycle
    '' -- which `#include once` exists to survive -- simply never pushes twice.
    dim seen_ as FB.Map( of long, boolean )
    out_.Push( fileIndex )
    seen_.Put( fileIndex, true )

    dim as long at_ = 0
    while( at_ < out_.Count( ) )
        dim as long f = out_[at_]
        at_ += 1

        for i as long = 0 to this.m_files[f].Includes.Count( ) - 1
            dim as long to_ = this.m_files[f].Includes[i].ToFile
            if( to_ < 0 ) then continue for
            if( seen_.Contains( to_ ) ) then continue for
            seen_.Put( to_, true )
            out_.Push( to_ )
        next
    wend
end sub

sub SymbolIndex.IncludedBy( byval fileIndex as long, byref out_ as FB.Array( of long ) )
    out_.Clear( )
    if( fileIndex < 0 orelse fileIndex >= this.m_files.Count( ) ) then exit sub

    '' The reverse direction has no stored edges -- one array of them would
    '' have to be kept correct through every re-index -- so it is walked the
    '' other way round: repeatedly, until a pass adds nothing. Include depth is
    '' small (a header of headers is three or four deep), so this converges in
    '' a handful of passes over an array that is already in cache.
    dim seen_ as FB.Map( of long, boolean )
    out_.Push( fileIndex )
    seen_.Put( fileIndex, true )

    dim as boolean grew = true
    while( grew )
        grew = false

        for f as long = 0 to this.m_files.Count( ) - 1
            if( seen_.Contains( f ) ) then continue for

            for i as long = 0 to this.m_files[f].Includes.Count( ) - 1
                dim as long to_ = this.m_files[f].Includes[i].ToFile
                if( to_ < 0 ) then continue for
                if( seen_.Contains( to_ ) = false ) then continue for

                seen_.Put( f, true )
                out_.Push( f )
                grew = true
                exit for
            next
        next
    wend
end sub

function SymbolIndex.CanSee( byval fromFile as long, byval targetFile as long ) as boolean
    if( fromFile = targetFile ) then return true
    if( fromFile < 0 orelse targetFile < 0 ) then return false

    dim visible as FB.Array( of long )
    this.VisibleFrom( fromFile, visible )
    for i as long = 0 to visible.Count( ) - 1
        if( visible[i] = targetFile ) then return true
    next
    return false
end function

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

function SymbolIndex.FindDefinitionFrom( byval fromFile as long, byref lowerName as string, _
                                        byref hit as IndexHit ) as boolean
    if( fromFile < 0 ) then return this.FindDefinition( lowerName, hit )

    dim visible as FB.Array( of long )
    this.VisibleFrom( fromFile, visible )

    dim as long bestFile  = -1
    dim as long bestSym   = -1
    dim as long bestScore = -1

    for v as long = 0 to visible.Count( ) - 1
        dim as long f = visible[v]

        for i as long = 0 to this.m_files[f].Symbols.Count( ) - 1
            if( this.m_files[f].Symbols.Items[i].LowerName <> lowerName ) then continue for
            if( this.m_files[f].Symbols.Items[i].IsLocal ) then continue for

            '' A body beats a DECLARE, and this file beats one it includes:
            '' the nearer declaration is the one a reader means.
            dim as long score = iif( this.m_files[f].Symbols.Items[i].IsDeclaration, 1, 2 )
            if( f = fromFile ) then score += 4
            if( this.m_files[f].FromBuffer ) then score += 1

            if( score > bestScore ) then
                bestScore = score
                bestFile  = f
                bestSym   = i
            end if
        next
    next

    if( bestFile >= 0 ) then
        hit.FileIndex = bestFile
        hit.SymIndex  = bestSym
        hit.Score     = bestScore
        return true
    end if

    '' Nothing visible declares it. That is NOT the same as nothing declaring
    '' it: an include this server could not resolve, a file outside every
    '' workspace folder, a build that adds a path we never see. Answering with
    '' the workspace-wide best is a guess, and it is a better one than silence.
    return this.FindDefinition( lowerName, hit )
end function

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
