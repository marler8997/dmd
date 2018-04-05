module dmd.root.

/**
A D string that is also null-terminated.
*/
struct zstring
{
    private string str;

    string toString() const { return str; }
    alias toString this;

    this(string str)
    in { assert(str.ptr[str.length] == '\0'); } body
    {
        this.str = str;
    }

    static zstring literal(string str)()
    {
        // string literals are always null-terminated
        return zstring(str);
    }
}
