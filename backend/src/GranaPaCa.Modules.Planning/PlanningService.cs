using System.Globalization;
using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using GranaPaCa.Modules.Banking.Contracts;
using GranaPaCa.Modules.Categorization.Contracts;
using GranaPaCa.Modules.Planning.Contracts;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace GranaPaCa.Modules.Planning;

internal sealed class PlanningService(
    NpgsqlDataSource dataSource,
    IBankingAnalyticsReader bankingReader,
    IAlertPublisher alertPublisher,
    IConfiguration configuration) : IPlanningReader, IPlanningPurgeService
{
    private static readonly string[] SubscriptionUnusedKeywords =
    [
        "streaming", "cine", "netflix", "spotify", "prime", "disney", "hbo", "max",
        "youtube", "icloud", "academia", "clube", "assinatura", "globoplay", "deezer",
        "canva", "audible", "kindle", "gympass", "totalpass", "smart fit", "smartfit"
    ];

    private static readonly IReadOnlyDictionary<string, string[]> KeywordSynonyms =
        new Dictionary<string, string[]>(StringComparer.Ordinal)
        {
            ["delivery"] = ["delivery", "ifood", "rappi", "aiqfome", "uber eats", "ubereats", "ze delivery", "restaurante"],
            ["mercado"] = ["mercado", "supermercado", "hipermercado", "atacadao", "assai", "hortifruti"],
            ["farmacia"] = ["farmacia", "drogaria", "droga"],
            ["transporte"] = ["uber", "99", "corrida", "posto", "combustivel", "estacionamento"]
        };

    private readonly TimeZoneInfo _instanceTimeZone = PlanningFormatting.ResolveInstanceTimeZone(configuration);

    public async Task<PlanningSnapshot> GetSnapshotAsync(
        Guid householdId,
        DateOnly monthStart,
        CancellationToken cancellationToken = default)
    {
        var normalizedMonth = new DateOnly(monthStart.Year, monthStart.Month, 1);
        var monthLabel = normalizedMonth.ToString("yyyy-MM", CultureInfo.InvariantCulture);

        var metrics = await bankingReader.GetMonthMetricsAsync(householdId, normalizedMonth, cancellationToken);
        var rule503020 = ComputeRule503020(metrics);
        var projection = ComputeProjection(normalizedMonth, monthLabel, metrics);

        var threeMonthTxs = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            normalizedMonth.AddMonths(-2),
            normalizedMonth.AddMonths(1),
            cancellationToken);
        var subscriptions = DetectSubscriptions(threeMonthTxs, normalizedMonth);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var activeBudgetsCount = await connection.ExecuteScalarAsync<int>(new CommandDefinition(
            "SELECT COUNT(*)::int FROM planning.budget WHERE household_id = @HouseholdId AND is_active = true",
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken));

        var activeGoalsCount = await connection.ExecuteScalarAsync<int>(new CommandDefinition(
            "SELECT COUNT(*)::int FROM planning.goal WHERE household_id = @HouseholdId AND is_completed = false",
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken));

        return new PlanningSnapshot(
            monthLabel,
            projection.ProjectedMonthEndSpentCents,
            rule503020.NeedsCents,
            rule503020.WantsCents,
            rule503020.SavingsCents,
            activeBudgetsCount,
            activeGoalsCount,
            subscriptions.Count);
    }

    public async Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM planning.spending_alert_rule WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM planning.goal WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM planning.budget WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));
    }

    public async Task<(bool Ok, string? Error, PlanningOverviewResponse? Data)> GetOverviewAsync(
        Guid householdId,
        string? month,
        CancellationToken cancellationToken)
    {
        if (!PlanningFormatting.TryParseMonth(month, _instanceTimeZone, out var monthStart, out var monthLabel))
        {
            return (false, "Mês inválido; use o formato YYYY-MM.", null);
        }

        var prevMonthStart = monthStart.AddMonths(-1);
        var monthEndExclusive = monthStart.AddMonths(1);

        var metrics = await bankingReader.GetMonthMetricsAsync(householdId, monthStart, cancellationToken);
        var prevMetrics = await bankingReader.GetMonthMetricsAsync(householdId, prevMonthStart, cancellationToken);
        var threeMonthTxs = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            monthStart.AddMonths(-2),
            monthEndExclusive,
            cancellationToken);

        var currentMonthTxs = threeMonthTxs
            .Where(t => t.OccurredOn >= monthStart && t.OccurredOn < monthEndExclusive)
            .ToList();

        var rule503020 = ComputeRule503020(metrics);
        var projection = ComputeProjection(monthStart, monthLabel, metrics);
        var mom = ComputeMonthOverMonth(monthLabel, prevMonthStart, metrics, prevMetrics);
        var heatmap = ComputeCalendarHeatmap(monthStart, metrics);
        var subscriptions = DetectSubscriptions(threeMonthTxs, monthStart);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var budgetRows = await LoadBudgetsAsync(connection, householdId, cancellationToken);
        var goalRows = await LoadGoalsAsync(connection, householdId, cancellationToken);
        var ruleRows = await LoadAlertRulesAsync(connection, householdId, cancellationToken);

        var budgets = budgetRows.Select(row => MapBudget(row, metrics)).ToList();
        var today = PlanningFormatting.TodayInTimeZone(_instanceTimeZone);
        var goals = goalRows.Select(row => MapGoal(row, today)).ToList();
        var alertRules = ruleRows.Select(row => MapAlertRule(row, metrics, currentMonthTxs)).ToList();

        var subMonthlyTotal = subscriptions.Sum(s => s.EstimatedMonthlyCents);
        var subAnnualTotal = subscriptions.Sum(s => s.EstimatedAnnualCents);

        var response = new PlanningOverviewResponse(
            monthLabel,
            rule503020,
            projection,
            mom,
            heatmap,
            budgets,
            goals,
            subscriptions,
            subMonthlyTotal,
            subAnnualTotal,
            alertRules);

        return (true, null, response);
    }

    public async Task<(bool Ok, string? Error, BudgetsListResponse? Data)> GetBudgetsAsync(
        Guid householdId,
        string? month,
        CancellationToken cancellationToken)
    {
        if (!PlanningFormatting.TryParseMonth(month, _instanceTimeZone, out var monthStart, out var monthLabel))
        {
            return (false, "Mês inválido; use o formato YYYY-MM.", null);
        }

        var metrics = await bankingReader.GetMonthMetricsAsync(householdId, monthStart, cancellationToken);
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rows = await LoadBudgetsAsync(connection, householdId, cancellationToken);
        var items = rows.Select(row => MapBudget(row, metrics)).ToList();
        return (true, null, new BudgetsListResponse(monthLabel, items));
    }

    public async Task<(bool Ok, string? Error, BudgetDto? Data)> UpsertBudgetAsync(
        Guid householdId,
        UpsertBudgetRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null)
        {
            return (false, "Informe os dados do orçamento.", null);
        }

        if (!PlanningFormatting.TryNormalizeCategory(request.Category, out var category))
        {
            return (false, "Categoria inválida para o orçamento.", null);
        }

        if (request.MonthLimitCents <= 0)
        {
            return (false, "O limite mensal do orçamento deve ser maior que zero.", null);
        }

        var threshold = request.AlertThresholdPercent ?? 80;
        if (threshold is < 1 or > 100)
        {
            return (false, "O percentual de alerta deve estar entre 1 e 100.", null);
        }

        var isActive = request.IsActive ?? true;

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var saved = await connection.QuerySingleAsync<BudgetRow>(new CommandDefinition(
            """
            INSERT INTO planning.budget (
                id,
                household_id,
                category,
                month_limit_cents,
                alert_threshold_percent,
                is_active
            )
            VALUES (
                @Id,
                @HouseholdId,
                @Category,
                @MonthLimitCents,
                @AlertThresholdPercent,
                @IsActive
            )
            ON CONFLICT (household_id, category) DO UPDATE
            SET month_limit_cents = EXCLUDED.month_limit_cents,
                alert_threshold_percent = EXCLUDED.alert_threshold_percent,
                is_active = EXCLUDED.is_active,
                updated_at = now()
            RETURNING
                id AS Id,
                category AS Category,
                month_limit_cents AS MonthLimitCents,
                alert_threshold_percent AS AlertThresholdPercent,
                is_active AS IsActive,
                created_at AS CreatedAt,
                updated_at AS UpdatedAt
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                HouseholdId = householdId,
                Category = category,
                request.MonthLimitCents,
                AlertThresholdPercent = threshold,
                IsActive = isActive
            },
            cancellationToken: cancellationToken));

        var today = PlanningFormatting.TodayInTimeZone(_instanceTimeZone);
        var currentMonth = new DateOnly(today.Year, today.Month, 1);
        var metrics = await bankingReader.GetMonthMetricsAsync(householdId, currentMonth, cancellationToken);
        return (true, null, MapBudget(saved, metrics));
    }

    public async Task<bool> DeleteBudgetAsync(
        Guid householdId,
        Guid budgetId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var affected = await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM planning.budget WHERE id = @Id AND household_id = @HouseholdId",
            new { Id = budgetId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        return affected > 0;
    }

    public async Task<GoalsListResponse> GetGoalsAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rows = await LoadGoalsAsync(connection, householdId, cancellationToken);
        var today = PlanningFormatting.TodayInTimeZone(_instanceTimeZone);
        return new GoalsListResponse(rows.Select(row => MapGoal(row, today)).ToList());
    }

    public async Task<(bool Ok, string? Error, GoalDto? Data)> CreateGoalAsync(
        Guid householdId,
        CreateGoalRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.Name))
        {
            return (false, "Informe um nome para a meta.", null);
        }

        var name = request.Name.Trim();
        if (name.Length > 120)
        {
            return (false, "O nome da meta deve ter no máximo 120 caracteres.", null);
        }

        if (request.TargetCents <= 0)
        {
            return (false, "O valor alvo da meta deve ser maior que zero.", null);
        }

        var currentCents = request.CurrentCents ?? 0;
        if (currentCents < 0)
        {
            return (false, "O valor acumulado da meta não pode ser negativo.", null);
        }

        var isCompleted = currentCents >= request.TargetCents;

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var saved = await connection.QuerySingleAsync<GoalRow>(new CommandDefinition(
            """
            INSERT INTO planning.goal (
                id,
                household_id,
                name,
                target_cents,
                current_cents,
                target_date,
                is_completed
            )
            VALUES (
                @Id,
                @HouseholdId,
                @Name,
                @TargetCents,
                @CurrentCents,
                @TargetDate,
                @IsCompleted
            )
            RETURNING
                id AS Id,
                name AS Name,
                target_cents AS TargetCents,
                current_cents AS CurrentCents,
                target_date AS TargetDate,
                is_completed AS IsCompleted,
                created_at AS CreatedAt,
                updated_at AS UpdatedAt
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                HouseholdId = householdId,
                Name = name,
                request.TargetCents,
                CurrentCents = currentCents,
                request.TargetDate,
                IsCompleted = isCompleted
            },
            cancellationToken: cancellationToken));

        var today = PlanningFormatting.TodayInTimeZone(_instanceTimeZone);
        return (true, null, MapGoal(saved, today));
    }

    public async Task<(int StatusCode, string? Error, GoalDto? Data)> UpdateGoalAsync(
        Guid householdId,
        Guid goalId,
        UpdateGoalRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null)
        {
            return (400, "Informe ao menos um campo para atualizar a meta.", null);
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var existing = await connection.QuerySingleOrDefaultAsync<GoalRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                name AS Name,
                target_cents AS TargetCents,
                current_cents AS CurrentCents,
                target_date AS TargetDate,
                is_completed AS IsCompleted,
                created_at AS CreatedAt,
                updated_at AS UpdatedAt
            FROM planning.goal
            WHERE id = @Id AND household_id = @HouseholdId
            """,
            new { Id = goalId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (existing is null)
        {
            return (404, "Meta não encontrada.", null);
        }

        var name = existing.Name;
        if (request.Name is not null)
        {
            name = request.Name.Trim();
            if (name.Length == 0 || name.Length > 120)
            {
                return (400, "O nome da meta deve ter entre 1 e 120 caracteres.", null);
            }
        }

        var targetCents = request.TargetCents ?? existing.TargetCents;
        if (targetCents <= 0)
        {
            return (400, "O valor alvo da meta deve ser maior que zero.", null);
        }

        var currentCents = existing.CurrentCents;
        if (request.CurrentCents.HasValue)
        {
            currentCents = request.CurrentCents.Value;
        }
        else if (request.AddCents.HasValue)
        {
            try
            {
                currentCents = checked(existing.CurrentCents + request.AddCents.Value);
            }
            catch (OverflowException)
            {
                return (400, "O valor acumulado da meta excede o limite suportado.", null);
            }
        }

        if (currentCents < 0)
        {
            return (400, "O valor acumulado da meta não pode ser negativo.", null);
        }

        var targetDate = request.ClearTargetDate == true
            ? null
            : request.TargetDate ?? existing.TargetDate;

        var isCompleted = request.IsCompleted ?? (currentCents >= targetCents);

        var updated = await connection.QuerySingleAsync<GoalRow>(new CommandDefinition(
            """
            UPDATE planning.goal
            SET name = @Name,
                target_cents = @TargetCents,
                current_cents = @CurrentCents,
                target_date = @TargetDate,
                is_completed = @IsCompleted,
                updated_at = now()
            WHERE id = @Id AND household_id = @HouseholdId
            RETURNING
                id AS Id,
                name AS Name,
                target_cents AS TargetCents,
                current_cents AS CurrentCents,
                target_date AS TargetDate,
                is_completed AS IsCompleted,
                created_at AS CreatedAt,
                updated_at AS UpdatedAt
            """,
            new
            {
                Id = goalId,
                HouseholdId = householdId,
                Name = name,
                TargetCents = targetCents,
                CurrentCents = currentCents,
                TargetDate = targetDate,
                IsCompleted = isCompleted
            },
            cancellationToken: cancellationToken));

        var today = PlanningFormatting.TodayInTimeZone(_instanceTimeZone);
        return (200, null, MapGoal(updated, today));
    }

    public async Task<bool> DeleteGoalAsync(
        Guid householdId,
        Guid goalId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var affected = await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM planning.goal WHERE id = @Id AND household_id = @HouseholdId",
            new { Id = goalId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        return affected > 0;
    }

    public async Task<(bool Ok, string? Error, SpendingAlertRulesListResponse? Data)> GetAlertRulesAsync(
        Guid householdId,
        string? month,
        CancellationToken cancellationToken)
    {
        if (!PlanningFormatting.TryParseMonth(month, _instanceTimeZone, out var monthStart, out var monthLabel))
        {
            return (false, "Mês inválido; use o formato YYYY-MM.", null);
        }

        var metrics = await bankingReader.GetMonthMetricsAsync(householdId, monthStart, cancellationToken);
        var monthTxs = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            monthStart,
            monthStart.AddMonths(1),
            cancellationToken);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rows = await LoadAlertRulesAsync(connection, householdId, cancellationToken);
        var items = rows.Select(row => MapAlertRule(row, metrics, monthTxs)).ToList();
        return (true, null, new SpendingAlertRulesListResponse(monthLabel, items));
    }

    public async Task<(bool Ok, string? Error, SpendingAlertRuleDto? Data)> CreateAlertRuleAsync(
        Guid householdId,
        CreateSpendingAlertRuleRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null)
        {
            return (false, "Informe os dados da regra de alerta.", null);
        }

        string? category = null;
        if (!string.IsNullOrWhiteSpace(request.Category))
        {
            if (!PlanningFormatting.TryNormalizeCategory(request.Category, out var normalizedCat))
            {
                return (false, "Categoria inválida para a regra de alerta.", null);
            }

            category = normalizedCat;
        }

        var merchantKeyword = string.IsNullOrWhiteSpace(request.MerchantKeyword)
            ? null
            : MerchantNormalizer.NormalizeDescription(request.MerchantKeyword);
        if (string.IsNullOrWhiteSpace(merchantKeyword))
        {
            merchantKeyword = null;
        }

        var limitCents = request.LimitCents;
        var expression = request.Expression?.Trim();

        if (!string.IsNullOrWhiteSpace(expression) &&
            (limitCents is null || (category is null && merchantKeyword is null)))
        {
            if (SpendingAlertExpressionParser.TryParse(expression, out var parsed) && parsed is not null)
            {
                category ??= parsed.Category;
                merchantKeyword ??= parsed.MerchantKeyword;
                limitCents ??= parsed.LimitCents;
            }
            else if (limitCents is null && SpendingAlertExpressionParser.TryExtractAmountCents(expression, out var parsedCents))
            {
                limitCents = parsedCents;
            }
        }

        if (limitCents is null || limitCents <= 0)
        {
            return (false, "Informe um valor limite maior que zero (ex.: 'me avise quando delivery passar de R$ 300').", null);
        }

        if (category is null && merchantKeyword is null)
        {
            return (false, "Não foi possível identificar a categoria ou termo da regra de alerta.", null);
        }

        if (string.IsNullOrWhiteSpace(expression))
        {
            var subject = merchantKeyword ?? PlanningFormatting.GetCategoryLabel(category!);
            expression = $"Me avise quando {subject} passar de {PlanningFormatting.FormatBrl(limitCents.Value)}";
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var saved = await connection.QuerySingleAsync<SpendingAlertRuleRow>(new CommandDefinition(
            """
            INSERT INTO planning.spending_alert_rule (
                id,
                household_id,
                expression,
                category,
                merchant_keyword,
                limit_cents,
                is_active
            )
            VALUES (
                @Id,
                @HouseholdId,
                @Expression,
                @Category,
                @MerchantKeyword,
                @LimitCents,
                true
            )
            RETURNING
                id AS Id,
                expression AS Expression,
                category AS Category,
                merchant_keyword AS MerchantKeyword,
                limit_cents AS LimitCents,
                is_active AS IsActive,
                created_at AS CreatedAt
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                HouseholdId = householdId,
                Expression = expression,
                Category = category,
                MerchantKeyword = merchantKeyword,
                LimitCents = limitCents.Value
            },
            cancellationToken: cancellationToken));

        var today = PlanningFormatting.TodayInTimeZone(_instanceTimeZone);
        var currentMonth = new DateOnly(today.Year, today.Month, 1);
        var metrics = await bankingReader.GetMonthMetricsAsync(householdId, currentMonth, cancellationToken);
        var monthTxs = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            currentMonth,
            currentMonth.AddMonths(1),
            cancellationToken);

        return (true, null, MapAlertRule(saved, metrics, monthTxs));
    }

    public async Task<bool> DeleteAlertRuleAsync(
        Guid householdId,
        Guid ruleId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var affected = await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM planning.spending_alert_rule WHERE id = @Id AND household_id = @HouseholdId",
            new { Id = ruleId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        return affected > 0;
    }

    public async Task<(bool Ok, string? Error, EvaluateAlertsResponse? Data)> EvaluateAlertsAsync(
        Guid householdId,
        string? month,
        CancellationToken cancellationToken)
    {
        if (!PlanningFormatting.TryParseMonth(month, _instanceTimeZone, out var monthStart, out var monthLabel))
        {
            return (false, "Mês inválido; use o formato YYYY-MM.", null);
        }

        var metrics = await bankingReader.GetMonthMetricsAsync(householdId, monthStart, cancellationToken);
        var monthTxs = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            monthStart,
            monthStart.AddMonths(1),
            cancellationToken);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var budgets = (await LoadBudgetsAsync(connection, householdId, cancellationToken))
            .Where(b => b.IsActive)
            .ToList();
        var rules = (await LoadAlertRulesAsync(connection, householdId, cancellationToken))
            .Where(r => r.IsActive)
            .ToList();

        var raised = 0;
        var resolved = 0;
        var triggered = new List<TriggeredPlanningAlertDto>();

        foreach (var budget in budgets)
        {
            var spentCents = metrics.SpentByCategoryCents.GetValueOrDefault(budget.Category, 0L);
            var usedPercent = budget.MonthLimitCents > 0
                ? Math.Round(spentCents * 100m / budget.MonthLimitCents, 2, MidpointRounding.AwayFromZero)
                : 0m;

            var dedupKey = $"planning:budget:{budget.Category}:{monthLabel}";
            var categoryLabel = PlanningFormatting.GetCategoryLabel(budget.Category);

            if (spentCents > budget.MonthLimitCents)
            {
                var title = $"Orçamento de {categoryLabel} ultrapassado";
                var message =
                    $"Em {monthLabel}, {categoryLabel} chegou a {PlanningFormatting.FormatBrl(spentCents)}, acima do limite de {PlanningFormatting.FormatBrl(budget.MonthLimitCents)}.";

                await alertPublisher.RaiseAsync(
                    new AlertRequest(
                        householdId,
                        dedupKey,
                        "budget_exceeded",
                        "warning",
                        title,
                        message,
                        $"/planning?month={monthLabel}"),
                    cancellationToken);

                raised++;
                triggered.Add(new TriggeredPlanningAlertDto(
                    dedupKey,
                    "budget_exceeded",
                    "warning",
                    title,
                    message,
                    spentCents,
                    budget.MonthLimitCents));
            }
            else if (usedPercent >= budget.AlertThresholdPercent)
            {
                var title = $"Orçamento de {categoryLabel} em {Math.Round(usedPercent, 0, MidpointRounding.AwayFromZero)}%";
                var message =
                    $"Em {monthLabel}, {categoryLabel} já consumiu {PlanningFormatting.FormatBrl(spentCents)} de {PlanningFormatting.FormatBrl(budget.MonthLimitCents)}.";

                await alertPublisher.RaiseAsync(
                    new AlertRequest(
                        householdId,
                        dedupKey,
                        "budget_threshold",
                        "warning",
                        title,
                        message,
                        $"/planning?month={monthLabel}"),
                    cancellationToken);

                raised++;
                triggered.Add(new TriggeredPlanningAlertDto(
                    dedupKey,
                    "budget_threshold",
                    "warning",
                    title,
                    message,
                    spentCents,
                    budget.MonthLimitCents));
            }
            else
            {
                await alertPublisher.ResolveAsync(householdId, dedupKey, cancellationToken);
                resolved++;
            }
        }

        foreach (var rule in rules)
        {
            var spentCents = ComputeAlertRuleSpentCents(rule, metrics, monthTxs);
            var dedupKey = $"planning:rule:{rule.Id:N}:{monthLabel}";

            if (spentCents >= rule.LimitCents)
            {
                var subject = rule.MerchantKeyword ?? PlanningFormatting.GetCategoryLabel(rule.Category ?? "other");
                var title = $"Alerta de gasto: {subject}";
                var message =
                    $"Em {monthLabel}, os gastos com {subject} atingiram {PlanningFormatting.FormatBrl(spentCents)}, superando o limite configurado de {PlanningFormatting.FormatBrl(rule.LimitCents)} ({rule.Expression}).";

                await alertPublisher.RaiseAsync(
                    new AlertRequest(
                        householdId,
                        dedupKey,
                        "spending_rule",
                        "warning",
                        title,
                        message,
                        $"/planning?month={monthLabel}"),
                    cancellationToken);

                raised++;
                triggered.Add(new TriggeredPlanningAlertDto(
                    dedupKey,
                    "spending_rule",
                    "warning",
                    title,
                    message,
                    spentCents,
                    rule.LimitCents));
            }
            else
            {
                await alertPublisher.ResolveAsync(householdId, dedupKey, cancellationToken);
                resolved++;
            }
        }

        return (true, null, new EvaluateAlertsResponse(
            monthLabel,
            budgets.Count,
            rules.Count,
            raised,
            resolved,
            triggered));
    }

    private static Rule503020Dto ComputeRule503020(BankingMonthMetrics metrics)
    {
        var needsCents = Math.Max(0L, metrics.EssentialSpentCents);
        var wantsCents = Math.Max(0L, metrics.ImportantSpentCents + metrics.FlexibleSpentCents);
        var savingsCents = Math.Max(0L, metrics.LeftoverCents);
        var unclassifiedSpentCents = Math.Max(0L, metrics.SpentCents - (needsCents + wantsCents));

        var baseCents = metrics.ReceivedCents > 0
            ? metrics.ReceivedCents
            : needsCents + wantsCents + savingsCents;

        decimal needsPct = 0m;
        decimal wantsPct = 0m;
        decimal savingsPct = 0m;

        if (baseCents > 0)
        {
            needsPct = Math.Round(needsCents * 100m / baseCents, 2, MidpointRounding.AwayFromZero);
            wantsPct = Math.Round(wantsCents * 100m / baseCents, 2, MidpointRounding.AwayFromZero);
            savingsPct = Math.Round(savingsCents * 100m / baseCents, 2, MidpointRounding.AwayFromZero);
        }

        return new Rule503020Dto(
            needsCents,
            wantsCents,
            savingsCents,
            baseCents,
            unclassifiedSpentCents,
            needsPct,
            wantsPct,
            savingsPct,
            50m,
            30m,
            20m);
    }

    private MonthProjectionDto ComputeProjection(
        DateOnly monthStart,
        string monthLabel,
        BankingMonthMetrics metrics)
    {
        var today = PlanningFormatting.TodayInTimeZone(_instanceTimeZone);
        var daysInMonth = DateTime.DaysInMonth(monthStart.Year, monthStart.Month);

        var regularSpentCents = Math.Max(0L, metrics.SpentCents - metrics.AtypicalSpentCents);
        var atypicalSpentCents = Math.Max(0L, metrics.AtypicalSpentCents);

        int elapsedDays;
        bool isClosedMonth;
        if (monthStart.Year < today.Year || (monthStart.Year == today.Year && monthStart.Month < today.Month))
        {
            elapsedDays = daysInMonth;
            isClosedMonth = true;
        }
        else if (monthStart.Year == today.Year && monthStart.Month == today.Month)
        {
            elapsedDays = Math.Clamp(today.Day, 1, daysInMonth);
            isClosedMonth = false;
        }
        else
        {
            elapsedDays = 0;
            isClosedMonth = false;
        }

        var remainingDays = Math.Max(0, daysInMonth - elapsedDays);

        long dailyAverageCents;
        long projectedMonthEndSpentCents;
        if (elapsedDays > 0)
        {
            var dailyAverageDecimal = (decimal)regularSpentCents / elapsedDays;
            dailyAverageCents = decimal.ToInt64(Math.Round(dailyAverageDecimal, 0, MidpointRounding.AwayFromZero));
            projectedMonthEndSpentCents = isClosedMonth
                ? regularSpentCents
                : decimal.ToInt64(Math.Round(dailyAverageDecimal * daysInMonth, 0, MidpointRounding.AwayFromZero));
        }
        else
        {
            dailyAverageCents = 0;
            projectedMonthEndSpentCents = regularSpentCents;
        }

        var projectedLeftoverCents = metrics.ReceivedCents - projectedMonthEndSpentCents;

        return new MonthProjectionDto(
            monthLabel,
            metrics.SpentCents,
            regularSpentCents,
            atypicalSpentCents,
            dailyAverageCents,
            projectedMonthEndSpentCents,
            projectedLeftoverCents,
            elapsedDays,
            daysInMonth,
            remainingDays,
            isClosedMonth);
    }

    private static MonthOverMonthDto ComputeMonthOverMonth(
        string currentMonthLabel,
        DateOnly prevMonthStart,
        BankingMonthMetrics current,
        BankingMonthMetrics previous)
    {
        var prevLabel = prevMonthStart.ToString("yyyy-MM", CultureInfo.InvariantCulture);
        var spentDeltaCents = current.SpentCents - previous.SpentCents;
        var spentDeltaPercent = ComputeDeltaPercent(current.SpentCents, previous.SpentCents);

        var allCategories = current.SpentByCategoryCents.Keys
            .Union(previous.SpentByCategoryCents.Keys, StringComparer.Ordinal)
            .ToList();

        var categoryDeltas = allCategories
            .Select(category =>
            {
                var curr = current.SpentByCategoryCents.GetValueOrDefault(category, 0L);
                var prev = previous.SpentByCategoryCents.GetValueOrDefault(category, 0L);
                var delta = curr - prev;
                var deltaPct = ComputeDeltaPercent(curr, prev);
                return new CategoryDeltaDto(
                    category,
                    PlanningFormatting.GetCategoryLabel(category),
                    curr,
                    prev,
                    delta,
                    deltaPct);
            })
            .OrderByDescending(d => Math.Abs(d.DeltaCents))
            .ThenByDescending(d => d.CurrentSpentCents)
            .ToList();

        return new MonthOverMonthDto(
            currentMonthLabel,
            prevLabel,
            current.SpentCents,
            previous.SpentCents,
            spentDeltaCents,
            spentDeltaPercent,
            current.ReceivedCents,
            previous.ReceivedCents,
            current.ReceivedCents - previous.ReceivedCents,
            current.LeftoverCents,
            previous.LeftoverCents,
            current.LeftoverCents - previous.LeftoverCents,
            categoryDeltas);
    }

    private static decimal ComputeDeltaPercent(long current, long previous)
    {
        if (previous > 0)
        {
            return Math.Round((current - previous) * 100m / previous, 2, MidpointRounding.AwayFromZero);
        }

        return current > 0 ? 100m : 0m;
    }

    private static List<CalendarHeatmapDayDto> ComputeCalendarHeatmap(
        DateOnly monthStart,
        BankingMonthMetrics metrics)
    {
        var daysInMonth = DateTime.DaysInMonth(monthStart.Year, monthStart.Month);
        var rawDays = new List<(DateOnly Date, long SpentCents)>(daysInMonth);
        long maxSpent = 0;

        for (var day = 1; day <= daysInMonth; day++)
        {
            var date = new DateOnly(monthStart.Year, monthStart.Month, day);
            var spent = metrics.DailySpendingCents.TryGetValue(date, out var value)
                ? Math.Max(0L, value)
                : 0L;
            if (spent > maxSpent)
            {
                maxSpent = spent;
            }

            rawDays.Add((date, spent));
        }

        var result = new List<CalendarHeatmapDayDto>(daysInMonth);
        foreach (var (date, spent) in rawDays)
        {
            var intensity = 0;
            if (spent > 0 && maxSpent > 0)
            {
                var ratio = (decimal)spent / maxSpent;
                intensity = ratio <= 0.20m ? 1
                    : ratio <= 0.40m ? 2
                    : ratio <= 0.60m ? 3
                    : ratio <= 0.80m ? 4
                    : 5;
            }

            result.Add(new CalendarHeatmapDayDto(date, spent, intensity));
        }

        return result;
    }

    private static List<DetectedSubscriptionDto> DetectSubscriptions(
        IReadOnlyList<BankingTransactionFact> transactions,
        DateOnly referenceMonthStart)
    {
        var grouped = transactions
            .Where(t => string.Equals(t.Kind, "expense", StringComparison.OrdinalIgnoreCase) && t.AmountCents < 0)
            .Select(t => (Tx: t, Normalized: MerchantNormalizer.NormalizeDescription(t.Description)))
            .Where(x => !string.IsNullOrWhiteSpace(x.Normalized))
            .GroupBy(x => x.Normalized, StringComparer.Ordinal);

        var detected = new List<DetectedSubscriptionDto>();

        foreach (var group in grouped)
        {
            var items = group.Select(x => x.Tx).OrderBy(x => x.OccurredOn).ToList();
            var byMonth = items
                .GroupBy(t => (t.OccurredOn.Year, t.OccurredOn.Month))
                .ToList();

            if (byMonth.Count < 2)
            {
                continue;
            }

            // Exclude frequent multi-purchase merchants (e.g., grocery/bakery bought multiple times every month).
            var maxChargesInSingleMonth = byMonth.Max(m => m.Count());
            var avgChargesPerMonth = (decimal)items.Count / byMonth.Count;
            if (maxChargesInSingleMonth > 2 || avgChargesPerMonth > 1.5m)
            {
                continue;
            }

            var absAmounts = items
                .Select(t => Math.Abs(t.AmountCents))
                .OrderBy(a => a)
                .ToList();

            var median = absAmounts[absAmounts.Count / 2];
            if (median <= 0)
            {
                continue;
            }

            var tolerance = median * 0.15m;
            if (!absAmounts.All(amount => Math.Abs(amount - median) <= tolerance))
            {
                continue;
            }

            var estimatedMonthlyCents = decimal.ToInt64(Math.Round(
                absAmounts.Average(a => (decimal)a),
                0,
                MidpointRounding.AwayFromZero));
            var estimatedAnnualCents = estimatedMonthlyCents * 12;

            var latest = items[^1];
            var category = items
                .Where(t => !string.IsNullOrWhiteSpace(t.Category))
                .GroupBy(t => t.Category!, StringComparer.Ordinal)
                .OrderByDescending(g => g.Count())
                .Select(g => g.Key)
                .FirstOrDefault() ?? "services";

            var averageDay = decimal.ToInt32(Math.Round(
                items.Average(t => (decimal)t.OccurredOn.Day),
                0,
                MidpointRounding.AwayFromZero));

            var chargedInReferenceMonth = byMonth.Any(m =>
                m.Key.Year == referenceMonthStart.Year && m.Key.Month == referenceMonthStart.Month);

            var matchesSubscriptionKeyword = SubscriptionUnusedKeywords.Any(kw =>
                group.Key.Contains(kw, StringComparison.Ordinal));

            var possiblyUnused = false;
            string? unusedReason = null;

            if (!chargedInReferenceMonth && byMonth.Count >= 2)
            {
                possiblyUnused = true;
                unusedReason = "Cobrada nos meses anteriores sem registro neste mês; vale conferir se continua ativa.";
            }
            else if (matchesSubscriptionKeyword ||
                     (category is "services" or "leisure" or "other" && byMonth.Count >= 3))
            {
                possiblyUnused = true;
                unusedReason = "Cobrança recorrente automática; revise se ainda utiliza este serviço.";
            }

            detected.Add(new DetectedSubscriptionDto(
                group.Key,
                latest.Description,
                category,
                PlanningFormatting.GetCategoryLabel(category),
                estimatedMonthlyCents,
                estimatedAnnualCents,
                items.Count,
                byMonth.Count,
                latest.OccurredOn,
                averageDay,
                possiblyUnused,
                unusedReason));
        }

        return detected
            .OrderByDescending(s => s.EstimatedMonthlyCents)
            .ThenBy(s => s.MerchantNormalized, StringComparer.Ordinal)
            .ToList();
    }

    private static BudgetDto MapBudget(BudgetRow row, BankingMonthMetrics metrics)
    {
        var spentCents = metrics.SpentByCategoryCents.GetValueOrDefault(row.Category, 0L);
        var remainingCents = row.MonthLimitCents - spentCents;
        var usedPercent = row.MonthLimitCents > 0
            ? Math.Round(spentCents * 100m / row.MonthLimitCents, 2, MidpointRounding.AwayFromZero)
            : 0m;

        var status = spentCents > row.MonthLimitCents
            ? "exceeded"
            : usedPercent >= row.AlertThresholdPercent
                ? "warning"
                : "ok";

        return new BudgetDto(
            row.Id,
            row.Category,
            PlanningFormatting.GetCategoryLabel(row.Category),
            row.MonthLimitCents,
            row.AlertThresholdPercent,
            row.IsActive,
            spentCents,
            remainingCents,
            usedPercent,
            status,
            row.CreatedAt,
            row.UpdatedAt);
    }

    private static GoalDto MapGoal(GoalRow row, DateOnly today)
    {
        var remainingCents = Math.Max(0L, row.TargetCents - row.CurrentCents);
        var progressPercent = row.TargetCents > 0
            ? Math.Round(row.CurrentCents * 100m / row.TargetCents, 2, MidpointRounding.AwayFromZero)
            : 0m;

        long? suggestedMonthlyCents = null;
        if (!row.IsCompleted && remainingCents > 0 && row.TargetDate.HasValue)
        {
            var monthsRemaining = ((row.TargetDate.Value.Year - today.Year) * 12) +
                (row.TargetDate.Value.Month - today.Month);
            if (monthsRemaining <= 0)
            {
                suggestedMonthlyCents = remainingCents;
            }
            else
            {
                suggestedMonthlyCents = decimal.ToInt64(Math.Ceiling((decimal)remainingCents / monthsRemaining));
            }
        }

        return new GoalDto(
            row.Id,
            row.Name,
            row.TargetCents,
            row.CurrentCents,
            remainingCents,
            progressPercent,
            row.TargetDate,
            suggestedMonthlyCents,
            row.IsCompleted,
            row.CreatedAt,
            row.UpdatedAt);
    }

    private static SpendingAlertRuleDto MapAlertRule(
        SpendingAlertRuleRow row,
        BankingMonthMetrics metrics,
        IReadOnlyList<BankingTransactionFact> monthTransactions)
    {
        var spentCents = ComputeAlertRuleSpentCents(row, metrics, monthTransactions);
        return new SpendingAlertRuleDto(
            row.Id,
            row.Expression,
            row.Category,
            row.Category is null ? null : PlanningFormatting.GetCategoryLabel(row.Category),
            row.MerchantKeyword,
            row.LimitCents,
            row.IsActive,
            spentCents,
            row.IsActive && spentCents >= row.LimitCents,
            row.CreatedAt);
    }

    private static long ComputeAlertRuleSpentCents(
        SpendingAlertRuleRow rule,
        BankingMonthMetrics metrics,
        IReadOnlyList<BankingTransactionFact> monthTransactions)
    {
        if (!string.IsNullOrWhiteSpace(rule.Category) && string.IsNullOrWhiteSpace(rule.MerchantKeyword))
        {
            return Math.Max(0L, metrics.SpentByCategoryCents.GetValueOrDefault(rule.Category, 0L));
        }

        var normalizedKeyword = string.IsNullOrWhiteSpace(rule.MerchantKeyword)
            ? null
            : MerchantNormalizer.NormalizeDescription(rule.MerchantKeyword);

        var terms = normalizedKeyword is not null && KeywordSynonyms.TryGetValue(normalizedKeyword, out var synonyms)
            ? synonyms
            : normalizedKeyword is not null
                ? [normalizedKeyword]
                : [];

        long totalCents = 0;
        foreach (var tx in monthTransactions)
        {
            if (tx.Kind is not ("expense" or "refund"))
            {
                continue;
            }

            if (!string.IsNullOrWhiteSpace(rule.Category) &&
                !string.Equals(tx.Category, rule.Category, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (terms.Length > 0)
            {
                var normalizedDesc = MerchantNormalizer.NormalizeDescription(tx.Description);
                var matched = terms.Any(term => normalizedDesc.Contains(term, StringComparison.Ordinal));
                if (!matched && tx.Tags.Count > 0)
                {
                    matched = tx.Tags.Any(tag =>
                    {
                        var normTag = MerchantNormalizer.NormalizeDescription(tag);
                        return terms.Any(term => normTag.Contains(term, StringComparison.Ordinal));
                    });
                }

                if (!matched)
                {
                    continue;
                }
            }

            totalCents += -tx.AmountCents;
        }

        return Math.Max(0L, totalCents);
    }

    private static async Task<List<BudgetRow>> LoadBudgetsAsync(
        NpgsqlConnection connection,
        Guid householdId,
        CancellationToken cancellationToken)
    {
        return (await connection.QueryAsync<BudgetRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                category AS Category,
                month_limit_cents AS MonthLimitCents,
                alert_threshold_percent AS AlertThresholdPercent,
                is_active AS IsActive,
                created_at AS CreatedAt,
                updated_at AS UpdatedAt
            FROM planning.budget
            WHERE household_id = @HouseholdId
            ORDER BY category ASC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();
    }

    private static async Task<List<GoalRow>> LoadGoalsAsync(
        NpgsqlConnection connection,
        Guid householdId,
        CancellationToken cancellationToken)
    {
        return (await connection.QueryAsync<GoalRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                name AS Name,
                target_cents AS TargetCents,
                current_cents AS CurrentCents,
                target_date AS TargetDate,
                is_completed AS IsCompleted,
                created_at AS CreatedAt,
                updated_at AS UpdatedAt
            FROM planning.goal
            WHERE household_id = @HouseholdId
            ORDER BY is_completed ASC, target_date ASC NULLS LAST, created_at DESC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();
    }

    private static async Task<List<SpendingAlertRuleRow>> LoadAlertRulesAsync(
        NpgsqlConnection connection,
        Guid householdId,
        CancellationToken cancellationToken)
    {
        return (await connection.QueryAsync<SpendingAlertRuleRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                expression AS Expression,
                category AS Category,
                merchant_keyword AS MerchantKeyword,
                limit_cents AS LimitCents,
                is_active AS IsActive,
                created_at AS CreatedAt
            FROM planning.spending_alert_rule
            WHERE household_id = @HouseholdId
            ORDER BY created_at DESC, id DESC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();
    }

    private sealed record BudgetRow(
        Guid Id,
        string Category,
        long MonthLimitCents,
        int AlertThresholdPercent,
        bool IsActive,
        DateTimeOffset CreatedAt,
        DateTimeOffset UpdatedAt);

    private sealed record GoalRow(
        Guid Id,
        string Name,
        long TargetCents,
        long CurrentCents,
        DateOnly? TargetDate,
        bool IsCompleted,
        DateTimeOffset CreatedAt,
        DateTimeOffset UpdatedAt);

    private sealed record SpendingAlertRuleRow(
        Guid Id,
        string Expression,
        string? Category,
        string? MerchantKeyword,
        long LimitCents,
        bool IsActive,
        DateTimeOffset CreatedAt);
}
