using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();
builder.Services.AddHttpClient("benefits-eligibility", client =>
{
    client.Timeout = TimeSpan.FromSeconds(5);
});
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
var paymentDatabaseName = Environment.GetEnvironmentVariable("PAYMENT_DATABASE_NAME") ?? "";
var benefitsApiUrl = Environment.GetEnvironmentVariable("BENEFITS_API_URL")?.TrimEnd('/');
var benefitsMemberId = Environment.GetEnvironmentVariable("BENEFITS_MEMBER_ID") ?? "1001";

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "payment-service" }));

app.MapGet("/payments", async (IHttpClientFactory httpClientFactory) =>
{
    try
    {
        if (!string.IsNullOrEmpty(benefitsApiUrl))
        {
            var benefitsClient = httpClientFactory.CreateClient("benefits-eligibility");
            using var eligibilityResponse = await benefitsClient.GetAsync(
                $"{benefitsApiUrl}/eligibility/{benefitsMemberId}");
            eligibilityResponse.EnsureSuccessStatusCode();
        }

        if (string.IsNullOrEmpty(dbConn) ||
            string.IsNullOrEmpty(paymentDatabaseName) ||
            !string.Equals(
                new NpgsqlConnectionStringBuilder(dbConn).Database,
                paymentDatabaseName,
                StringComparison.OrdinalIgnoreCase))
        {
            return Results.Ok(new { payments = new[] { new { id = 1, amount = 99.99, status = "completed" } }, source = "mock" });
        }

        await using var conn = new NpgsqlConnection(dbConn);
        await conn.OpenAsync();
        return Results.Ok(new { payments = new[] { new { id = 1, amount = 99.99, status = "completed" } }, source = "database" });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Payment data request failed");
        return Results.Problem("Payment data is temporarily unavailable.", statusCode: 500);
    }
});

app.MapPost("/payments/process", async (
    IHttpClientFactory httpClientFactory,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrEmpty(benefitsApiUrl))
    {
        logger.LogError("BENEFITS_API_URL is not configured");
        return Results.Json(new
        {
            errorCode = "benefits_service_not_configured",
            detail = "Benefits verification is unavailable.",
            charged = false
        }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }

    try
    {
        var benefitsClient = httpClientFactory.CreateClient("benefits-eligibility");
        using var eligibilityResponse = await benefitsClient.GetAsync(
            $"{benefitsApiUrl}/eligibility/{benefitsMemberId}",
            cancellationToken);

        if (!eligibilityResponse.IsSuccessStatusCode)
        {
            logger.LogError(
                "Benefits verification returned status {StatusCode} for member {MemberId}",
                (int)eligibilityResponse.StatusCode,
                benefitsMemberId);
            return Results.Json(new
            {
                errorCode = "benefits_verification_unavailable",
                detail = "We could not verify your prescription benefits.",
                charged = false
            }, statusCode: StatusCodes.Status503ServiceUnavailable);
        }

        var eligibility = await eligibilityResponse.Content.ReadFromJsonAsync<BenefitsEligibility>(
            cancellationToken);
        if (eligibility is null)
        {
            logger.LogError(
                "Benefits verification returned no data for member {MemberId}",
                benefitsMemberId);
            return Results.Json(new
            {
                errorCode = "benefits_verification_invalid",
                detail = "We could not verify your prescription benefits.",
                charged = false
            }, statusCode: StatusCodes.Status503ServiceUnavailable);
        }

        if (!eligibility.Eligible)
        {
            return Results.Json(new
            {
                errorCode = "benefits_not_eligible",
                detail = "Your benefits require review before this prescription can be paid.",
                charged = false
            }, statusCode: StatusCodes.Status409Conflict);
        }

        await Task.Delay(Random.Shared.Next(100, 500), cancellationToken);
        return Results.Ok(new
        {
            status = "processed",
            transactionId = Guid.NewGuid(),
            memberId = eligibility.MemberId,
            amount = eligibility.Copay,
            plan = eligibility.Plan,
            source = eligibility.Source,
            charged = true
        });
    }
    catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogError(ex, "Benefits verification timed out for member {MemberId}", benefitsMemberId);
        return Results.Json(new
        {
            errorCode = "benefits_verification_timeout",
            detail = "Benefits verification timed out.",
            charged = false
        }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (Exception ex) when (ex is HttpRequestException or System.Text.Json.JsonException)
    {
        logger.LogError(ex, "Benefits verification failed for member {MemberId}", benefitsMemberId);
        return Results.Json(new
        {
            errorCode = "benefits_verification_unavailable",
            detail = "We could not verify your prescription benefits.",
            charged = false
        }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
});

app.Run();

sealed record BenefitsEligibility(
    int MemberId,
    bool Eligible,
    string Plan,
    string RxGroup,
    decimal Copay,
    string Source);
