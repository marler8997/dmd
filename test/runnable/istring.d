/*
PERMUTE_ARGS:
*/
import std.conv : text;
void main()
{
    int a = 42;
    assert("a is 42" == text(i"a is $(a)"));
    assert("a + 23 is 65" == text(i"a + 23 is $(a + 23)"));

    // test each type of string literal
    int b = 93;
    assert("42 + 93 = 135" == text(  i"$(a) + $(b) = $(a + b)"));  // double-quote
    assert("42 + 93 = 135" == text( ir"$(a) + $(b) = $(a + b)"));  // wysiwyg
    assert("42 + 93 = 135" == text(  i`$(a) + $(b) = $(a + b)`));  // wysiwyg (alt)
    assert("42 + 93 = 135" == text( iq{$(a) + $(b) = $(a + b)}));  // token
    assert("42 + 93 = 135" == text(iq"!$(a) + $(b) = $(a + b)!")); // delimited

    assert(928 == add(900, 28));
}

string funcCode(string attributes, string returnType, string name, string args, string body)
{
    return text(iq{
    $(attributes) $(returnType) $(name)($(args))
    {
        $(body)
    }
    });
}
mixin(funcCode("pragma(inline)", "int", "add", "int a, int b", "return a + b;"));
