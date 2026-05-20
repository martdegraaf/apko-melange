using System.Text.Json.Serialization;

var builder = WebApplication.CreateSlimBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

var app = builder.Build();

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild",
    "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

app.MapGet("/", () => new AppInfo(
    "WeatherApi",
    System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
    System.Runtime.InteropServices.RuntimeInformation.OSDescription,
    System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString(),
    DateTime.UtcNow
));

app.MapGet("/weatherforecast", () =>
{
    var forecast = Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast(
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20, 55),
            summaries[Random.Shared.Next(summaries.Length)]
        ))
        .ToArray();
    return forecast;
});

app.Run();

record AppInfo(string App, string Runtime, string OS, string Arch, DateTime Timestamp);

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}

[JsonSerializable(typeof(AppInfo))]
[JsonSerializable(typeof(WeatherForecast[]))]
internal partial class AppJsonContext : JsonSerializerContext { }
