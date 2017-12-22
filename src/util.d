module util;

import core.stdc.stdlib : exit;
static import std.stdio;
import std.stdio : File, writefln, writeln;

version(Windows)
{
    auto exeExtension = ".exe";
}
else
{
    auto exeExtension = "";
}

auto tryRun(const(char)[] command, File stdout = std.stdio.stdout)
{
    import std.process : spawnShell, wait;

    if(stdout is std.stdio.stdout)
    {
        writefln("[SHELL] %s", command);
    }
    else
    {
        writefln("[SHELL] %s > %s", command, stdout.name);
    }
    auto pid = spawnShell(command, std.stdio.stdin, stdout);
    auto exitCode = wait(pid);
    writeln("-------------------------------------------------------");
    return exitCode;
}
void run(const(char)[] command, File stdout = std.stdio.stdout)
{
    auto exitCode = tryRun(command, stdout);
    if(exitCode)
    {
        writefln("Command '%s' failed with exit code %s", command, exitCode);
        exit(1);
    }
}

// returns a formatter that will print the given string.  it will print
// it surrounded with quotes if the string contains any spaces.
@property auto formatQuotedIfSpaces(T...)(T args) if(T.length > 0)
{
    struct Formatter
    {
        T args;
        void toString(scope void delegate(const(char)[]) sink) const
        {
            bool useQuotes = false;
            foreach(arg; args)
            {
                import std.string : indexOf;
                if(arg.indexOf(' ') >= 0)
                {
                    useQuotes = true;
                    break;
                }
            }

            if(useQuotes)
            {
                sink("\"");
            }
            foreach(arg; args)
            {
                sink(arg);
            }
            if(useQuotes)
            {
                sink("\"");
            }
        }
    }
    return Formatter(args);
}

@property auto formatDir(const(char)[] dir)
{
    if(dir.length == 0)
    {
        dir = ".";
    }
    return formatQuotedIfSpaces(dir);
}
