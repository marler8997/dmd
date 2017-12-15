/**
Detects and sets the macros:

  OS         = one of {osx,linux,freebsd,openbsd,netbsd,solaris}
  MODEL      = one of { 32, 64 }
  MODEL_FLAG = one of { -m32, -m64 }

Note:
  Keep this file in sync between druntime, phobos, and dmd repositories!
Source: https://github.com/dlang/dmd/blob/master/osmodel.mak
*/

module osmodel;

import std.typecons : Nullable;

enum OsEnum
{
    windows,
    osx,
    linux,
    freebsd,
    openbsd,
    netbsd,
    solaris
}
enum ModelEnum { _32, _64 }

private __gshared bool initCalled = false;
private OsEnum globalOS;
private ModelEnum globalModel;

@property OsEnum OS()
{
    assert(initCalled);
    return globalOS;
}
@property ModelEnum MODEL()
{
    assert(initCalled);
    return globalModel;
}

void initOsModel(Nullable!OsEnum os, Nullable!ModelEnum model)
{
    if(initCalled)
    {
        assert(0, "osmodel.init has already been called");
    }
    initCalled = true;
    if(!os.isNull)
    {
        globalOS = os;
    }
    else
    {
        import std.format : format;
        import std.process : executeShell;
        import std.string : strip;
        enum unameCommand = "uname -s";
        auto result = executeShell(unameCommand);
        if(result.status != 0)
            assert(0, format("Error: command '%s' failed (rc=%s)", unameCommand, result.status));
        auto uname = strip(result.output);
            assert(uname.length > 0, format("Error: command '%s' did not return any output", unameCommand));
        if(uname == "Darwin")
            globalOS = OsEnum.osx;
        else if(uname == "Linux")
            globalOS = OsEnum.linux;
        else if(uname == "FreeBSD")
            globalOS = OsEnum.freebsd;
        else if(uname == "OpenBSD")
            globalOS = OsEnum.openbsd;
        else if(uname == "NetBSD")
            globalOS = OsEnum.netbsd;
        else if(uname == "Solaris")
            globalOS = OsEnum.solaris;
        else if(uname == "SunOS")
            globalOS = OsEnum.solaris;
        else
        {
            assert(0, format("Unrecognized or unsupported OS for uname '%s'", uname));
        }
    }
    
    if(!model.isNull)
    {
        globalModel = model;
    }
    else
    {
        final switch(globalOS) with(OsEnum)
        {
        case windows:
            globalModel = ModelEnum._32;
        /*ifeq (Windows_NT,$(OS))
            ifeq ($(findstring WOW64, $(shell uname)),WOW64)
            OS:=win64
            MODEL:=64
            else
            OS:=win32
            MODEL:=32
            endif
        endif
        ifeq (Win_32,$(OS))
            OS:=win32
            MODEL:=32
        endif
        ifeq (Win_64,$(OS))
            OS:=win64
            MODEL:=64
        endif
        */
            break;
        case osx:
            globalModel = ModelEnum._32;
            break;
        case linux:
            globalModel = ModelEnum._32;
            break;
        case freebsd:
            globalModel = ModelEnum._32;
            break;
        case openbsd:
            globalModel = ModelEnum._32;
            break;
        case netbsd:
            globalModel = ModelEnum._32;
            break;
        case solaris:
            globalModel = ModelEnum._32;
            break;
        }
    }
}
    
/+

# When running make from XCode it may set environment var OS=MACOS.
# Adjust it here:
ifeq (MACOS,$(OS))
  OS:=osx
endif

ifeq (,$(MODEL))
  ifeq ($(OS), solaris)
    uname_M:=$(shell isainfo -n)
  else
    uname_M:=$(shell uname -m)
  endif
  ifneq (,$(findstring $(uname_M),x86_64 amd64))
    MODEL:=64
  endif
  ifneq (,$(findstring $(uname_M),i386 i586 i686))
    MODEL:=32
  endif
  ifeq (,$(MODEL))
    $(error Cannot figure 32/64 model from uname -m: $(uname_M))
  endif
endif

MODEL_FLAG:=-m$(MODEL)
+/