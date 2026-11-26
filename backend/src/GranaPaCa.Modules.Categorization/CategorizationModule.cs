using System.Data;
using System.Security.Claims;
using Dapper;
using GranaPaCa.Modules.Categorization.Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using NpgsqlTypes;

namespace GranaPaCa.Modules.Categorization;

public static class CategorizationModule
{
    public static IServiceCollection AddCategorizationModule(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        services.AddSingleton<ProfileCatalog>();
        services.AddSingleton<ICategorizationEngine, CategorizationEngine>();
        return services;
    }

    public static IEndpointRouteBuilder MapCategorizationEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var profilesGroup = endpoints.MapGroup("/api/v1/profiles").RequireAuthorization();

        profilesGroup.MapGet("/catalog", async (
            ClaimsPrincipal user,
            ProfileCatalog catalog,
            NpgsqlDataSource dataSource,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            var saved = await connection.QuerySingleOrDefaultAsync<SavedProfileConfigRow>(new CommandDefinition(
                """
                SELECT
                    occupations AS Occupations,
                    home_traits AS HomeTraits,
                    transport_modes AS TransportModes
                FROM categorization.profile_config
                WHERE household_id = @HouseholdId
                """,
                new { HouseholdId = householdId },
                cancellationToken: cancellationToken));

            var snapshot = catalog.GetCatalog();
            return Results.Ok(new ProfileCatalogResponse(
                snapshot.Occupations,
                snapshot.HomeTraits,
                snapshot.TransportModes,
                new ProfileSelectionDto(
                    saved?.Occupations ?? [],
                    saved?.HomeTraits ?? [],
                    saved?.TransportModes ?? [])));
        });

        profilesGroup.MapPost("/preview", (
            ProfilePreviewRequest request,
            ClaimsPrincipal user,
            ProfileCatalog catalog) =>
        {
            if (!TryGetHouseholdId(user, out _))
            {
                return Results.Unauthorized();
            }

            var rules = catalog.PreviewRules(
                request.Occupations ?? [],
                request.HomeTraits ?? [],
                request.TransportModes ?? []);

            return Results.Ok(new ProfilePreviewResponse(rules));
        });

