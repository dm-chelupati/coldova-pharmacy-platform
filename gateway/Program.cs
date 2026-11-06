using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
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
        .ConfigureResource(r => r.AddService("gateway"))
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

builder.Services.AddHttpClient("backend", client =>
{
    client.Timeout = TimeSpan.FromSeconds(6);
});
var app = builder.Build();
var logger = app.Logger;

var orderUrl = Environment.GetEnvironmentVariable("ORDER_SERVICE_URL") ?? "http://localhost:8081";
var paymentUrl = Environment.GetEnvironmentVariable("PAYMENT_SERVICE_URL") ?? "http://localhost:8082";
var benefitsUrl = Environment.GetEnvironmentVariable("BENEFITS_SERVICE_URL") ?? "http://localhost:8083";

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "gateway" }));

app.MapGet("/api/orders", async (IHttpClientFactory http) =>
{
    try
    {
        var client = http.CreateClient("backend");
        var response = await client.GetAsync($"{orderUrl}/orders");
        var body = await response.Content.ReadAsStringAsync();
        return Results.Text(body, "application/json", statusCode: (int)response.StatusCode);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Order request failed");
        return Results.Problem("Order processing is temporarily unavailable.", statusCode: 502);
    }
});

app.MapGet("/api/payments", async (IHttpClientFactory http) =>
{
    try
    {
        var client = http.CreateClient("backend");
        var response = await client.GetAsync($"{paymentUrl}/payments");
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadAsStringAsync();
        return Results.Content(body, "application/json");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Payment request failed");
        return Results.Problem("Payment processing is temporarily unavailable.", statusCode: 502);
    }
});

app.MapPost("/api/payments/process", async (
    IHttpClientFactory http,
    CancellationToken cancellationToken) =>
{
    try
    {
        var client = http.CreateClient("backend");
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{paymentUrl}/payments/process");
        using var response = await client.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        return Results.Text(body, "application/json", statusCode: (int)response.StatusCode);
    }
    catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogError(ex, "Payment processing timed out");
        return Results.Problem("Payment processing timed out. No charge was made.", statusCode: 504);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Payment processing failed");
        return Results.Problem("Payment processing is temporarily unavailable. No charge was made.", statusCode: 502);
    }
});

app.MapGet("/api/benefits/{memberId:int}", async (
    int memberId,
    IHttpClientFactory http,
    CancellationToken cancellationToken) =>
{
    try
    {
        var client = http.CreateClient("backend");
        using var response = await client.GetAsync(
            $"{benefitsUrl}/eligibility/{memberId}",
            cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        return Results.Text(body, "application/json", statusCode: (int)response.StatusCode);
    }
    catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogError(ex, "Benefits request timed out for member {MemberId}", memberId);
        return Results.Problem("Benefits eligibility timed out.", statusCode: 504);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Benefits request failed for member {MemberId}", memberId);
        return Results.Problem("Benefits eligibility is temporarily unavailable.", statusCode: 502);
    }
});

app.MapGet("/api/catalog", async (IHttpClientFactory http, CancellationToken cancellationToken) =>
{
    try
    {
        var client = http.CreateClient("backend");
        using var response = await client.GetAsync($"{benefitsUrl}/catalog", cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        return Results.Text(body, "application/json", statusCode: (int)response.StatusCode);
    }
    catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogError(ex, "Catalog request timed out");
        return Results.Problem("The pharmacy catalog timed out.", statusCode: 504);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Catalog request failed");
        return Results.Problem("The pharmacy catalog is temporarily unavailable.", statusCode: 502);
    }
});

app.Run();
