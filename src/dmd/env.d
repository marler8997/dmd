module dmd.env;

import core.stdc.string;
import core.sys.posix.stdlib;
import dmd.globals;
import dmd.root.array;
import dmd.root.rmem;
import dmd.utils;

version (Windows)
    private extern (C) int putenv(const char*) nothrow;

/**
Construct a variable from `name` and `value` and put it in the environment while saving
the previous value of the environment variable into a global list so it can be restored later.
Params:
    name = the name of the variable
    value = the value of the variable
Returns:
    true on error, false on success
*/
bool putenvRestorable(const(char)[] name, const(char)[] value) nothrow
{
    auto var = LocalEnvVar.alloc(name, value);
    const result = var.addToEnvRestorable();
    version (Windows)
        mem.xfree(cast(void*)var.nameValueCStr.ptr);
    else if (result)
        mem.xfree(cast(void*)var.nameValueCStr.ptr);
    return result;
}

/// Holds a `name=value` string that can be put into the global environment.
struct LocalEnvVar
{
    string nameValueCStr;        // The null-terminated `name=value` string that will be passed to `putenv`.
    private size_t equalsIndex;  // index of '=' in nameValueCStr.

    /// The name of the variable
    auto name() const { return nameValueCStr[0 .. equalsIndex]; }

    /// The value of the variable
    auto value() const { return nameValueCStr[equalsIndex + 1 .. $]; }

    /**
    Put this variable in the environment while saving the previous value of the
    environment variable into a global list so it can be restored later.
    Returns:
        true on error, false on success
    */
    bool addToEnvRestorable() const nothrow
    {
        RestorableEnv.save(name);
        return putenv(cast(char*)nameValueCStr.ptr) ? true : false;
    }

    /**
    Allocate a new variable via xmalloc that can be added to the global environment.
    Params:
        name = name of the variable
        value = value of the variable
    Returns:
        a newly allocated variable that can be added to the global environment
    */
    static LocalEnvVar alloc(const(char)[] name, const(char)[] value) nothrow
    {
        const length = name.length + 1 + value.length;
        auto str = (cast(char*)mem.xmalloc(length + 1))[0 .. length];
        str[0 .. name.length] = name[];
        str[name.length] = '=';
        str[name.length + 1 .. length] = value[];
        str.ptr[length] = '\0';
        return LocalEnvVar(cast(string)str, name.length);
    }
}

/// Provides save/restore functionality for environment variables.
struct RestorableEnv
{
    /// Holds the original values of environment variables when they are overwritten.
    private __gshared Array!LocalEnvVar originalVars;

    /// Restore the original environment.
    static void restore()
    {
        foreach (var; originalVars)
        {
            if (putenv(cast(char*)var.nameValueCStr))
                assert(0);
        }
    }

    /// Save the environment variable `name` if not saved already.
    static void save(const(char)[] name) nothrow
    {
        foreach (var; originalVars)
        {
            if (name == var.name)
                return; // already saved
        }
        originalVars.push(LocalEnvVar.alloc(name,
            name.toCStringThen!(n => getenv(n.ptr)).toDString));
    }
}
