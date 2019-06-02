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
the current value of the environment variable.
Returns:
    0 on success, non-zero on failure
*/
int putenvRestorable(const(char)[] name, const(char)[] value) nothrow
{
    auto var = LocalEnvVar.xmalloc(name, value);
    const result = var.putenvRestorable();
    var.xfree(result);
    return result;
}

/// Holds a `VAR=value` string that can be put into the global environment.
struct LocalEnvVar
{
    string nameValueCStr;        // The argument passed to `putenv`.
    private size_t equalsIndex;  // index of '=' in nameValueCStr.

    /// The name of the variable
    auto name() const { return nameValueCStr[0 .. equalsIndex]; }

    /// The value of the variable
    auto value() const { return nameValueCStr[equalsIndex + 1 .. $]; }

    /**
    Put this variable in the environment while saving the current value of the
    environment variable.
    Returns:
        0 on success, non-zero on failure
    */
    int putenvRestorable() const nothrow
    {
        RestorableEnv.save(name);
        return .putenv(cast(char*)nameValueCStr.ptr);
    }

    /**
    Allocate a new variable via xmalloc that can be promoted to the global environment.
    Params:
        name = name of the variable
        value = value of the variable
    Returns:
        a newly allocated variable that can be promoted to the global environment
    */
    static LocalEnvVar xmalloc(const(char)[] name, const(char)[] value) nothrow
    {
        const length = name.length + 1 + value.length;
        auto str = (cast(char*)mem.xmalloc(length + 1))[0 .. length];
        str[0 .. name.length] = name[];
        str[name.length] = '=';
        str[name.length + 1 .. length] = value[];
        str.ptr[length] = '\0';
        return LocalEnvVar(cast(string)str, name.length);
    }

    private void xfree(int putenvResult) const nothrow
    {
        bool doFree;
        version (Windows)
            doFree = true;
        else
        {
            // on posix, when putenv succeeds ownership of the memory is transferred
            // to the global environment
            doFree = (putenvResult != 0);
        }
        if (doFree)
            mem.xfree(cast(void*)nameValueCStr.ptr);
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
            if (0 != putenv(cast(char*)var.nameValueCStr))
                assert(0, "putenv failed");
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
        originalVars.push(LocalEnvVar.xmalloc(name,
            name.toCStringThen!(n => getenv(n.ptr)).toDString));
    }
}
