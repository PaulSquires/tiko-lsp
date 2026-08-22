'' ############################################################################
''  document/document.bi -- one open editor buffer
''
''  THE BUFFER IS THE TRUTH, NOT THE FILE. Once a client sends didOpen, the
''  text this object holds is authoritative until didClose, even if the file on
''  disk says something else. Reading the file behind the editor's back is the
''  classic language-server bug: the user types, the analysis lags one save
''  behind, and every position is subtly wrong.
'' ############################################################################

#pragma once

#include once "../utils/position.bi"

type TextDocument
    private:
        m_uri        as string    '' the identity, exactly as the client spelled it
        m_path       as string    '' derived; "" for untitled: and other schemes
        m_languageId as string
        m_version    as longint   '' the client's version, monotonic per document
        m_text       as string    '' UTF-8
        m_index      as LineIndex
        m_dirty      as boolean   '' changed since the last didSave

    public:
        declare constructor( )
        declare constructor( byref uriText as string, byref langId as string, _
                             byval version_ as longint, byref text_ as string )

        '' -- identity and state ----------------------------------------------
        declare function Uri       ( ) as string
        declare function FilePath  ( ) as string
        declare function LanguageId( ) as string
        declare function Version   ( ) as longint
        declare function IsDirty   ( ) as boolean

        '' -- content -----------------------------------------------------------
        declare function Text      ( ) as string
        declare function TextLength( ) as longint
        declare function LineCount ( ) as long
        declare function LineText  ( byval lineNo as long ) as string

        '' -- mutation ----------------------------------------------------------
        declare sub Reset( byref uriText as string, byref langId as string, _
                           byval version_ as longint, byref text_ as string )

        '' Full replacement -- TextDocumentSyncKind.Full, and what didSave
        '' carries when the client includes text.
        declare sub ReplaceAll( byref text_ as string, byval version_ as longint )

        '' Incremental replacement -- TextDocumentSyncKind.Incremental. The
        '' range is in LSP coordinates (0-based line, UTF-16 character) and is
        '' clamped, never rejected: a client that raced ahead of us must not be
        '' able to kill the server.
        declare sub ApplyRange( byval startLine as long, byval startChar as long, _
                                byval endLine   as long, byval endChar   as long, _
                                byref newText as string, byval version_ as longint )

        declare sub SetVersion( byval version_ as longint )
        declare sub MarkSaved ( )

        '' -- coordinates -------------------------------------------------------
        declare function PositionToOffset( byval lineNo as long, byval character as long ) as longint
        declare function OffsetToPosition( byval offset as longint ) as SourcePosition
        declare function Index( ) byref as LineIndex

        '' -- analysis ----------------------------------------------------------
        ''
        '' Phase 3 adds the parse tree, phase 4 the symbol table and phase 3's
        '' diagnostics, each as a typed member with its own lifetime tied to
        '' this document. They are deliberately absent rather than present as
        '' ANY PTR placeholders that nothing would free.
end type