        profilesGroup.MapPut("", async (
            SaveProfilesRequest request,
            ClaimsPrincipal user,
            ProfileCatalog catalog,
            NpgsqlDataSource dataSource,
            IServiceProvider serviceProvider,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var occupations = NormalizeIdArray(request.Occupations);
            var homeTraits = NormalizeIdArray(request.HomeTraits);
            var transportModes = NormalizeIdArray(request.TransportModes);

            var candidates = catalog.PreviewRules(occupations, homeTraits, transportModes);
            var acceptedSet = new HashSet<string>(
                request.AcceptedRuleIds ?? [],
                StringComparer.OrdinalIgnoreCase);

            var selectedTemplates = candidates
                .Where(rule => acceptedSet.Contains(rule.TemplateId))
                .ToList();

            var savedRules = new List<RuleDto>(selectedTemplates.Count);

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO categorization.profile_config (
                    household_id,
                    occupations,
                    home_traits,
                    transport_modes,
                    updated_at
                )
                VALUES (
                    @HouseholdId,
                    @Occupations,
                    @HomeTraits,
                    @TransportModes,
                    now()
                )
                ON CONFLICT (household_id) DO UPDATE
                SET occupations = EXCLUDED.occupations,
                    home_traits = EXCLUDED.home_traits,
                    transport_modes = EXCLUDED.transport_modes,
                    updated_at = now()
                """,
                new
                {
                    HouseholdId = householdId,
                    Occupations = new TextArrayParameter(occupations),
                    HomeTraits = new TextArrayParameter(homeTraits),
                    TransportModes = new TextArrayParameter(transportModes)
                },
                transaction: transaction,
                cancellationToken: cancellationToken));

            await connection.ExecuteAsync(new CommandDefinition(
                """
                DELETE FROM categorization.rule
                WHERE household_id = @HouseholdId
                  AND layer = 'profile'
                """,
                new { HouseholdId = householdId },
                transaction: transaction,
                cancellationToken: cancellationToken));

            foreach (var template in selectedTemplates)
            {
                var ruleId = Guid.CreateVersion7();
                var createdAt = await connection.ExecuteScalarAsync<DateTimeOffset>(new CommandDefinition(
                    """
                    INSERT INTO categorization.rule (
                        id,
                        household_id,
                        layer,
                        priority,
                        name,
                        explanation,
                        match_pattern,
                        category,
                        essentiality,
                        brand,
                        is_active
                    )
                    VALUES (
                        @Id,
                        @HouseholdId,
                        'profile',
                        @Priority,
                        @Name,
                        @Explanation,
                        @MatchPattern,
                        @Category,
                        @Essentiality,
                        @Brand,
                        true
                    )
                    RETURNING created_at
                    """,
                    new
                    {
                        Id = ruleId,
                        HouseholdId = householdId,
                        template.Priority,
                        template.Name,
                        template.Explanation,
                        template.MatchPattern,
                        template.Category,
                        template.Essentiality,
                        template.Brand
                    },
                    transaction: transaction,
                    cancellationToken: cancellationToken));

                savedRules.Add(new RuleDto(
                    ruleId,
                    "profile",
                    template.Priority,
                    template.Name,
                    template.Explanation,
                    null,
                    null,
                    template.MatchPattern,
                    template.Category,
                    template.Essentiality,
                    template.Brand,
                    true,
                    createdAt,
                    0));
            }

            await transaction.CommitAsync(cancellationToken);

            var reclassifier = serviceProvider.GetService<ITransactionReclassifier>();
            var reclassifiedCount = reclassifier is null
                ? 0
                : await reclassifier.ReclassifyHouseholdAsync(householdId, cancellationToken);

            if (reclassifier is not null && savedRules.Count > 0)
            {
                var counts = await reclassifier.CountRuleMatchesAsync(householdId, cancellationToken);
                savedRules = savedRules
                    .Select(rule => rule with { MatchCount = counts.GetValueOrDefault(rule.Id, 0) })
                    .ToList();
            }

            return Results.Ok(new SaveProfilesResponse(savedRules, savedRules.Count, reclassifiedCount));
        });

        var rulesGroup = endpoints.MapGroup("/api/v1/rules").RequireAuthorization();

        rulesGroup.MapGet("", async (
            ClaimsPrincipal user,
            NpgsqlDataSource dataSource,
            IServiceProvider serviceProvider,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            var rows = (await connection.QueryAsync<RuleRow>(new CommandDefinition(
                """
                SELECT
                    id AS Id,
                    layer AS Layer,
                    priority AS Priority,
                    name AS Name,
                    explanation AS Explanation,
                    match_cnpj AS MatchCnpj,
                    match_merchant_normalized AS MatchMerchantNormalized,
                    match_pattern AS MatchPattern,
                    category AS Category,
                    essentiality AS Essentiality,
                    brand AS Brand,
                    is_active AS IsActive,
                    created_at AS CreatedAt
                FROM categorization.rule
                WHERE household_id = @HouseholdId
                  AND layer IN ('user', 'profile')
                ORDER BY
                    CASE layer WHEN 'user' THEN 1 WHEN 'profile' THEN 2 ELSE 3 END,
                    priority ASC,
                    created_at ASC,
                    id ASC
                """,
                new { HouseholdId = householdId },
                cancellationToken: cancellationToken))).ToList();

            var reclassifier = serviceProvider.GetService<ITransactionReclassifier>();
            var matchCounts = reclassifier is null
                ? new Dictionary<Guid, int>()
                : await reclassifier.CountRuleMatchesAsync(householdId, cancellationToken);

            var items = rows
                .Select(row => new RuleDto(
                    row.Id,
                    row.Layer,
                    row.Priority,
                    row.Name,
                    row.Explanation,
                    row.MatchCnpj,
                    row.MatchMerchantNormalized,
                    row.MatchPattern,
                    row.Category,
                    row.Essentiality,
                    row.Brand,
                    row.IsActive,
                    row.CreatedAt,
                    matchCounts.GetValueOrDefault(row.Id, 0)))
                .ToList();

            return Results.Ok(new RulesListResponse(items));
        });

        rulesGroup.MapPost("", async (
            CreateRuleRequest request,
            ClaimsPrincipal user,
            NpgsqlDataSource dataSource,
            IServiceProvider serviceProvider,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            string? normalizedCnpj = null;
            if (!string.IsNullOrWhiteSpace(request.MatchCnpj))
            {
                normalizedCnpj = MerchantNormalizer.NormalizeCnpj(request.MatchCnpj);
                if (normalizedCnpj is null)
                {
                    return Results.BadRequest(new { error = "CNPJ inválido; informe 14 dígitos." });
                }
            }

            var rawMerchant = request.MatchMerchantNormalized ?? request.MatchMerchant;
            var normalizedMerchant = string.IsNullOrWhiteSpace(rawMerchant)
                ? null
                : MerchantNormalizer.NormalizeDescription(rawMerchant);
            if (string.IsNullOrEmpty(normalizedMerchant))
            {
                normalizedMerchant = null;
            }

            var matchPattern = NormalizePattern(request.MatchPattern);

            if (normalizedCnpj is null && normalizedMerchant is null && matchPattern is null)
            {
                return Results.BadRequest(new
                {
                    error = "Informe ao menos um critério de correspondência (CNPJ, nome do estabelecimento ou padrão)."
                });
            }

            if (!TaxonomyConstants.TryNormalizeCategory(request.Category, out var category))
            {
                return Results.BadRequest(new { error = "Categoria inválida." });
            }

            if (!TaxonomyConstants.TryNormalizeEssentiality(request.Essentiality, out var essentiality))
            {
                return Results.BadRequest(new
                {
                    error = "Essencialidade inválida; use essential, important ou flexible."
                });
            }

            var brand = string.IsNullOrWhiteSpace(request.Brand) ? null : request.Brand.Trim();
            if (category is null && essentiality is null && brand is null)
            {
                return Results.BadRequest(new
                {
                    error = "Informe ao menos um resultado para a regra (categoria, essencialidade ou marca)."
                });
            }

            var name = string.IsNullOrWhiteSpace(request.Name)
                ? BuildDefaultRuleName(normalizedMerchant, matchPattern, normalizedCnpj)
                : request.Name.Trim();

            var explanation = string.IsNullOrWhiteSpace(request.Explanation)
                ? "Regra personalizada criada por você."
                : request.Explanation.Trim();

            var priority = request.Priority ?? 100;
            var id = Guid.CreateVersion7();

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            var createdAt = await connection.ExecuteScalarAsync<DateTimeOffset>(new CommandDefinition(
                """
                INSERT INTO categorization.rule (
                    id,
                    household_id,
                    layer,
                    priority,
                    name,
                    explanation,
                    match_cnpj,
                    match_merchant_normalized,
                    match_pattern,
                    category,
                    essentiality,
                    brand,
                    is_active
                )
                VALUES (
                    @Id,
                    @HouseholdId,
                    'user',
                    @Priority,
                    @Name,
                    @Explanation,
                    @MatchCnpj,
                    @MatchMerchantNormalized,
                    @MatchPattern,
                    @Category,
                    @Essentiality,
                    @Brand,
                    true
                )
                RETURNING created_at
                """,
                new
                {
                    Id = id,
                    HouseholdId = householdId,
                    Priority = priority,
                    Name = name,
                    Explanation = explanation,
                    MatchCnpj = normalizedCnpj,
                    MatchMerchantNormalized = normalizedMerchant,
                    MatchPattern = matchPattern,
                    Category = category,
                    Essentiality = essentiality,
                    Brand = brand
                },
                cancellationToken: cancellationToken));

            var reclassifier = serviceProvider.GetService<ITransactionReclassifier>();
            var reclassifiedCount = reclassifier is null
                ? 0
                : await reclassifier.ReclassifyHouseholdAsync(householdId, cancellationToken);

            var matchCount = 0;
            if (reclassifier is not null)
            {
                var counts = await reclassifier.CountRuleMatchesAsync(householdId, cancellationToken);
                matchCount = counts.GetValueOrDefault(id, 0);
            }

            var response = new RuleMutationResponse(
                id,
                "user",
                priority,
                name,
                explanation,
                normalizedCnpj,
                normalizedMerchant,
                matchPattern,
                category,
                essentiality,
                brand,
                true,
                createdAt,
                matchCount,
                reclassifiedCount);

            return Results.Created($"/api/v1/rules/{id}", response);
        });

        rulesGroup.MapPatch("/{id:guid}", async (
            Guid id,
            UpdateRuleRequest request,
            ClaimsPrincipal user,
            NpgsqlDataSource dataSource,
            IServiceProvider serviceProvider,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            var existing = await connection.QuerySingleOrDefaultAsync<RuleRow>(new CommandDefinition(
                """
                SELECT
                    id AS Id,
                    layer AS Layer,
                    priority AS Priority,
                    name AS Name,
                    explanation AS Explanation,
                    match_cnpj AS MatchCnpj,
                    match_merchant_normalized AS MatchMerchantNormalized,
                    match_pattern AS MatchPattern,
                    category AS Category,
                    essentiality AS Essentiality,
                    brand AS Brand,
                    is_active AS IsActive,
                    created_at AS CreatedAt
                FROM categorization.rule
                WHERE id = @Id
                  AND household_id = @HouseholdId
                """,
                new { Id = id, HouseholdId = householdId },
                cancellationToken: cancellationToken));

            if (existing is null)
            {
                return Results.NotFound();
            }

            string? category = existing.Category;
            if (request.Category is not null)
            {
                if (!TaxonomyConstants.TryNormalizeCategory(request.Category, out category))
                {
                    return Results.BadRequest(new { error = "Categoria inválida." });
                }
            }

            string? essentiality = existing.Essentiality;
            if (request.Essentiality is not null)
            {
                if (!TaxonomyConstants.TryNormalizeEssentiality(request.Essentiality, out essentiality))
                {
                    return Results.BadRequest(new
                    {
                        error = "Essencialidade inválida; use essential, important ou flexible."
                    });
                }
            }

            var isActive = request.IsActive ?? existing.IsActive;
            var name = string.IsNullOrWhiteSpace(request.Name) ? existing.Name : request.Name.Trim();
            var explanation = string.IsNullOrWhiteSpace(request.Explanation)
                ? existing.Explanation
                : request.Explanation.Trim();
            var brand = request.Brand is null
                ? existing.Brand
                : (string.IsNullOrWhiteSpace(request.Brand) ? null : request.Brand.Trim());

            if (category is null && essentiality is null && brand is null)
            {
                return Results.BadRequest(new
                {
                    error = "Informe ao menos um resultado para a regra (categoria, essencialidade ou marca)."
                });
            }

            var priority = request.Priority ?? existing.Priority;

            await connection.ExecuteAsync(new CommandDefinition(
                """
                UPDATE categorization.rule
                SET is_active = @IsActive,
                    name = @Name,
                    explanation = @Explanation,
                    category = @Category,
                    essentiality = @Essentiality,
                    brand = @Brand,
                    priority = @Priority
                WHERE id = @Id
                  AND household_id = @HouseholdId
                """,
                new
                {
                    Id = id,
                    HouseholdId = householdId,
                    IsActive = isActive,
                    Name = name,
                    Explanation = explanation,
                    Category = category,
                    Essentiality = essentiality,
                    Brand = brand,
                    Priority = priority
                },
                cancellationToken: cancellationToken));

            var reclassifier = serviceProvider.GetService<ITransactionReclassifier>();
            var reclassifiedCount = reclassifier is null
                ? 0
                : await reclassifier.ReclassifyHouseholdAsync(householdId, cancellationToken);

            var matchCount = 0;
            if (reclassifier is not null)
            {
                var counts = await reclassifier.CountRuleMatchesAsync(householdId, cancellationToken);
                matchCount = counts.GetValueOrDefault(id, 0);
            }

            return Results.Ok(new RuleMutationResponse(
                existing.Id,
                existing.Layer,
                priority,
                name,
                explanation,
                existing.MatchCnpj,
                existing.MatchMerchantNormalized,
                existing.MatchPattern,
                category,
                essentiality,
                brand,
                isActive,
                existing.CreatedAt,
                matchCount,
                reclassifiedCount));
        });

        rulesGroup.MapDelete("/{id:guid}", async (
            Guid id,
            ClaimsPrincipal user,
            NpgsqlDataSource dataSource,
            IServiceProvider serviceProvider,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            var affected = await connection.ExecuteAsync(new CommandDefinition(
                """
                DELETE FROM categorization.rule
                WHERE id = @Id
                  AND household_id = @HouseholdId
                """,
                new { Id = id, HouseholdId = householdId },
                cancellationToken: cancellationToken));

            if (affected == 0)
            {
                return Results.NotFound();
            }

            var reclassifier = serviceProvider.GetService<ITransactionReclassifier>();
            if (reclassifier is not null)
            {
                await reclassifier.ReclassifyHouseholdAsync(householdId, cancellationToken);
            }

            return Results.NoContent();
        });

        return endpoints;
    }

    private static bool TryGetHouseholdId(ClaimsPrincipal user, out Guid householdId)
    {
        var raw = user.FindFirst("household_id")?.Value;
        return Guid.TryParse(raw, out householdId);
    }

    private static string[] NormalizeIdArray(IReadOnlyCollection<string>? values)
    {
        if (values is null || values.Count == 0)
        {
            return [];
        }

        return values
            .Where(v => !string.IsNullOrWhiteSpace(v))
            .Select(v => v.Trim().ToLowerInvariant())
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }

    private static string? NormalizePattern(string? pattern)
    {
        if (string.IsNullOrWhiteSpace(pattern))
        {
            return null;
        }

        var parts = pattern.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part => part.StartsWith("category:", StringComparison.OrdinalIgnoreCase)
                ? $"category:{part["category:".Length..].Trim().ToLowerInvariant()}"
                : MerchantNormalizer.NormalizeDescription(part))
            .Where(part => !string.IsNullOrWhiteSpace(part))
            .Distinct(StringComparer.Ordinal)
            .ToArray();

        return parts.Length == 0 ? null : string.Join('|', parts);
    }

    private static string BuildDefaultRuleName(
        string? normalizedMerchant,
        string? matchPattern,
        string? normalizedCnpj)
    {
        if (!string.IsNullOrWhiteSpace(normalizedMerchant))
        {
            return $"Regra para {normalizedMerchant}";
        }

        if (!string.IsNullOrWhiteSpace(matchPattern))
        {
            return $"Regra para {matchPattern}";
        }

        return $"Regra para CNPJ {normalizedCnpj}";
    }
}

internal sealed record SavedProfileConfigRow(
    string[] Occupations,
    string[] HomeTraits,
    string[] TransportModes);

internal sealed record ProfileSelectionDto(
    IReadOnlyList<string> Occupations,
    IReadOnlyList<string> HomeTraits,
    IReadOnlyList<string> TransportModes);

internal sealed record ProfileCatalogResponse(
    IReadOnlyList<ProfileEntry> Occupations,
    IReadOnlyList<ProfileEntry> HomeTraits,
    IReadOnlyList<ProfileEntry> TransportModes,
    ProfileSelectionDto CurrentSelection);

internal sealed record ProfilePreviewRequest(
    IReadOnlyList<string>? Occupations,
    IReadOnlyList<string>? HomeTraits,
    IReadOnlyList<string>? TransportModes);

internal sealed record ProfilePreviewResponse(
    IReadOnlyList<ProfileRuleTemplate> Rules);

internal sealed record SaveProfilesRequest(
    IReadOnlyList<string>? Occupations,
    IReadOnlyList<string>? HomeTraits,
    IReadOnlyList<string>? TransportModes,
    IReadOnlyList<string>? AcceptedRuleIds);

internal sealed record SaveProfilesResponse(
    IReadOnlyList<RuleDto> SavedRules,
    int SavedRuleCount,
    int ReclassifiedCount);

internal sealed record RuleRow(
    Guid Id,
    string Layer,
    int Priority,
    string Name,
    string Explanation,
    string? MatchCnpj,
    string? MatchMerchantNormalized,
    string? MatchPattern,
    string? Category,
    string? Essentiality,
    string? Brand,
    bool IsActive,
    DateTimeOffset CreatedAt);

internal sealed record RuleDto(
    Guid Id,
    string Layer,
    int Priority,
    string Name,
    string Explanation,
    string? MatchCnpj,
    string? MatchMerchantNormalized,
    string? MatchPattern,
    string? Category,
    string? Essentiality,
    string? Brand,
    bool IsActive,
    DateTimeOffset CreatedAt,
    int MatchCount);

internal sealed record RulesListResponse(
    IReadOnlyList<RuleDto> Items);

internal sealed record CreateRuleRequest(
    string? Name,
    string? Explanation,
    string? MatchCnpj,
    string? MatchMerchant,
    string? MatchMerchantNormalized,
    string? MatchPattern,
    string? Category,
    string? Essentiality,
    string? Brand,
    int? Priority);

internal sealed record UpdateRuleRequest(
    bool? IsActive,
    string? Name,
    string? Explanation,
    string? Category,
    string? Essentiality,
    string? Brand,
    int? Priority);

internal sealed record RuleMutationResponse(
    Guid Id,
    string Layer,
    int Priority,
    string Name,
    string Explanation,
    string? MatchCnpj,
    string? MatchMerchantNormalized,
    string? MatchPattern,
    string? Category,
    string? Essentiality,
    string? Brand,
    bool IsActive,
    DateTimeOffset CreatedAt,
    int MatchCount,
    int ReclassifiedCount);

internal sealed class TextArrayParameter(string[] values) : SqlMapper.ICustomQueryParameter
{
    public void AddParameter(IDbCommand command, string name)
    {
        var parameter = new NpgsqlParameter(name, NpgsqlDbType.Array | NpgsqlDbType.Text)
        {
            Value = values
        };
        command.Parameters.Add(parameter);
    }
}

