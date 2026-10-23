using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();
// Dynatrace OTLP export — traces + metrics + logs (active when DT_OTLP_ENDPOINT is set)
var dtEndpoint = Environment.GetEnvironmentVariable("DT_OTLP_ENDPOINT");
var dtToken = Environment.GetEnvironmentVariable("DT_OTLP_TOKEN");
if (!string.IsNullOrEmpty(dtEndpoint))
{
    var baseOtlp = dtEndpoint.TrimEnd('/');
    Action<OpenTelemetry.Exporter.OtlpExporterOptions> configureOtlp(string signal) => o =>
    {
        o.Endpoint = new Uri($"{baseOtlp}/v1/{signal}");
        o.Headers = $"Authorization=Api-Token {dtToken}";
        o.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.HttpProtobuf;
    };

    builder.Services.AddOpenTelemetry()
        .ConfigureResource(r => r.AddService("payment-service"))
        .WithTracing(tracing => tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(configureOtlp("traces")))
        .WithMetrics(metrics => metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(configureOtlp("metrics")));

    builder.Logging.AddOpenTelemetry(logging =>
    {
        logging.IncludeScopes = true;
        logging.IncludeFormattedMessage = true;
        logging.AddOtlpExporter(configureOtlp("logs"));
    });
}

var app = builder.Build();
var logger = app.Logger;

var dbConn = Environment.GetEnvironmentVariable("DATABASE_URL") ?? "";

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "payment-service" }));

app.MapGet("/payments", async () =>
{
    try
    {
        if (string.IsNullOrEmpty(dbConn))
            return Results.Ok(new { payments = new[] { new { id = 1, amount = 99.99, status = "completed" } }, source = "mock" });

        await using var conn = new NpgsqlConnection(dbConn);
        await conn.OpenAsync();
        return Results.Problem("Payment processing is temporarily unavailable.", statusCode: 503);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Payment data request failed");
        return Results.Problem("Payment data is temporarily unavailable.", statusCode: 500);
    }
});

app.MapPost("/payments/process", async () =>
{
    await Task.Delay(Random.Shared.Next(100, 500));
    return Results.Ok(new { status = "processed", transactionId = Guid.NewGuid() });
});

app.Run();
