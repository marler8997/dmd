// This Makefile snippet detects the OS and the architecture MODEL
// Keep this file in sync between dmd, druntime, phobos, dlang.org and tools
// repositories!
module osmodel;

import std.format  : format;
import std.process : executeShell;

struct OsModel
{
    string os;
    string model;
}

OsModel getOsModel(ushort selectBitMode = ushort.max)
{
    OsModel osModel;

    version(Windows)
    {
        osModel.os = "Windows_NT";
        if(selectBitMode == ushort.max || selectBitMode == 32)
        {
            osModel.model = "32";
        }
        else if(selectBitMode == 64)
        {
            osModel.model = "64";
        }
        else
        {
            assert(0, format("unsupported bit-mode %s", selectBitMode));
        }
    }
    else
    {
        {
            // When running make from XCode it may set environment var OS=MACOS.
            auto osEnvironmentVariable = environment.get("OS", null);
            if(osEnvironmentVariable == "MACOS")
            {
                osModel.os = "osx";
            }
            else
            {
                auto uname = executeShell("uname -s");
                if(uname == "Darwin")
                {
                    osModel.os = "osx";
                    model = executeShell("uname -m");
                }
                else if(uname == "Linux")
                {
                    osModel.os = "linux";
                    model = executeShell("uname -m");
                }
                else if(uname == "FreeBSD")
                {
                    osModel.os = "freebsd";
                    model = executeShell("uname -m");
                }
                else if(uname == "OpenBSD")
                {
                    osModel.os = "openbsd";
                    model = executeShell("uname -m");
                }
                else if(uname == "Solaris" || uname == "SunOS")
                {
                    osModel.os = "solaris";
                    model = executeShell("isainfo -n");
                }
                else
                {
                    assert(0, format("Unrecognized or unsupported OS from uname \"%s\"", uname));
                }
            }
        }
        if(selectBitMode != ushort.max)
        {
            assert(0, "this platform does not support selecting the bit mode");
        }
    }
    if(!osModel.os)
    {
        assert(0, "failed to determine OS");
    }
    if(!osModel.model)
    {
        assert(0, "failed to determine MODEL");
    }
    return osModel;
/+


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
}