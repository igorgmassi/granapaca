using ArchUnitNET.Domain;
using GranaPaCa.Api;
using ArchUnitNET.Loader;
using ArchUnitNET.xUnitV3;
using static ArchUnitNET.Fluent.ArchRuleDefinition;
using Assembly = System.Reflection.Assembly;

namespace GranaPaCa.Tests;

public sealed class ModuleBoundaryTests
{
    private const string ModulePrefix = "GranaPaCa.Modules.";

    // Every module the host references, so a new module is covered without editing this test.
    private static readonly Assembly[] Modules = typeof(Program).Assembly.GetReferencedAssemblies()
        .Where(reference => reference.Name!.StartsWith(ModulePrefix, StringComparison.Ordinal))
        .Select(Assembly.Load)
        .ToArray();

    private static readonly Architecture Architecture =
        new ArchLoader().LoadAssemblies([typeof(Program).Assembly, .. Modules]).Build();

    [Fact]
    public void Code_outside_a_module_uses_only_its_entry_point_and_contracts()
    {
        Assert.NotEmpty(Modules);

        foreach (var module in Modules)
        {
            var root = module.GetName().Name!;
            Types().That().DoNotResideInAssembly(module)
                .Should().NotDependOnAny(Types().That().ResideInAssembly(module)
                    .And().DoNotHaveFullName($"{root}.{root[ModulePrefix.Length..]}Module")
                    .And().DoNotResideInNamespaceOrBelow($"{root}.Contracts"))
                .Because("outside its own project a module is reached only through its entry point and its Contracts namespace")
                .Check(Architecture);
        }
    }
}
