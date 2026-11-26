using System.Text.Json;

namespace GranaPaCa.Modules.Banking.Providers;

/// <summary>
/// Deterministic fictitious provider matching app/lib/demo/demo_data.dart (no real data, no clock/random variance).
/// </summary>
internal sealed class SyntheticBankProvider : IBankProvider
{
    public const string AuroraItemId = "synthetic-aurora";
    public const string SiriemaItemId = "synthetic-siriema";

    public static readonly IReadOnlyList<(string ExternalItemId, string InstitutionName, string BrandColor)> DefaultConnections =
    [
        (AuroraItemId, "Banco Aurora", "#A0521A"),
        (SiriemaItemId, "Banco Siriema", "#2A7550")
    ];

    private static readonly (int Day, string Description, long Cents, string Cnpj)[] CardPurchases =
    [
        (3, "Supermercado Bom Preço", 48230, "11222333000181"),
        (9, "Posto Estrada Real", 21000, "22333444000172"),
        (11, "Restaurante Sabor da Serra", 8950, "33444555000163"),
        (14, "Farmácia Vida Plena", 6420, "44555666000154"),
        (17, "Supermercado Bom Preço", 39110, "11222333000181"),
        (19, "Streaming Cine+", 3990, "55666777000145"),
        (22, "Livraria Página Virada", 7480, "66777888000136"),
        (25, "Loja Tudo pra Casa", 12900, "77888999000127")
    ];

    private static readonly (int Day, string Description, long Cents, string? Cnpj)[] DebitSpending =
    [
        (6, "Academia Movimento", 9900, "12345678000190"),
        (8, "Aluguel", 165000, null),
        (12, "Conta de luz", 15800, null),
        (15, "Internet Fibra Lar", 11990, "23456789000181"),
        (20, "Padaria Pão de Ontem", 2350, "34567890000172"),
        (23, "Corrida de app", 2780, null),
        (27, "Padaria Pão de Ontem", 1980, "34567890000172")
    ];

    public string ProviderName => "synthetic";

    public bool IsConfigured => true;

    public Task<ProviderConnectionData> FetchConnectionAsync(
        string externalItemId,
        CancellationToken cancellationToken = default)
    {
        var data = externalItemId switch
        {
            AuroraItemId => BuildAurora(),
            SiriemaItemId => BuildSiriema(),
            _ => throw new InvalidOperationException($"Unknown synthetic connection '{externalItemId}'.")
        };

        return Task.FromResult(data);
    }

    private static long Vary(long cents, int month, int salt) =>
        cents + (month * 7919L + salt * 104729L) % 2000L;

    private static ProviderConnectionData BuildAurora()
    {
        var ccTxs = new List<ProviderTransactionData>();
        var poupTxs = new List<ProviderTransactionData>();
        var cardTxs = new List<ProviderTransactionData>();
        var bills = new List<ProviderCardBillData>();

        long openBill = 0;

        for (var month = 1; month <= 3; month++)
        {
            ccTxs.Add(CreateTx(
                $"aurora-cc-2026-{month:D2}-salary",
                new DateOnly(2026, month, 5),
                null,
                "Salário",
                null,
                620000));

            ccTxs.Add(CreateTx(
                $"aurora-cc-2026-{month:D2}-to-poup",
                new DateOnly(2026, month, 6),
                null,
                "Transferência para a poupança",
                null,
                -50000));

            poupTxs.Add(CreateTx(
                $"aurora-poup-2026-{month:D2}-from-cc",
                new DateOnly(2026, month, 6),
                null,
                "Transferência da conta corrente",
                null,
                50000));

            ccTxs.Add(CreateTx(
                $"aurora-cc-2026-{month:D2}-to-siriema",
                new DateOnly(2026, month, 6),
                null,
                "Pix para Banco Siriema",
                null,
                -260000));

            if (openBill > 0)
            {
                ccTxs.Add(CreateTx(
                    $"aurora-cc-2026-{month:D2}-bill-pay",
                    new DateOnly(2026, month, 10),
                    null,
                    "Pagamento da fatura do cartão",
                    null,
                    -openBill));

                cardTxs.Add(CreateTx(
                    $"aurora-card-2026-{month:D2}-bill-paid",
                    new DateOnly(2026, month, 10),
                    null,
                    "Pagamento recebido",
                    null,
                    openBill));
            }

            ccTxs.Add(CreateTx(
                $"aurora-cc-2026-{month:D2}-withdrawal",
                new DateOnly(2026, month, 18),
                null,
                "Saque",
                null,
                -20000));

            var billExternalId = $"aurora-card-bill-2026-{month:D2}";
            openBill = 0;

            // Bought in November 2025 in 10 installments; January 2026 is installment 3/10.
            cardTxs.Add(CreateTx(
                $"aurora-card-2026-{month:D2}-item-0",
                new DateOnly(2026, month, 4),
                new DateOnly(2025, 11, 4),
                "Notebook Loja Byte",
                "99000111000109",
                -42000,
                billExternalId,
                month + 2,
                10));
            openBill += 42000;

            for (var i = 0; i < CardPurchases.Length; i++)
            {
                var (day, description, cents, cnpj) = CardPurchases[i];
                var amount = Vary(cents, month, i + 1);
                cardTxs.Add(CreateTx(
                    $"aurora-card-2026-{month:D2}-item-{i + 1}",
                    new DateOnly(2026, month, day),
                    null,
                    description,
                    cnpj,
                    -amount,
                    billExternalId));
                openBill += amount;
            }

            var periodMonth = new DateOnly(2026, month, 1);
            var closingOn = new DateOnly(2026, month, 28);
            var dueOn = new DateOnly(2026, month + 1, 10);
            var isOpen = month == 3;
            var billRaw = JsonSerializer.Serialize(new
            {
                provider = "synthetic",
                billId = billExternalId,
                periodMonth = periodMonth.ToString("yyyy-MM-dd"),
                closingOn = closingOn.ToString("yyyy-MM-dd"),
                dueOn = dueOn.ToString("yyyy-MM-dd"),
                totalCents = openBill,
                isOpen
            });

            bills.Add(new ProviderCardBillData(
                billExternalId,
                periodMonth,
                closingOn,
                dueOn,
                openBill,
                isOpen,
                billRaw));
        }

        poupTxs.Add(CreateTx(
            "aurora-poup-2026-02-cdb",
            new DateOnly(2026, 2, 13),
            null,
            "Aplicação CDB",
            null,
            -100000));

        const long ccOpening = 312000;
        const long poupOpening = 1450000;

        var accounts = new List<ProviderAccountData>
        {
            new(
                "aurora-cc",
                "Conta corrente",
                "checking",
                "1042",
                "BRL",
                ccOpening,
                ccOpening + ccTxs.Sum(t => t.AmountCents),
                [],
                ccTxs),
            new(
                "aurora-poup",
                "Poupança",
                "savings",
                "8819",
                "BRL",
                poupOpening,
                poupOpening + poupTxs.Sum(t => t.AmountCents),
                [],
                poupTxs),
            new(
                "aurora-card",
                "Cartão Aurora",
                "credit_card",
                "4821",
                "BRL",
                0,
                cardTxs.Sum(t => t.AmountCents),
                bills,
                cardTxs)
        };

        return new ProviderConnectionData(
            AuroraItemId,
            "Banco Aurora",
            "#A0521A",
            "up_to_date",
            DateTimeOffset.UtcNow.AddDays(120),
            null,
            accounts);
    }

