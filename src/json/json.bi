'' ############################################################################
''  json/json.bi -- the JSON facade
''
''  Everything the rest of the server knows about JSON is in this file. yyjson
''  appears here and in json.bas and nowhere else, so the library can be
''  replaced without touching the RPC layer, the dispatcher or a handler.
''
''  Ownership is explicit:
''
''      JsonDoc      OWNS a parsed, immutable document. Frees it.
''      JsonValue    BORROWS a node inside a JsonDoc. Copyable, cheap, and
''                   invalid the moment its document dies.
''      JsonBuilder  OWNS a mutable document under construction.
''      JsonNode     BORROWS a node inside a JsonBuilder. Same lifetime rule.
''
''  Nothing in the server ever concatenates JSON text by hand.
'' ############################################################################

#pragma once

#include once "yyjson.bi"

'' ----------------------------------------------------------------------------
''  JsonValue -- a borrowed, read-only view of one node
''
''  Every accessor is total: a call on an absent or wrongly-typed node returns
''  the supplied default rather than failing. That is what makes handler code
''  readable, because LSP payloads are full of optional fields.
'' ----------------------------------------------------------------------------
type JsonValue
    private:
        m_val as yyjson_val ptr

    public:
        declare constructor( )
        declare constructor( byval v as yyjson_val ptr )

        declare function Handle( ) as yyjson_val ptr

        declare function IsValid ( ) as boolean
        declare function IsNull  ( ) as boolean
        declare function IsObject( ) as boolean
        declare function IsArray ( ) as boolean
        declare function IsString( ) as boolean
        declare function IsNumber( ) as boolean
        declare function IsBool  ( ) as boolean

        '' Object access. Member() on a missing key returns an invalid
        '' JsonValue, so chains like Member("a").Member("b") never fault.
        declare function Has   ( byref key as string ) as boolean
        declare function Member( byref key as string ) as JsonValue

        '' Array access. Item() out of range returns an invalid JsonValue.
        '' Count() is the element count of an array and the pair count of an
        '' object; 0 for anything else.
        declare function Count( ) as long
        declare function Item ( byval idx as long ) as JsonValue

        '' Scalar extraction with defaults.
        declare function AsString ( byref dflt as string  = ""    ) as string
        declare function AsLongInt( byval dflt as longint = 0     ) as longint
        declare function AsDouble ( byval dflt as double  = 0.0   ) as double
        declare function AsBoolean( byval dflt as boolean = false ) as boolean
end type

'' ----------------------------------------------------------------------------
''  JsonArrayIterator / JsonArray -- RFC-0002 iteration over an array value
''
''      for each folder in ArrayOf( params.Member( "workspaceFolders" ) )
''          ...
''      next
''
''  The iterator is a separate type rather than a JsonValue member because
''  FreeBASIC cannot resolve the circular by-value return between the two
''  (error 71, incomplete type) -- see docs/architecture.md.
'' ----------------------------------------------------------------------------
type JsonArrayIterator
    private:
        m_arr as yyjson_val ptr
        m_idx as long
        m_max as long

    public:
        declare constructor( )
        declare constructor( byval arr as yyjson_val ptr )
        declare function IsValid ( ) as boolean
        declare function Value   ( ) as JsonValue
        declare sub      MoveNext( )
end type

type JsonArray
    private:
        m_arr as yyjson_val ptr

    public:
        declare constructor( )
        declare constructor( byval v as JsonValue )
        declare function Count      ( ) as long
        declare function GetIterator( ) as JsonArrayIterator
end type

'' Iterating a non-array (or an absent member) yields zero elements.
declare function ArrayOf( byval v as JsonValue ) as JsonArray

'' ----------------------------------------------------------------------------
''  JsonDoc -- an owned, parsed document
''
''  Copy and assignment DEEP-COPY the document, so a JsonDoc may be stored in a
''  container without a double free. A JsonValue taken from the original still
''  points into the original and is NOT rebased onto the copy -- take values
''  from the object you actually hold.
'' ----------------------------------------------------------------------------
type JsonDoc
    private:
        m_doc as yyjson_doc ptr
        m_err as string

    public:
        declare constructor( )
        declare constructor( byref rhs as JsonDoc )
        declare operator let( byref rhs as JsonDoc )
        declare destructor( )

        declare function Parse( byref text_ as string ) as boolean
        declare sub      Clear( )

        declare function IsValid  ( ) as boolean
        declare function Root     ( ) as JsonValue
        declare function ErrorText( ) as string
end type

'' ----------------------------------------------------------------------------
''  JsonNode -- a borrowed handle on a node inside a JsonBuilder
'' ----------------------------------------------------------------------------
type JsonNode
    private:
        m_val as yyjson_mut_val ptr

    public:
        declare constructor( )
        declare constructor( byval v as yyjson_mut_val ptr )
        declare function Handle ( ) as yyjson_mut_val ptr
        declare function IsValid( ) as boolean
end type

'' ----------------------------------------------------------------------------
''  JsonBuilder -- constructs one outgoing document
''
''  Every string handed in is COPIED into the document, so a builder never
''  holds a reference into a FreeBASIC temporary. Serialize() returns the text
''  and the builder still owns the tree.
'' ----------------------------------------------------------------------------
type JsonBuilder
    private:
        m_doc as yyjson_mut_doc ptr

    public:
        declare constructor( )
        declare destructor( )

        declare function IsValid( ) as boolean

        '' -- node factories --------------------------------------------------
        declare function NewObject( ) as JsonNode
        declare function NewArray ( ) as JsonNode
        declare function NewString( byref v as string  ) as JsonNode
        declare function NewInt   ( byval v as longint ) as JsonNode
        declare function NewDouble( byval v as double  ) as JsonNode
        declare function NewBool  ( byval v as boolean ) as JsonNode
        declare function NewNull  ( ) as JsonNode
        '' A DEEP COPY of a parsed value into this document -- what a reply that passes
        '' another program's JSON through needs, since the parsed document dies first.
        declare function CopyOf   ( byval v as JsonValue ) as JsonNode

        '' -- object writers --------------------------------------------------
        declare function SetStr   ( byval obj as JsonNode, byref key as string, byref v as string  ) as boolean
        declare function SetInt   ( byval obj as JsonNode, byref key as string, byval v as longint ) as boolean
        declare function SetDouble( byval obj as JsonNode, byref key as string, byval v as double  ) as boolean
        declare function SetBool  ( byval obj as JsonNode, byref key as string, byval v as boolean ) as boolean
        declare function SetNull  ( byval obj as JsonNode, byref key as string ) as boolean
        declare function SetNode  ( byval obj as JsonNode, byref key as string, byval v as JsonNode ) as boolean

        '' -- array writers ---------------------------------------------------
        declare function PushStr ( byval arr as JsonNode, byref v as string   ) as boolean
        declare function PushInt ( byval arr as JsonNode, byval v as longint  ) as boolean
        declare function PushNode( byval arr as JsonNode, byval v as JsonNode ) as boolean

        '' -- output ----------------------------------------------------------
        declare sub      SetRoot  ( byval root as JsonNode )
        declare function Serialize( byval pretty as boolean = false ) as string
end type

'' ----------------------------------------------------------------------------
''  Free helpers
'' ----------------------------------------------------------------------------

'' Escapes and quotes one string as a JSON scalar. Used by logging and by the
'' tests; the protocol path always goes through JsonBuilder.
declare function JsonQuote( byref v as string ) as string
