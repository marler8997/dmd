// meant to be able to link without druntime
extern (C) void _d_dso_registry() { }
extern (C) int main(int argc, char **argv) { return 0; }
