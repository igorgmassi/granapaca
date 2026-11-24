using Npgsql;

namespace GranaPaCa.Api;

internal static class PostgresConnectionResolver
{
    private const int MinimumPasswordLength = 16;

    private static readonly HashSet<string> DisallowedPasswords = new(StringComparer.OrdinalIgnoreCase)
    {
        "postgres",
        "password",
        "granapaca",
        "admin",
        "root",
        "changeme",
        "secret",
        "1234567890123456",
        "password12345678",
        "qwertyuiop123456",
    };

    public static string ResolveAndValidate(IConfiguration configuration)
    {
        var allowWeakForTests = configuration.GetValue("Database:AllowWeakPasswordForTests", false);

        NpgsqlConnectionStringBuilder builder;
        var explicitConnectionString = configuration.GetConnectionString("Postgres");
        if (!string.IsNullOrWhiteSpace(explicitConnectionString))
        {
            builder = new NpgsqlConnectionStringBuilder(explicitConnectionString);
        }
        else
        {
            var host = configuration["POSTGRES_HOST"];
            var database = configuration["POSTGRES_DB"] ?? "granapaca";
            var username = configuration["POSTGRES_USER"] ?? "granapaca";
            var password = ReadPassword(configuration);

            if (string.IsNullOrWhiteSpace(host) || string.IsNullOrWhiteSpace(password))
            {
                throw new InvalidOperationException(
                    "Set ConnectionStrings__Postgres or POSTGRES_HOST + POSTGRES_PASSWORD_FILE.");
            }

            builder = new NpgsqlConnectionStringBuilder
            {
                Host = host.Trim(),
                Database = database.Trim(),
                Username = username.Trim(),
                Password = password,
            };

            if (int.TryParse(configuration["POSTGRES_PORT"], out var port) && port > 0)
            {
                builder.Port = port;
            }
        }

        if (!allowWeakForTests)
        {
            ValidatePasswordStrength(builder.Password);
        }

        // ADR-015: database session always runs in UTC.
        builder.Timezone = "UTC";
        return builder.ConnectionString;
    }

    internal static void ValidatePasswordStrength(string? password)
    {
        if (string.IsNullOrWhiteSpace(password))
        {
            throw new InvalidOperationException("Database password is required and cannot be empty.");
        }

        var trimmed = password.Trim();
        if (trimmed.Length < MinimumPasswordLength)
        {
            throw new InvalidOperationException(
                $"Database password is too weak: minimum length is {MinimumPasswordLength} characters.");
        }

        if (DisallowedPasswords.Contains(trimmed) || trimmed.Distinct().Count() < 6)
        {
            throw new InvalidOperationException(
                "Database password is too weak: use a randomly generated high-entropy password (e.g. openssl rand -hex 32).");
        }
    }

    private static string? ReadPassword(IConfiguration configuration)
    {
        var passwordFile = configuration["POSTGRES_PASSWORD_FILE"];
        if (!string.IsNullOrWhiteSpace(passwordFile))
        {
            if (!File.Exists(passwordFile))
            {
                throw new InvalidOperationException(
                    $"POSTGRES_PASSWORD_FILE does not exist at '{passwordFile}'.");
            }

            return File.ReadAllText(passwordFile).Trim();
        }

        return configuration["POSTGRES_PASSWORD"]?.Trim();
    }
}
