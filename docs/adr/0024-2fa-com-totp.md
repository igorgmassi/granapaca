# ADR-024: 2FA com TOTP; passkeys adiadas

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

A instância concentra o histórico financeiro de todas as contas bancárias da casa, exigindo segundo fator obrigatório além da senha (RF-03, RNF-02, RNF-03). O segundo fator precisa funcionar offline em qualquer autenticador padrão, em Android, iOS, Windows, macOS e Linux, sem depender de SMS, e-mail nem serviço externo.

## Decisão

Exigir 2FA com TOTP padrão RFC 6238 (HMAC-SHA1, 6 dígitos, período de 30 segundos, tolerância de ±1 passo para pequeno desvio de relógio) no módulo `GranaPaCa.Modules.Identity`:

- **Ativação obrigatória no primeiro acesso:** após a criação da conta do dono (RF-02) e o primeiro login com senha, o app obriga ativar o TOTP (QR Code `otpauth://` e chave Base32 manual), confirmar com um código válido e salvar os códigos de recuperação de uso único (RF-03).
- **Proteção no banco:** o segredo TOTP é cifrado em envelope com AES-256-GCM (ADR-016); os códigos de recuperação ficam apenas com hash e são invalidados individualmente no uso.
- **Anti-força bruta e anti-replay:** tentativas respeitam o limite do RNF-04, erros de senha e de código devolvem a mesma mensagem genérica, e o último passo TOTP aceito é registrado para recusar reuso dentro da mesma janela.
- **Passkeys (WebAuthn/FIDO2):** adiadas para depois do MVP.

## Alternativas consideradas

- **Passkeys (WebAuthn/FIDO2) no MVP:** exige domínio HTTPS estável como *relying party* e ainda tem suporte desigual em Flutter desktop (especialmente Linux), conflitando com acesso inicial via IP de rede privada (Tailscale).
- **Códigos por SMS ou e-mail:** dependem de provedor externo pago ou SMTP configurado pelo dono, além de sofrerem com troca de chip e atrasos de entrega.
- **Apenas senha, sem segundo fator:** superfície de risco alta demais para dados financeiros consolidados.

## Consequências

- Funciona com qualquer app autenticador aberto (Aegis, Ente Auth, Bitwarden, KeePassXC, Google/Microsoft Authenticator) sem nenhuma conta ou custo externo.
- Perder o autenticador e todos os códigos de recuperação — ou perder a master key (ADR-016) — exige acesso direto ao servidor para redefinir o 2FA por comando administrativo, evitando recuperação remota insegura.
- Passkeys podem ser adicionadas depois como fator alternativo sem alterar o fluxo base de sessões (ADR-019).
