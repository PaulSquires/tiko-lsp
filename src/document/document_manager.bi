'' ############################################################################
''  document/document_manager.bi -- every buffer the client has open
''
''  OWNERSHIP: the manager allocates each TextDocument with NEW and frees it in
''  Close(), CloseAll() or its destructor. Callers get a POINTER, which stays
''  valid until that document is closed -- the map stores pointers precisely so
''  a rehash cannot move a document out from under a handler.
'' ############################################################################

#pragma once

#include once "document.bi"

type TextDocumentPtr as TextDocument ptr

'' A container held as a FIELD must be a named instantiation: fbc cannot
'' instantiate a generic written inline in a field declaration.
type DocumentMap as containers.Map( of string, TextDocumentPtr )

type DocumentManager
    private:
        m_docs as DocumentMap

    public:
        declare constructor( )
        declare destructor( )

        '' Registers a buffer. Re-opening a URI that is already open replaces
        '' its content in place -- some clients do that instead of closing
        '' first, and the pointer must not change under anyone holding it.
        declare function Open( byref uriText as string, byref langId as string, _
                               byval version_ as longint, byref text_ as string ) as TextDocumentPtr

        '' NULL when the document is not open. Every handler checks this: a
        '' request for a closed document is normal, not exceptional.
        declare function Find( byref uri as string ) as TextDocumentPtr

        declare function IsOpen  ( byref uri as string ) as boolean
        declare function Close   ( byref uri as string ) as boolean
        declare sub      CloseAll( )
        declare function Count   ( ) as long

        '' A snapshot of the open URIs, for logging and for phase 6's indexer.
        declare function OpenUris( ) as containers.Array( of string )
end type
