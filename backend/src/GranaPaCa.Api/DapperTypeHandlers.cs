using System.Data;
using Dapper;

namespace GranaPaCa.Api;

internal static class DapperTypeHandlers
{
    public static void Register()
    {
        SqlMapper.AddTypeHandler(new UtcDateTimeOffsetTypeHandler());
        SqlMapper.AddTypeHandler(new DateOnlyHandler());
    }

    private sealed class UtcDateTimeOffsetTypeHandler : SqlMapper.TypeHandler<DateTimeOffset>
    {
        public override void SetValue(IDbDataParameter parameter, DateTimeOffset value)
        {
            parameter.Value = value.ToUniversalTime();
        }

        public override DateTimeOffset Parse(object value) => value switch
        {
            DateTimeOffset dto => dto.ToUniversalTime(),
            DateTime dt => new DateTimeOffset(DateTime.SpecifyKind(dt, DateTimeKind.Utc)),
            string s => DateTimeOffset.Parse(s).ToUniversalTime(),
            _ => throw new InvalidCastException($"Cannot convert '{value.GetType()}' to DateTimeOffset."),
        };
    }

    private sealed class DateOnlyHandler : SqlMapper.TypeHandler<DateOnly>
    {
        public override void SetValue(IDbDataParameter parameter, DateOnly value)
        {
            parameter.Value = value;
        }

        public override DateOnly Parse(object value) => value switch
        {
            DateOnly d => d,
            DateTime dt => DateOnly.FromDateTime(dt),
            DateTimeOffset dto => DateOnly.FromDateTime(dto.Date),
            string s => DateOnly.Parse(s),
            _ => throw new InvalidCastException($"Cannot convert '{value.GetType()}' to DateOnly."),
        };
    }
}
