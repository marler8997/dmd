#!/usr/bin/env rund
import core.stdc.stdlib : exit;

import std.array;
import std.string;
import std.algorithm;
import std.conv;
import std.process;
import std.path;
import std.file;
import std.stdio;
alias write = std.stdio.write;

__gshared string[string] globalBuiltins;
__gshared string[string] vars;

void usage()
{
    writeln("Usage: vss <file> <args>...");
}
int main(string[] args)
{
    args = args[1 .. $];
    if (args.length == 0)
    {
        usage();
        return 1;
    }
    globalBuiltins["printCommands"] = "0";
    auto topLevelScript = Script(args[0]);
    foreach (i, arg; args)
    {
        vars[i.to!string] = arg;
    }
    topLevelScript.execute();
    return 0;
}

auto limitArray(T)(T* ptr, T* limit)
in { assert(ptr <= limit); } do
{ return LimitArray!T(ptr, limit); }
LimitArray!T asLimitArray(T)(T[] array)
{
    return LimitArray!T(array.ptr, array.ptr + array.length);
}
struct LimitArray(T)
{
    T* ptr;
    T* limit;
    bool empty() const { return ptr == limit; }
    auto front() inout { return ptr[0]; }
    void popFront() { ptr++; }
    auto asArray() inout { return ptr[0 .. limit-ptr]; }
    static if (is(T == char))
    {
        char[] toString() { return ptr[0 .. limit-ptr]; }
    }
}
void skip(Range, U)(Range* range, U value)
{
    for (;!range.empty && range.front == value; range.popFront)
    { }
}
void until(Range, U)(Range* range, U value)
{
    for (;!range.empty && range.front != value; range.popFront)
    { }
}

T[][] parseArgs(T)(T[] line) { return parseArgs(line.asLimitArray); }
T[][] parseArgs(T)(LimitArray!T line)
{
    //writefln("[DEBUG] parseArgs '%s'", line);
    Appender!(T[][]) args;
    auto rest = line;
    for (;;)
    {
        skip(&rest, ' ');
        if (rest.empty)
            break;
        if (rest.front == '"')
        {
            rest.popFront;
            auto start = rest.ptr;
            until(&rest, '"');
            if (rest.empty)
                errorf("an unterminated double-quoted '\"' string");
            args.put(start[0  .. rest.ptr - start]);
            rest.popFront;
        }
        else
        {
            auto start = rest.ptr;
            rest.popFront;
            until(&rest, ' ');
            args.put(start[0 .. rest.ptr - start]);
        }
    }
    //writefln("[DEBUG] parseArgs '%s' > %s", line, args);
    return args.data;
}

struct Script
{
    static Script* current = null;

    string filename;
    string filenameAbsolute;
    string dirAbsolute;
    string[string] builtins;
    uint lineNumberMin;
    uint lineNumberMax;
    IfState[] ifStack;
    void execute()
    {
        builtins["file"] = filename;
        filenameAbsolute = absolutePath(filename);
        builtins["abs_file"] = filenameAbsolute;
        dirAbsolute = dirName(filenameAbsolute);
        builtins["abs_dir"] = dirAbsolute;

        lineNumberMax = 0;
        auto parentScript = Script.current;
        Script.current = &this;
        scope (exit) Script.current = parentScript;

        const fileContent = FileContent(filename);
        foreach (line; FileContent(filename).byLine)
        {
            lineNumberMin = lineNumberMax + 1;
            lineNumberMax = lineNumberMin + line.count - 1;
            //writefln("line %s '%s'", lineNumber, line);

            auto lineText = line.text.strip().asLimitArray.stripComment();
            // we have to handle conditionals before expansion becuase
            // we don't want to expand the condition if we aren't executing it
            if (handleConditionals(lineText))
                continue;
            if (isCurrentBlockDisabled)
                continue;

            executeLine(lineText.expand.parseArgs);
        }

        if (ifStack.length > 0)
            errorf("missing %s 'fi' terminator(s)", ifStack.length);
    }
}

auto stripComment(T)(LimitArray!T line)
{
    auto start = line.ptr;
    enum QuoteState { none, open, inside, insideQuote }
    auto quoteState = QuoteState.none;
  Loop:
    for (;!line.empty; line.popFront)
    {
        //writefln("c='%s' state=%s", line.front, quoteState);
        final switch (quoteState)
        {
            case QuoteState.none:
                if (line.front == '#')
                    break Loop;
                if (line.front == '"')
                    quoteState = QuoteState.open;
                break;
            case QuoteState.open:
                if (line.front == '"')
                    quoteState = QuoteState.none;
                else
                    quoteState = QuoteState.inside;
                break;
            case QuoteState.inside:
                if (line.front == '"')
                    quoteState = QuoteState.insideQuote;
                break;
            case QuoteState.insideQuote:
                if (line.front == '"')
                    quoteState = QuoteState.inside;
                else
                    quoteState = QuoteState.none;
                break;
        }
    }
    //writefln("stripComment returns '%s'", limitArray(start, line.ptr));
    return limitArray(start, line.ptr);
}

