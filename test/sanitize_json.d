import std.exception : assumeUnique;
import std.string : startsWith, replace;
import std.format : formattedWrite, format;
import std.json;
import std.getopt;
import std.file : readText;
import std.stdio;

bool keepDeco = false;

void usage()
{
    writeln("Usage: santize_json [--keep-deco] <input-json> [<output-json>]");
}
int main(string[] args)
{
    getopt(args,
        "keep-deco", &keepDeco);
    args = args[1 .. $];
    if (args.length == 0)
    {
        usage();
        return 1;
    }
    string inFilename = args[0];
    File outFile;
    if(args.length == 1)
    {
        outFile = stdout;
    }
    else if(args.length == 2)
    {
        outFile = File(args[1], "w");
    }
    else
    {
        writeln("Error: too many command line arguments");
        return 1;
    }

    auto json = parseJSON(readText(inFilename));
    sanitize(json);

    outFile.write(json.toJSON(true, JSONOptions.doNotEscapeSlashes));
    return 0;
}

void sanitize(JSONValue root)
{
    if (root.type == JSON_TYPE.ARRAY)
    {
        sanitizeSyntaxNode(root);
    }
    else
    {
        assert(root.type == JSON_TYPE.OBJECT);
        auto rootObject = root.object;
        {
            auto compilerInfo = rootObject.get("compilerInfo", JSONValue.init);
            if (compilerInfo.type != JSON_TYPE.NULL)
            {
                sanitizeCompilerInfo(compilerInfo.object);
            }
        }
        {
            auto buildInfo = rootObject.get("buildInfo", JSONValue.init);
            if (buildInfo.type != JSON_TYPE.NULL)
            {
                sanitizeBuildInfo(buildInfo.object);
            }
        }
        {
            auto modules = rootObject.get("modules", JSONValue.init);
            if (modules.type != JSON_TYPE.NULL)
            {
                sanitizeSyntaxNode(modules);
            }
        }
        {
            auto semantics = rootObject.get("semantics", JSONValue.init);
            if (semantics.type != JSON_TYPE.NULL)
            {
                sanitizeSemantics(semantics.object);
            }
        }
    }
}

void removeString(JSONValue* value)
{
    assert(value.type == JSON_TYPE.STRING);
    *value = JSONValue("VALUE_REMOVED_FOR_TEST");
}
void removeNumber(JSONValue* value)
{
    assert(value.type == JSON_TYPE.INTEGER || value.type == JSON_TYPE.UINTEGER);
    *value = JSONValue(0);
}
void removeStringIfExists(JSONValue* value)
{
    if (value !is null)
        removeString(value);
}

void sanitizeCompilerInfo(ref JSONValue[string] buildInfo)
{
    removeString(&buildInfo["binary"]);
    removeString(&buildInfo["version"]);
}
void sanitizeBuildInfo(ref JSONValue[string] buildInfo)
{
    removeString(&buildInfo["cwd"]);
    removeStringIfExists("config" in buildInfo);
    removeStringIfExists("lib" in buildInfo);
    {
        auto importPaths = buildInfo["importPaths"].array;
        foreach(ref path; importPaths)
        {
            path = JSONValue(normalizeFile(path.str));
        }
    }
}
void sanitizeSyntaxNode(ref JSONValue value)
{
    if (value.type == JSON_TYPE.ARRAY)
    {
        foreach (ref element; value.array)
        {
            sanitizeSyntaxNode(element);
        }
    }
    else if(value.type == JSON_TYPE.OBJECT)
    {
        foreach (name; value.object.byKey)
        {
            if (name == "file")
                removeString(&value.object[name]);
            else if (name == "offset")
                removeNumber(&value.object[name]);
            else if (!keepDeco && name == "deco")
                removeString(&value.object[name]);
            else
                sanitizeSyntaxNode(value.object[name]);
        }
    }
}

string getOptionalString(ref JSONValue[string] obj, string name)
{
    auto node = obj.get(name, JSONValue.init);
    if (node.type == JSON_TYPE.NULL)
        return null;
    assert(node.type == JSON_TYPE.STRING, format("got %s where STRING was expected", node.type));
    return node.str;
}

void sanitizeSemantics(ref JSONValue[string] semantics)
{
    import std.array : appender;

    auto modulesArrayPtr = &semantics["modules"].array();
    auto newModules = appender!(JSONValue[])();
    foreach (ref semanticModuleNode; *modulesArrayPtr)
    {
        auto semanticModule = semanticModuleNode.object();
        auto moduleName = semanticModule.getOptionalString("name");
        if(moduleName.startsWith("std.", "core.", "etc.") || moduleName == "object")
        {
           // remove druntime/phobos modules since they can change for each
           // platform
           continue;
        }
        auto fileNode = &semanticModule["file"];
        *fileNode = JSONValue(normalizeFile(fileNode.str));
        newModules.put(JSONValue(semanticModule));
    }
    *modulesArrayPtr = newModules.data;
}

auto normalizeFile(string file)
{
    version(Windows)
        return file.replace("\\", "/");
    return file;
}
