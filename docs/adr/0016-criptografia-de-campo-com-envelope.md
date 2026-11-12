# ADR-016: Criptografia de campo com envelope (AES-GCM do .NET) e master key fora do banco

- **Status:** Aceito
- **Data:** 2026-11-12

## Contexto

O RNF-06 pede que 100% dos tokens da Pluggy, das chaves de IA e dos segredos TOTP fiquem cifrados em envelope, com a master key fora do banco. Uma cópia do banco, como um backup vazado, não pode revelar esses segredos. O payload bruto do provedor também traz dados de terceiros, como nome e documento de quem recebeu um Pix [Conferir: campos de paymentData na Pluggy].

## Decisão

- **Master key** de 256 bits fora do banco, numa variável de ambiente ou num Docker secret. A instância não sobe sem ela (RN-39). Cada master key tem um id, para a rotação.
- **Chaves de dados (DEK)** de 256 bits por casa e finalidade, guardadas em `keyring.data_key`, seladas pela master key.
- **Cifra** AES-256-GCM com a classe `AesGcm` do .NET, nonce aleatório de 12 bytes e tag de 16 bytes. Um só `bytea` guarda a versão do formato, o id da DEK, o nonce, o texto cifrado e a tag. Os dados associados (AAD) amarram o valor à tabela, à coluna e ao id da linha, então um valor copiado para outra linha não decifra.
- **Cifrado:** segredo TOTP, payload bruto do provedor (transação e fatura), credencial de provedor guardada no banco e chave de IA (v1).
- **Com hash, sem cifra:** senha (Argon2id), códigos de recuperação e refresh tokens.
- **Em claro:** os campos normalizados das transações, porque busca, filtros e somas precisam deles. A proteção deles é a rede privada, o disco da máquina e o backup cifrado (ADR-029).
- No MVP, o client id e o secret da Pluggy ficam no `.env`, fora do banco [Suposição].

## Alternativas consideradas

- **pgcrypto:** a chave viajaria dentro das consultas e poderia parar nos logs do banco.
- **Cifrar a transação inteira:** impede busca e soma no banco.
- **Só disco cifrado:** um dump do banco sairia com os segredos legíveis.
- **ASP.NET Core Data Protection:** serve, mas no Linux o anel de chaves precisa de outro protetor, e o formato e a rotação ficam fora do nosso controle. O envelope próprio é pouco código e tem teste.

## Consequências

- Rotacionar a master key é selar de novo só as DEKs. Rotacionar uma DEK é criar outra e recifrar aos poucos; a antiga ganha `retired_at` e continua decifrando.
- Perder a master key perde os segredos TOTP, redefinidos por comando no servidor, e os payloads brutos. Os campos normalizados ficam. O guia de backup manda guardar a master key em outro lugar (ADR-029).
- Uma DEK por casa permite, no apagar tudo (RF-07), destruir a chave junto com os dados.
- O teste do RNF-06 procura os segredos em texto puro numa cópia do banco.
