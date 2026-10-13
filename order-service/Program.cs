using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
using Azure.Messaging.ServiceBus;
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
        .ConfigureResource(r => r.AddService("order-service"))
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
var sbConn = Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION") ?? "";

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "order-service" }));

app.MapGet("/orders", async () =>
{
    try
    {
        if (string.IsNullOrEmpty(dbConn))
            return Results.Ok(new { orders = new[] { new { id = 1, item = "Mock Order", status = "pending" } }, source = "mock" });

        await using var conn = new NpgsqlConnection(dbConn);
        await conn.OpenAsync();
        return Results.Ok(new { orders = new[] { new { id = 1, item = "DB Order", status = "active" } }, source = "database" });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Database error on GET /orders: {ErrorMessage}", ex.Message);
        return Results.Problem("Order data is temporarily unavailable.", statusCode: 500);
    }
});

app.MapPost("/orders", async () =>
{
    try
    {
        // Publish to Service Bus queue
        if (!string.IsNullOrEmpty(sbConn))
        {
            await using var client = new ServiceBusClient(sbConn);
            var sender = client.CreateSender("orders");
            await sender.SendMessageAsync(new ServiceBusMessage($"{{\"orderId\": \"{Guid.NewGuid()}\"}}"));
        }
        return Results.Ok(new { status = "created", message = "Order queued for processing" });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Queue error on POST /orders: {ErrorMessage}", ex.Message);
        return Results.Problem("The order could not be submitted.", statusCode: 500);
    }
});

app.Run();
