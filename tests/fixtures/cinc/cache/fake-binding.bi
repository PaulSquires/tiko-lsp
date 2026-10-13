'' A fake #cinclude binding: what tiko would write for fake.h.
#pragma once
extern "C"
type FakeColor field = 1
	r as ubyte
	g as ubyte
end type
declare function FakeAdd cdecl alias "FakeAdd" ( byval a as long, byval b as long ) as long
#define FAKE_RED type<FakeColor>(255, 0)
end extern
