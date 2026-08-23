'' ############################################################################
''  workspace/symbol_index.bi -- every symbol in the workspace
''
''  One SymbolTable per file, kept whole rather than flattened, because that is
''  what makes an incremental update cheap: a file changes, its table is
''  replaced, and nothing else is touched. A flat list would have to be
''  rebuilt, or grow holes.
''
''  THE OPEN BUFFER WINS. A file that the editor has open is indexed from the
''  buffer, not from disk -- the same rule as everything else in this server,
''  and the reason a symbol appears in the workspace list as soon as it is
''  typed rather than when it is saved.
'' ############################################################################

#pragma once

#include once "fb/array.bi"
#include once "workspace.bi"
#include once "../analysis/parser.bi"

'' A symbol's NAME range, in LSP coordinates, worked out when the file was
'' indexed.
''
'' Storing the position rather than the byte offset is what lets the index
'' answer without keeping every file's text in memory: converting an offset to
'' a UTF-16 column needs the bytes of that line, and holding a workspace's
'' worth of source to be able to do it later would cost tens of megabytes for
'' a question already answered.
type IndexedRange
    StartLine as long
    StartChar as long
    EndLine   as long
    EndChar   as long
end type

type IndexedRangeArray as FB.Array( of IndexedRange )

'' Where a symbol is: which file, and which entry of that file's table.
type IndexHit
    FileIndex as long
    SymIndex  as long
    Score     as long        '' higher is a better match; see Query
end type

type IndexHitArray as FB.Array( of IndexHit )

type IndexedFile
    Uri        as string
    Path_      as string

    '' The file's IDENTITY: its absolute path, lower-cased. The URI is what
    '' goes back to the client, but two spellings of one path -- the client's
    '' and the scan's -- must be ONE entry, or every symbol in the file is
    '' found twice.
    Key_       as string
    Symbols    as SymbolTable
    Ranges     as IndexedRangeArray   '' one per symbol, aligned by index
    FromBuffer as boolean    '' indexed from an open document, not from disk
end type

type IndexedFileArray as FB.Array( of IndexedFile )

type SymbolIndex
    private:
        m_files as IndexedFileArray

    public:
        declare sub      Clear( )
        declare function FileCount  ( ) as long
        declare function SymbolCount( ) as long

        declare function FileUri ( byval fileIndex as long ) as string
        declare function FilePath( byval fileIndex as long ) as string
        declare function IsFromBuffer( byval fileIndex as long ) as boolean

        '' -1 when that file is not indexed.
        declare function IndexOfUri( byref uri as string ) as long

        '' Adds or REPLACES the entry for `uri`. Analysis happens here, so a
        '' caller never has to know whether this file was seen before.
        declare sub IndexText( byref uri as string, byref path_ as string, _
                               byref text_ as string, byval fromBuffer as boolean = false )

        '' Reads the file and indexes it. False when it could not be read.
        declare function IndexPath( byref path_ as string ) as boolean

        declare sub Remove( byref uri as string )

        '' A symbol, by file and entry. The reference dies with the index.
        declare function SymbolAt( byval fileIndex as long, byval symIndex as long ) byref as SymbolInfo

        '' Its name's range, in LSP line/character coordinates.
        declare function RangeAt( byval fileIndex as long, byval symIndex as long ) as IndexedRange

        '' How many symbols one indexed file declares.
        declare function FileSymbolCount( byval fileIndex as long ) as long

        '' workspace/symbol. Matches case-insensitively, and scores an exact
        '' name above a prefix above a substring above a subsequence, so the
        '' obvious answer is first. An empty query matches everything, which is
        '' what a client sends to populate its picker.
        declare sub Query( byref queryText as string, byval limit as long, byref hits as IndexHitArray )

        '' The best DEFINITION of `lowerName` anywhere in the workspace, or
        '' false. A body beats a DECLARE, and a file the editor has open beats
        '' one read from disk.
        declare function FindDefinition( byref lowerName as string, byref hit as IndexHit ) as boolean
end type

'' Byte offsets of every identifier token in `text_` that matches `lowerName`.
''
'' Kept out of SymbolIndex on purpose: references are answered by re-lexing,
'' not from a stored occurrence list. A list of every identifier in a workspace
'' is tens of megabytes to hold and to keep current, and a "find references" is
'' a deliberate action a user waits for, not something typed against.
declare sub FindIdentifierOffsets( byref text_ as string, byref lowerName as string, _
                                   byref offsets as FB.Array( of long ) )
