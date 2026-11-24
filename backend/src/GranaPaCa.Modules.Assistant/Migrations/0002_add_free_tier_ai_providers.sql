-- Expand allowed AI providers to include zero-cost and low-cost OpenAI-compatible options (ADR-020).
ALTER TABLE assistant.provider_config
    DROP CONSTRAINT IF EXISTS provider_config_provider_check,
    ADD CONSTRAINT provider_config_provider_check CHECK (
        provider IN (
            'none',
            'openai',
            'anthropic',
            'google',
            'ollama',
            'groq',
            'openrouter',
            'openai_compatible'
        )
    );
