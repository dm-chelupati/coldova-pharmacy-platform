using System.Net.Http.Headers;
using System.Net.Http.Json;

var builder = WebApplication.CreateBuilder(args);

var options = BenefitsApiOptions.FromConfiguration(builder.Configuration);
builder.Services.AddSingleton(options);
builder.Services.AddHttpClient("onprem-sql", client =>
{
    client.BaseAddress = options.ApiUrl;
    client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
    client.DefaultRequestHeaders.Authorization =
        new AuthenticationHeaderValue("Bearer", options.BearerToken);
});

var app = builder.Build();
var logger = app.Logger;

app.MapGet("/health", () => Results.Ok(new
{
    status = "healthy",
    service = "benefits-service",
    dependency = "on-premises-sql-server"
}));

app.MapGet("/health/dependencies", async (
    IHttpClientFactory httpClientFactory,
    CancellationToken cancellationToken) =>
{
    try
    {
        var client = httpClientFactory.CreateClient("onprem-sql");
        using var response = await client.GetAsync("health", cancellationToken);
        return response.IsSuccessStatusCode
            ? Results.Ok(new
            {
                status = "healthy",
                dependency = "on-premises-sql-server"
            })
            : Results.Json(new
            {
                status = "unhealthy",
                dependency = "on-premises-sql-server",
                errorCode = "benefits_database_unavailable"
            }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
    {
        logger.LogError(ex, "On-premises SQL dependency health request was unsuccessful");
        return Results.Json(new
        {
            status = "unhealthy",
            dependency = "on-premises-sql-server",
            errorCode = "benefits_database_unavailable"
        }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
});

app.MapGet("/eligibility/{memberId:int}", async (
    int memberId,
    IHttpClientFactory httpClientFactory,
    CancellationToken cancellationToken) =>
{
    if (memberId <= 0)
    {
        return Results.BadRequest(new { errorCode = "invalid_member_id", detail = "Member ID must be positive." });
    }

    try
    {
        var client = httpClientFactory.CreateClient("onprem-sql");
        using var response = await client.GetAsync(
            $"api/MemberBenefits/MemberId/{memberId}",
            cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            logger.LogError(
                "On-premises eligibility request returned status {StatusCode} for member {MemberId}",
                (int)response.StatusCode,
                memberId);
            return Results.Problem(
                title: "Benefits eligibility is temporarily unavailable.",
                detail: "The benefits database request was unsuccessful.",
                statusCode: StatusCodes.Status503ServiceUnavailable,
                extensions: new Dictionary<string, object?>
                {
                    ["errorCode"] = "benefits_database_unavailable"
                });
        }

        var result = await response.Content.ReadFromJsonAsync<DabCollection<MemberBenefit>>(
            cancellationToken);
        var member = result?.Value.FirstOrDefault();

        return member is null
            ? Results.NotFound(new { errorCode = "member_not_found", memberId })
            : Results.Ok(new
            {
                memberId = member.MemberId,
                eligible = member.IsEligible,
                plan = member.PlanName,
                rxGroup = member.RxGroup,
                copay = member.CopayAmount,
                source = "on-premises-sql-server"
            });
    }
    catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
    {
        logger.LogError(ex, "On-premises eligibility request timed out for member {MemberId}", memberId);
        return Results.Problem(
            title: "Benefits eligibility is temporarily unavailable.",
            detail: "The benefits database request timed out.",
            statusCode: StatusCodes.Status503ServiceUnavailable,
            extensions: new Dictionary<string, object?>
            {
                ["errorCode"] = "benefits_database_timeout"
            });
    }
    catch (HttpRequestException ex)
    {
        logger.LogError(ex, "On-premises eligibility request was unsuccessful for member {MemberId}", memberId);
        return Results.Problem(
            title: "Benefits eligibility is temporarily unavailable.",
            detail: "The benefits database request was unsuccessful.",
            statusCode: StatusCodes.Status503ServiceUnavailable,
            extensions: new Dictionary<string, object?>
            {
                ["errorCode"] = "benefits_database_unavailable"
            });
    }
});

app.MapGet("/catalog", async (
    IHttpClientFactory httpClientFactory,
    CancellationToken cancellationToken) =>
{
    try
    {
        var client = httpClientFactory.CreateClient("onprem-sql");
        using var response = await client.GetAsync("api/PharmacyProducts", cancellationToken);
        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<DabCollection<PharmacyProduct>>(
            cancellationToken);
        var products = (result?.Value ?? [])
            .Where(product => product.IsActive)
            .OrderBy(product => product.DisplayOrder)
            .Select(product => new
            {
                id = product.ProductId,
                name = product.ProductName,
                category = product.Category,
                price = product.Price,
                availability = product.Availability,
                badge = product.Badge
            });

        return Results.Ok(new { products });
    }
    catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
    {
        logger.LogError(ex, "On-premises catalog request was unsuccessful");
        return Results.Problem(
            title: "The pharmacy catalog is temporarily unavailable.",
            detail: "The catalog database request was unsuccessful.",
            statusCode: StatusCodes.Status503ServiceUnavailable,
            extensions: new Dictionary<string, object?>
            {
                ["errorCode"] = "catalog_database_unavailable"
            });
    }
});

app.Run();

sealed record BenefitsApiOptions(Uri ApiUrl, string BearerToken, int TimeoutSeconds)
{
    public static BenefitsApiOptions FromConfiguration(IConfiguration configuration)
    {
        var rawUrl = configuration["ONPREM_SQL_API_URL"];
        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var apiUrl) ||
            apiUrl.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidOperationException("ONPREM_SQL_API_URL must be an absolute HTTPS URL.");
        }

        var bearerToken = configuration["ONPREM_SQL_API_TOKEN"];
        if (string.IsNullOrWhiteSpace(bearerToken))
        {
            throw new InvalidOperationException("ONPREM_SQL_API_TOKEN is required.");
        }

        var rawTimeout = configuration["ONPREM_SQL_API_TIMEOUT_SECONDS"];
        var timeoutSeconds = 5;
        if (!string.IsNullOrWhiteSpace(rawTimeout) &&
            (!int.TryParse(rawTimeout, out timeoutSeconds) || timeoutSeconds is < 1 or > 30))
        {
            throw new InvalidOperationException(
                "ONPREM_SQL_API_TIMEOUT_SECONDS must be an integer between 1 and 30.");
        }

        return new BenefitsApiOptions(
            new Uri($"{apiUrl.AbsoluteUri.TrimEnd('/')}/"),
            bearerToken,
            timeoutSeconds);
    }
}

sealed record DabCollection<T>(IReadOnlyList<T> Value);

sealed record MemberBenefit(
    int MemberId,
    bool IsEligible,
    string PlanName,
    string RxGroup,
    decimal CopayAmount);

sealed record PharmacyProduct(
    int ProductId,
    string ProductName,
    string Category,
    decimal Price,
    string Availability,
    string Badge,
    int DisplayOrder,
    bool IsActive);
