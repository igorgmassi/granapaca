# ADR-022: NFC-e com parser determinístico por estado e fallback opcional de IA

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

Compras em supermercado, farmácia ou varejo chegam ao extrato bancário como um único lançamento consolidado, misturando itens de categorias e essencialidades diferentes. No Brasil, a Nota Fiscal de Consumidor Eletrônica (NFC-e) detalha cada produto no XML padrão nacional da SEFAZ (versão 4.00) e em consultas públicas acessadas pelo QR Code impresso no cupom, cujo layout HTML varia por Secretaria da Fazenda estadual (SEFAZ-UF). Porém, nem sempre a pessoa possui o XML ou um QR Code legível — em alguns casos há apenas uma foto do comprovante.

## Decisão

Implementar no módulo `GranaPaCa.Modules.Receipts` um **pipeline determinístico de extração de NFC-e (XML SEFAZ 4.00 e QR Code por estado, começando pelo Espírito Santo)** com **fallback opcional de visão por IA** somente quando houver apenas imagem ou indisponibilidade da SEFAZ:

- **Camada 1 — Parser determinístico de XML SEFAZ 4.00:** lê diretamente `<nfeProc>` / `<NFe>` / `<infNFe>` usando `System.Xml.Linq`, extraindo chave de acesso (44 dígitos), CNPJ e nome do emitente, data de emissão, descontos, total e lista completa de itens (`<det>/<prod>`) convertidos exatamente para centavos (`BIGINT`, ADR-013), sem rede e sem custo.
- **Camada 2 — Parser de QR Code e adaptador por UF (ES primeiro):** decodifica a URL do QR Code (extraindo a chave de acesso de 44 dígitos e o código da UF) e delega a consulta pública a um adaptador por estado (`INfceStateParser`), começando pela **SEFAZ-ES** e mantendo a interface aberta para novas UFs contribuídas pela comunidade.
- **Camada 3 — Fallback opcional de visão por IA:** quando só existir foto do cupom ou não houver adaptador/disponibilidade para a UF, a pessoa pode acionar explicitamente a extração via provedor de IA configurado (ADR-020), respeitando a minimização e os avisos de privacidade do ADR-023.
- **Revisão antes de dividir a transação:** tanto os itens vindos de XML/QR quanto os sugeridos por visão entram como rascunho conferível; nenhuma divisão ou recategorização altera a transação sem confirmação da pessoa (ADR-012).

## Alternativas consideradas

- **Usar visão/OCR por IA para todos os comprovantes:** gera custo por imagem, imprecisão em centavos ou quantidades e envia documentos fiscais para terceiros mesmo quando o XML ou QR entrega dados estruturados exatos.
- **Contratar API comercial terceirizada de consulta de NFC-e:** cria dependência centralizada e entrega o histórico detalhado de consumo da pessoa a um intermediário, contrariando o modelo self-hosted.
- **Implementar as 27 UFs simultaneamente antes do primeiro lançamento:** cada SEFAZ muda HTML, certificados e mecanismos anti-automação de forma independente; começar pelo padrão nacional XML 4.00 + SEFAZ-ES entrega valor imediato sobre uma abstração fácil de expandir.

## Consequências

- Cupons com XML SEFAZ 4.00 ou QR Code do ES funcionam com precisão exata de centavos, custo zero e nenhum envio de dados para provedores de IA.
- Adicionar novas UFs resume-se a implementar um adaptador isolado acompanhado de fixtures sintéticas em teste unitário, sem tocar no restante do módulo.
- Mudanças no HTML da SEFAZ estadual ou bloqueios temporários degradam graciosamente para conferência manual ou fallback opcional por visão, sem impedir o arquivamento cifrado do comprovante (ADR-025).
