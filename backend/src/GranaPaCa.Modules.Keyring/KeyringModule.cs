using GranaPaCa.Modules.Keyring.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace GranaPaCa.Modules.Keyring;

public static class KeyringModule
{
    public static IServiceCollection AddKeyringModule(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        // Resolve via IServiceProvider so test overrides (WebApplicationFactory) are applied,
        // and fail fast on startup via MasterKeyStartupValidator (RN-39, ADR-016).
        services.AddSingleton(sp =>
            MasterKeyRing.Load(sp.GetService<IConfiguration>() ?? configuration));
        services.AddHostedService<MasterKeyStartupValidator>();
        services.AddSingleton<IEnvelopeEncryptor, EnvelopeEncryptor>();

        return services;
    }
}