struct LineBuilder(C)
{
    private Appender!(C[]) appender;
    private bool started; // need this because appender could be started AND empty
    void put(C[] part)
    {
        this.started = true;
        appender.put(part);
    }
    auto finish(C[] lastPart)
    {
        if (!started)
            return lastPart;
        appender.put(lastPart);
        return appender.data;
    }
}
struct LineContinuationIterator(C)
{
    struct Result { C[] text; uint count; }

    private char* nextLineStart;
    Result result;
    this(C* ptr) { this.nextLineStart = ptr; popFront(); }
    bool empty() const { return result.text is null; }
    auto front() inout { return result; }
    void popFront()
    {
        LineBuilder!C lineBuilder;
        result.count = 0;
        for (;;)
        {
            if (nextLineStart[0] == '\0')
            {
                result.text = lineBuilder.finish(null);
                return;
            }
            auto saveStart = nextLineStart;
            auto next = nextLineStart;
            for (;;)
            {
                if (next[0] == '\n')
                {
                    nextLineStart = next + 1;
                    break;
                }
                next++;
                if (next[0] == '\0')
                {
                    nextLineStart = next;
                    break;
                }
            }

            result.count++;
            // Check for line continuation '\'
            if (next == saveStart || (next-1)[0] != '\\')
            {
                result.text = lineBuilder.finish(saveStart[0 .. next - saveStart]);
                return;
            }
            lineBuilder.put(saveStart[0 .. next - saveStart - 1]);
        }
    }
}
struct FileContent
{
    string filename;
    char[] text;
    this(string filename)
    {
        this.filename = filename;
        auto file = File(filename, "rb");
        const fileSize = file.size;
        if (fileSize + 1 > size_t.max)
            errorf("file '%s' is too large: %s", filename, fileSize);
        auto buffer = new char[cast(size_t)(fileSize + 1)];
        this.text = buffer[0 .. $-1];
        const length = file.rawRead(this.text).length;
        if (length != this.text.length)
            errorf("rawRead of '%s' with length %s returned %s", filename, this.text.length, length);
        buffer[$-1] = '\0';
    }
    auto byLine()
    {
        return LineContinuationIterator!char(text.ptr);
    }
}

void errorf(T...)(T args)
{
    if (Script.current)
    {
        if (Script.current.lineNumberMin == Script.current.lineNumberMax)
            writef("%s(line %s) ", Script.current.filename, Script.current.lineNumberMin);
        else
            writef("%s(lines %s-%s) ", Script.current.filename, Script.current.lineNumberMin, Script.current.lineNumberMax);
    }
    writefln(args);
    exit(1);
}
bool isCurrentBlockDisabled()
{
    return Script.current.ifStack.length > 0 && !Script.current.ifStack[$-1].currentBlockTrue;
}

// Note: comment has already been removed
bool hasArgs(T)(LimitArray!T str)
{
    foreach (c; str)
    {
        if (c != ' ')
            return true;
    }
    return false;
}

auto expand(T)(T[] s) { return expand(s.asLimitArray); }
auto expand(T)(LimitArray!T s)
{
    auto next = s;
    for (;; next.popFront)
    {
        if (next.empty)
             return s;
        //if (next.front == '#')
        //    return LimitArray!T(s.ptr, next.ptr);
        if (next.front == '$')
            break;
    }
    Appender!(char[]) expanded;
    T* save = s.ptr;
  OuterLoop:
    for (;;)
    {
        expanded.put(save[0 .. next.ptr - save]);
        // next points to '$'
        next.popFront;
        if (next.empty)
            errorf("empty '$' expression");
        if (next.front == '{')
        {
            // TODO: support balanced parens? recursive expansion?
            next.popFront;
            auto start = next.ptr;
            for (;; next.popFront)
            {
                if (next.empty)
                    errorf("unterminated '${...' expression");
                if (next.front == '}')
                    break;
            }
            expanded.put(resolve(start[0 .. next.ptr - start]));
            next.popFront;
        }
        else if (next.front == '(')
        {
            errorf("$(...) not implemented");
        /*
            next.popFront;
            auto parenCount = 1;
            auto start = next.ptr;
            for (;; next.popFront)
            {
                if (next.empty)
                    errorf("unterminated '$(...' expression");
                if (next.front == ')')
                {
                    parenCount--;
                    if (parenCount == 0)
                        break;
                }
            }
            expanded.put(executeForExpand(start[0 .. next.ptr - start].expand.split));
            next.popFront;
            */
        }
        else
        {
            auto start = next.ptr;
            for (; validVarChar(next.front);)
            {
                next.popFront;
                if (next.empty)
                    break;
            }
            if (start == next.ptr)
                errorf("empty '$' expression");
            expanded.put(resolve(start[0 .. next.ptr - start]));
        }
        save = next.ptr;
        for (;; next.popFront)
        {
            if (next.empty/* || next.front == '#'*/)
                break OuterLoop;
            if (next.front == '$')
                break;
        }
    }
    expanded.put(save[0 .. next.ptr - save]);
    return (cast(T[])expanded.data).asLimitArray;
}