    private static ProviderConnectionData BuildSiriema()
    {
        var txs = new List<ProviderTransactionData>();

        for (var month = 1; month <= 3; month++)
        {
            txs.Add(CreateTx(
                $"siriema-cc-2026-{month:D2}-from-aurora",
                new DateOnly(2026, month, 6),
                null,
                "Pix de Banco Aurora",
                null,
                260000));

            for (var i = 0; i < DebitSpending.Length; i++)
            {
                var (day, description, cents, cnpj) = DebitSpending[i];
                var amount = Vary(cents, month, i + 10);
                txs.Add(CreateTx(
                    $"siriema-cc-2026-{month:D2}-debit-{i}",
                    new DateOnly(2026, month, day),
                    null,
                    description,
                    cnpj,
                    -amount));
            }
        }

        txs.Add(CreateTx(
            "siriema-cc-2026-03-freelance",
            new DateOnly(2026, 3, 21),
            null,
            "Pix recebido: projeto freelance",
            null,
            85000));

        // Deterministic uncategorized merchant items so the review queue (RF-31) and
        // similar-transaction rule suggestion (RF-26) have realistic entries out of the box.
        txs.Add(CreateTx(
            "siriema-cc-2026-03-uncat-1",
            new DateOnly(2026, 3, 24),
            null,
            "Armarinho Estrela",
            "88999000000118",
            -3500));

        txs.Add(CreateTx(
            "siriema-cc-2026-03-uncat-2",
            new DateOnly(2026, 3, 26),
            null,
            "Armarinho Estrela",
            "88999000000118",
            -2800));

        const long opening = 95000;
        var accounts = new List<ProviderAccountData>
        {
            new(
                "siriema-cc",
                "Conta corrente",
                "checking",
                "7390",
                "BRL",
                opening,
                opening + txs.Sum(t => t.AmountCents),
                [],
                txs)
        };

        return new ProviderConnectionData(
            SiriemaItemId,
            "Banco Siriema",
            "#2A7550",
            "up_to_date",
            DateTimeOffset.UtcNow.AddDays(120),
            null,
            accounts);
    }

    private static ProviderTransactionData CreateTx(
        string externalId,
        DateOnly occurredOn,
        DateOnly? purchaseOn,
        string description,
        string? merchantCnpj,
        long amountCents,
        string? externalBillId = null,
        int? installmentNumber = null,
        int? installmentTotal = null)
    {
        var rawPayload = JsonSerializer.Serialize(new
        {
            provider = "synthetic",
            externalId,
            occurredOn = occurredOn.ToString("yyyy-MM-dd"),
            purchaseOn = purchaseOn?.ToString("yyyy-MM-dd"),
            description,
            merchantCnpj,
            amountCents,
            currency = "BRL",
            status = "posted",
            billId = externalBillId,
            installmentNumber,
            installmentTotal
        });

        return new ProviderTransactionData(
            "synthetic",
            externalId,
            occurredOn,
            purchaseOn,
            description,
            merchantCnpj,
            amountCents,
            "BRL",
            "posted",
            externalBillId,
            installmentNumber,
            installmentTotal,
            rawPayload);
    }
}
