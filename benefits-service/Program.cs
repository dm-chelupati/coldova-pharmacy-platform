var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "benefits-service" }));

app.MapGet("/eligibility/{memberId:int}", (int memberId) =>
    Results.Ok(new
    {
        memberId,
        eligible = true,
        plan = "Coldova Plus"
    }));

app.Run();
