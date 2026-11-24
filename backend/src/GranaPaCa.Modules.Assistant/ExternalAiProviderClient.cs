using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace GranaPaCa.Modules.Assistant;

internal sealed record ExternalCompletionRequest(
    string Provider,
    string Model,
    string? BaseUrl,
    string? ApiKey,
    string SystemPrompt,
    string UserPrompt);

/// <summary>
/// Typed HTTP client for optional BYOK external/local AI providers (ADR-020).
/// Receives ONLY already-minimized and pseudonymized text from PrivacyPseudonymizer (ADR-023).
/// </summary>
internal sealed class ExternalAiProviderClient(
    HttpClient httpClient,
    ILogger<ExternalAiProviderClient> logger)
{
    public async Task<string?> TryCompleteAsync(
        ExternalCompletionRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            return request.Provider switch
            {
                "openai" => await CallOpenAiAsync(request, cancellationToken),
                "anthropic" => await CallAnthropicAsync(request, cancellationToken),
                "google" => await CallGoogleAsync(request, cancellationToken),
                "ollama" => await CallOllamaAsync(request, cancellationToken),
                _ => null
            };
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException or InvalidOperationException)
        {
            logger.LogWarning(
                "External AI provider '{Provider}' did not return a valid completion; falling back to local financial engine.",
                request.Provider);
            return null;
        }
    }

    private async Task<string?> CallOpenAiAsync(
        ExternalCompletionRequest req,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(req.ApiKey))
        {
            return null;
        }

        var baseUrl = string.IsNullOrWhiteSpace(req.BaseUrl)
            ? "https://api.openai.com/v1"
            : req.BaseUrl.TrimEnd('/');
        var model = string.IsNullOrWhiteSpace(req.Model) ? "gpt-4o-mini" : req.Model.Trim();

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/chat/completions");
        httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", req.ApiKey);
        var payload = new
        {
            model,
            temperature = 0.1,
            messages = new[]
            {
                new { role = "system", content = req.SystemPrompt },
                new { role = "user", content = req.UserPrompt }
            }
        };
        httpRequest.Content = new StringContent(
            JsonSerializer.Serialize(payload, AssistantFormatting.WebJson),
            Encoding.UTF8,
            "application/json");

        using var response = await httpClient.SendAsync(httpRequest, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

        if (doc.RootElement.TryGetProperty("choices", out var choices) &&
            choices.ValueKind == JsonValueKind.Array &&
            choices.GetArrayLength() > 0 &&
            choices[0].TryGetProperty("message", out var msg) &&
            msg.TryGetProperty("content", out var content))
        {
            return content.GetString()?.Trim();
        }

        return null;
    }

    private async Task<string?> CallAnthropicAsync(
        ExternalCompletionRequest req,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(req.ApiKey))
        {
            return null;
        }

        var baseUrl = string.IsNullOrWhiteSpace(req.BaseUrl)
            ? "https://api.anthropic.com/v1"
            : req.BaseUrl.TrimEnd('/');
        var model = string.IsNullOrWhiteSpace(req.Model) ? "claude-3-5-haiku-latest" : req.Model.Trim();

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/messages");
        httpRequest.Headers.Add("x-api-key", req.ApiKey);
        httpRequest.Headers.Add("anthropic-version", "2023-06-01");
        var payload = new
        {
            model,
            max_tokens = 600,
            system = req.SystemPrompt,
            messages = new[]
            {
                new { role = "user", content = req.UserPrompt }
            }
        };
        httpRequest.Content = new StringContent(
            JsonSerializer.Serialize(payload, AssistantFormatting.WebJson),
            Encoding.UTF8,
            "application/json");

        using var response = await httpClient.SendAsync(httpRequest, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

        if (doc.RootElement.TryGetProperty("content", out var contentArr) &&
            contentArr.ValueKind == JsonValueKind.Array &&
            contentArr.GetArrayLength() > 0 &&
            contentArr[0].TryGetProperty("text", out var text))
        {
            return text.GetString()?.Trim();
        }

        return null;
    }

    private async Task<string?> CallGoogleAsync(
        ExternalCompletionRequest req,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(req.ApiKey))
        {
            return null;
        }

        var baseUrl = string.IsNullOrWhiteSpace(req.BaseUrl)
            ? "https://generativelanguage.googleapis.com/v1beta"
            : req.BaseUrl.TrimEnd('/');
        var model = string.IsNullOrWhiteSpace(req.Model) ? "gemini-2.0-flash" : req.Model.Trim();

        using var httpRequest = new HttpRequestMessage(
            HttpMethod.Post,
            $"{baseUrl}/models/{Uri.EscapeDataString(model)}:generateContent?key={Uri.EscapeDataString(req.ApiKey)}");

        var payload = new
        {
            systemInstruction = new
            {
                parts = new[] { new { text = req.SystemPrompt } }
            },
            contents = new[]
            {
                new
                {
                    role = "user",
                    parts = new[] { new { text = req.UserPrompt } }
                }
            }
        };
        httpRequest.Content = new StringContent(
            JsonSerializer.Serialize(payload, AssistantFormatting.WebJson),
            Encoding.UTF8,
            "application/json");

        using var response = await httpClient.SendAsync(httpRequest, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

        if (doc.RootElement.TryGetProperty("candidates", out var candidates) &&
            candidates.ValueKind == JsonValueKind.Array &&
            candidates.GetArrayLength() > 0 &&
            candidates[0].TryGetProperty("content", out var content) &&
            content.TryGetProperty("parts", out var parts) &&
            parts.ValueKind == JsonValueKind.Array &&
            parts.GetArrayLength() > 0 &&
            parts[0].TryGetProperty("text", out var text))
        {
            return text.GetString()?.Trim();
        }

        return null;
    }

    private async Task<string?> CallOllamaAsync(
        ExternalCompletionRequest req,
        CancellationToken cancellationToken)
    {
        var baseUrl = string.IsNullOrWhiteSpace(req.BaseUrl)
            ? "http://localhost:11434"
            : req.BaseUrl.TrimEnd('/');
        var model = string.IsNullOrWhiteSpace(req.Model) ? "llama3.2" : req.Model.Trim();

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/api/chat");
        var payload = new
        {
            model,
            stream = false,
            messages = new[]
            {
                new { role = "system", content = req.SystemPrompt },
                new { role = "user", content = req.UserPrompt }
            }
        };
        httpRequest.Content = new StringContent(
            JsonSerializer.Serialize(payload, AssistantFormatting.WebJson),
            Encoding.UTF8,
            "application/json");

        using var response = await httpClient.SendAsync(httpRequest, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

        if (doc.RootElement.TryGetProperty("message", out var message) &&
            message.TryGetProperty("content", out var content))
        {
            return content.GetString()?.Trim();
        }

        return null;
    }
}
