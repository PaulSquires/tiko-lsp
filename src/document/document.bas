'' ############################################################################
''  document/document.bas -- one open editor buffer
'' ############################################################################

#include once "document.bi"
#include once "../utils/uri.bi"

constructor TextDocument( )
    this.m_version = 0
    this.m_dirty   = false
    this.m_index.Rebuild( "" )
end constructor

constructor TextDocument( byref uriText as string, byref langId as string, _
                          byval version_ as longint, byref text_ as string )
    this.Reset( uriText, langId, version_, text_ )
end constructor

sub TextDocument.Reset( byref uriText as string, byref langId as string, _
                        byval version_ as longint, byref text_ as string )
    this.m_uri        = uriText
    this.m_path       = UriToPath( uriText )   '' "" for untitled:, git:, and friends
    this.m_languageId = langId
    this.m_version    = version_
    this.m_text       = text_
    this.m_dirty      = false
    this.Invalidate( )
    this.m_index.Rebuild( this.m_text )
end sub

function TextDocument.Uri( ) as string
    return this.m_uri
end function

function TextDocument.FilePath( ) as string
    return this.m_path
end function

function TextDocument.LanguageId( ) as string
    return this.m_languageId
end function

function TextDocument.Version( ) as longint
    return this.m_version
end function

function TextDocument.IsDirty( ) as boolean
    return this.m_dirty
end function

function TextDocument.Text( ) as string
    return this.m_text
end function

function TextDocument.TextLength( ) as longint
    return len(this.m_text)
end function

function TextDocument.LineCount( ) as long
    return this.m_index.LineCount( )
end function

function TextDocument.LineText( byval lineNo as long ) as string
    if( lineNo < 0 orelse lineNo >= this.m_index.LineCount( ) ) then return ""

    dim as longint begin_ = this.m_index.LineStart( lineNo )
    dim as longint stop_  = this.m_index.LineContentEnd( this.m_text, lineNo )
    if( stop_ <= begin_ ) then return ""

    return mid( this.m_text, begin_ + 1, stop_ - begin_ )
end function

sub TextDocument.ReplaceAll( byref text_ as string, byval version_ as longint )
    this.m_text    = text_
    this.m_version = version_
    this.m_dirty   = true
    this.Invalidate( )
    this.m_index.Rebuild( this.m_text )
end sub

sub TextDocument.ApplyRange( byval startLine as long, byval startChar as long, _
                             byval endLine   as long, byval endChar   as long, _
                             byref newText as string, byval version_ as longint )

    dim as longint fromByte = LspPositionToOffset( this.m_text, this.m_index, startLine, startChar )
    dim as longint toByte   = LspPositionToOffset( this.m_text, this.m_index, endLine,   endChar )

    '' A reversed range is malformed but survivable, and some clients emit one
    '' after a racing edit. Normalise rather than drop the change: dropping it
    '' desynchronises the buffer from the editor permanently.
    if( toByte < fromByte ) then swap fromByte, toByte

    dim as string head_ = ""
    dim as string tail_ = ""
    if( fromByte > 0 ) then head_ = left( this.m_text, fromByte )
    if( toByte < len(this.m_text) ) then tail_ = mid( this.m_text, toByte + 1 )

    this.m_text    = head_ & newText & tail_
    this.m_version = version_
    this.m_dirty   = true

    '' The index is rebuilt in full. Patching it in place would have to handle
    '' a terminator split across the edit boundary, and one linear pass over a
    '' document is not what makes a language server slow.
    this.Invalidate( )
    this.m_index.Rebuild( this.m_text )
end sub

sub TextDocument.SetVersion( byval version_ as longint )
    this.m_version = version_
end sub

sub TextDocument.MarkSaved( )
    this.m_dirty = false
end sub

function TextDocument.PositionToOffset( byval lineNo as long, byval character as long ) as longint
    return LspPositionToOffset( this.m_text, this.m_index, lineNo, character )
end function

function TextDocument.OffsetToPosition( byval offset as longint ) as SourcePosition
    return OffsetToSourcePosition( this.m_text, this.m_index, offset )
end function

function TextDocument.Index( ) byref as LineIndex
    return this.m_index
end function

'' ----------------------------------------------------------------------------
''  Cached analysis
'' ----------------------------------------------------------------------------

sub TextDocument.Invalidate( )
    this.m_analysed = false
end sub

sub TextDocument.EnsureAnalysed( )
    if( this.m_analysed ) then exit sub
    this.m_analysed = true
    AnalyzeFull( this.m_text, this.m_tokens, this.m_diags, this.m_symbols )
end sub

function TextDocument.Tokens( ) byref as TokenArray
    this.EnsureAnalysed( )
    return this.m_tokens
end function

function TextDocument.Symbols( ) byref as SymbolTable
    this.EnsureAnalysed( )
    return this.m_symbols
end function

function TextDocument.Diagnostics( ) byref as DiagnosticArray
    this.EnsureAnalysed( )
    return this.m_diags
end function