// [a-zA-Z0-9_]
bool validVarChar(const char c)
{
    if (c < 'A')
        return (c >= '0' && c <= '9') || c == '.';
    if (c <= 'Z')
        return true;
    if (c == '_')
        return true;
    return (c >= 'a' && c <= 'z');
}
auto resolve(const(char)[] varname)
{
    const dotIndex = varname.indexOf('.');
    if (dotIndex == -1)
    {
        const result = tryResolveBasename(varname);
        if (result)
            return result;
    }
    else
    {
        const obj = varname[0 .. dotIndex];
        const field = varname[dotIndex + 1 .. $];
        if (obj == "opt")
        {
            const result = tryResolveBasename(field);
            return result ? result : "";
        }

        if (obj == "builtin")
        {
            {
                auto result = Script.current.builtins.get(cast(string)field, null);
                if (result)
                    return result;
            }
            {
                auto result = globalBuiltins.get(cast(string)field, null);
                if (result)
                    return result;
            }
        }
        else
        {
            errorf("unknown object '%s' in variable '%s'", obj, varname);
            assert(0);
        }
    }
    errorf("unknown variable '%s'", varname);
    assert(0);
}
private string tryResolveBasename(const(char)[] basename)
{
    {
        auto result = vars.get(cast(string)basename, null);
        if (result)
            return result;
    }
    {
        auto result = environment.get(basename, null);
        if (result)
            return result;
    }
    return null;
}
void setvar(string varname, string value)
{
    const dotIndex = varname.indexOf('.');
    if (dotIndex == -1)
    {
        vars[varname] = value;
    }
    else
    {
        const obj = varname[0 .. dotIndex];
        const field = varname[dotIndex + 1 .. $];
        if (obj == "builtin")
        {
            // TODO: global or local?
            // Script.current.builtins?
            // globalBuiltins?
            globalBuiltins[field] = value;
        }
        else
        {
            errorf("unknown object '%s' in variable '%s'", obj, varname);
            assert(0);
        }
    }
}

void executeLine(T)(T args)
{
    if (args.length == 0)
        return;
    if (tryBuiltin(args))
        return;
    const result = executeCommand(args);
    if (result != 0)
        exit(1);
}

auto executeForExpand(T)(T[] cmd)
{
    errorf("$(...) not implemented");
    //writefln("WARNING: TODO: executeForExpand $(", cmd, ")");
    return "?????";
}


struct Redirects
{
    File out_;
    File err;
}
auto parseRedirect(scope const(char[])[] args, Redirects* redirects)
{
    if (args.length >= 2)
    {
        if (args[$-2] == ">")
            redirects.out_ = File(args[$-1], "wb");
        else if (args[$-2] == "2>")
            redirects.err = File(args[$-1], "wb");
        else if (args[$-2] == "&>")
        {
            redirects.out_ = File(args[$-1], "wb");
            redirects.err = redirects.out_;
        }
        else if (args[$-2] == ">>")
            redirects.out_ = File(args[$-1], "ab");
        else if (args[$-2] == "2>>")
            redirects.err = File(args[$-1], "ab");
        else if (args[$-2] == "&>>")
        {
            redirects.out_ = File(args[$-1], "ab");
            redirects.err = redirects.out_;
        }
        else
            return args;

        return args[0 .. $-2];
    }
    return args;
}

void printCommand(scope const(char[])[] args)
{
    //writefln("printCommands = '%s'", globalBuiltins["printCommands"]);
    if (globalBuiltins["printCommands"] == "1")
        writeln("+ ", args);
}

auto executeCommand(scope const(char[])[] args)
{
    printCommand(args);
    auto redirects = Redirects(stdout, stderr);
    args = parseRedirect(args, &redirects);

    typeof(spawnProcess(args)) result;
    try
    {
        result = spawnProcess(args, stdin, redirects.out_, redirects.err);
    }
    catch (ProcessException e)
    {
        errorf("failed to execute: %s: %s", args, e.msg);
    }
    return wait(result);
}

