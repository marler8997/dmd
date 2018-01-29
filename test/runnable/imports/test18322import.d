module test18322import;
void fun(string templateFileFullPath = __FILE_FULL_PATH__,
    string templateFile = __FILE__)(string fileFullPath = __FILE_FULL_PATH__)
{
    version(Windows)
    {
        assert(fileFullPath[1..3] == ":\\");
        assert(templateFileFullPath[1..3] == ":\\");
        enum lastPart = "runnable\\test18322.d";
    }
    else
    {
        assert(fileFullPath[0] == '/');
        assert(templateFileFullPath[0] == '/');
        enum lastPart = "runnable/test18322.d";
    }
    assert(fileFullPath[$ - lastPart.length .. $] == lastPart);
    assert(fileFullPath[$ - templateFile.length .. $] == templateFile);
    assert(templateFileFullPath == fileFullPath);
}