struct IfState
{
    enum BlockType { if_, elif, else_ }
    BlockType currentBlockType;
    bool currentBlockTrue;
    bool elseEnabled;
    void enterElse()
    {
        if (currentBlockType == BlockType.else_)
            errorf("multiple consecutive 'else' blocks");
        this.currentBlockTrue = elseEnabled;
        this.currentBlockType = BlockType.else_;
    }
}

// Assumption: line does not start with whitespace
// Returns: true if it was a conditional
bool handleConditionals(LimitArray!char line)
{
    if (line.empty)
        return false;

    auto progStart = line.ptr;
    auto rest = line;
    until(&rest, ' ');
    auto prog = progStart[0 .. rest.ptr - progStart];

    if (prog == "if")
    {
        if (isCurrentBlockDisabled)
            Script.current.ifStack ~= IfState(IfState.BlockType.if_, false, false);
        else
        {
            const result = executeCommand(rest.expand.parseArgs);
            const isTrue = (result == 0);
            Script.current.ifStack ~= IfState(IfState.BlockType.if_, isTrue, !isTrue);
        }
    }
    else if (prog == "elif")
    {
        if (Script.current.ifStack.length == 0)
            errorf("found 'elif' without matching 'if'");
        if (Script.current.ifStack[$-1].elseEnabled)
        {
            const result = executeCommand(rest.expand.parseArgs);
            const isTrue = (result == 0);
            if (isTrue)
                Script.current.ifStack[$-1].elseEnabled = false;
            Script.current.ifStack[$-1].currentBlockTrue = isTrue;
        }
        else
        {
            Script.current.ifStack[$-1].currentBlockTrue = false;
        }
        Script.current.ifStack[$-1].currentBlockType = IfState.BlockType.elif;
    }
    else if (prog == "else")
    {
        if (hasArgs(rest))
            errorf("the 'else' directive does not accept any arguments");
        if (Script.current.ifStack.length == 0)
            errorf("found 'else' without matching 'if'");
        Script.current.ifStack[$-1].enterElse();
    }
    else if (prog == "fi")
    {
        if (hasArgs(rest))
            errorf("the 'fi' directive does not accept any arguments");
        if (Script.current.ifStack.length == 0)
            errorf("found 'fi' without a matching 'if'");
        Script.current.ifStack = Script.current.ifStack[0 .. $-1];
    }
    else
        return false; // not handled
    return true; // handled
}

bool tryBuiltin(scope const(char[])[] args)
{
    auto originalArgs = args;
    const prog = args[0];
    args = args[1 .. $];
    if (prog == "exit")
    {
        printCommand(originalArgs);
        if (args.length != 1)
            errorf("the 'exit' builtin command requires 1 argument, an exit code");
        // TODO: nice error message it not an integer
        const exitCode = args[0].to!int;
        exit(exitCode);
        assert(0);
    }

    if (prog == "assert")
    {
        printCommand(originalArgs);
        if (args.length == 0)
        {
            errorf("assert");
            assert(0);
        }
        const result = executeCommand(args);
        if (result != 0)
        {
            errorf("assert failed: ", args);
            assert(0);
        }
    }
    else if (prog == "source")
    {
        printCommand(originalArgs);
        if (args.length != 1)
            errorf("the 'source' builtin command requires 1 argument, but got %s", args.length);
        //const filename = buildPath(dirName(Script.current.filename), args[0]);
        const filename = args[0].idup;
        if (!exists(filename))
            errorf("file '%s' does not exist", filename);
        auto script = Script(filename);
        script.execute();
    }
    else if (prog == "echo")
    {
        printCommand(originalArgs);
        auto redirects = Redirects(stdout, stderr);
        args = parseRedirect(args, &redirects);
        string prefix = "";
        foreach (arg; args)
        {
            redirects.out_.write(prefix, arg);
            prefix = " ";
        }
        redirects.out_.writeln();
    }
    else if (prog == "export")
    {
        printCommand(originalArgs);
        if (args.length != 2)
            errorf("the 'export' builtin takes 2 arguments");
        environment[args[0].idup] = args[1].idup;
    }
    else if (prog == "exportdefault")
    {
        printCommand(originalArgs);
        if (args.length != 2)
            errorf("the 'export' builtin takes 2 arguments");
        if (null is environment.get(args[0], null))
            environment[args[0].idup] = args[1].idup;
    }
    else if (prog == "set")
    {
        printCommand(originalArgs);
        if (args.length != 2)
            errorf("the 'set' builtin takes 2 arguments");
        setvar(args[0].idup, args[1].idup);
    }
    else if (prog == "setdefault")
    {
        printCommand(originalArgs);
        if (args.length != 2)
            errorf("the 'setdefault' builtin takes 2 arguments");
        if (null is vars.get(cast(string)args[0], null))
            vars[args[0].idup] = args[1].idup;
    }
    else
        return false; // not a builtin
    return true; // is a builtin
}
