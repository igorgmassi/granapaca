import '../finance/model.dart';
import '../finance/taxonomy.dart';

enum ProfileOccupation {
  developer('Desenvolvedor', 'Computador e internet estável viram ferramentas de trabalho.'),
  rideshareDriver('Motorista de app', 'Combustível e manutenção entram como essenciais.'),
  designer('Designer', 'Equipamentos e referências criativas apoiam a atividade.'),
  student('Estudante', 'Livros e materiais de estudo entram como essenciais.'),
  teacher('Professor', 'Livros didáticos e internet residencial apoiam as aulas.');

  const ProfileOccupation(this.label, this.description);

  final String label;
  final String description;
}

enum HomeTrait {
  livesAlone('Mora sozinho', 'Compras rápidas de rotina ganham mais peso no dia a dia.'),
  withFamily('Com família', 'Mercado e manutenção da casa abastecem a rotina familiar.'),
  hasChildren('Tem filhos', 'Farmácia e cuidados de saúde têm prioridade constante.'),
  hasPets('Tem pets', 'Ração e cuidados veterinários entram como essenciais.');

  const HomeTrait(this.label, this.description);

  final String label;
  final String description;
}

enum TransportMode {
  carOrMotorcycle('Carro ou moto', 'Combustível mantém o deslocamento diário funcionando.'),
  publicTransit('Transporte público', 'Abastecimento eventual fica como flexível.'),
  rideshare('Aplicativo', 'Corridas por aplicativo viram o meio principal de transporte.'),
  bikeOrWalk('Bicicleta ou a pé', 'Corridas pontuais por aplicativo ficam como flexíveis.');

  const TransportMode(this.label, this.description);

  final String label;
  final String description;
}

/// Multi-select answers from the profile guide (RF-08).
class ProfileAnswers {
  const ProfileAnswers({
    this.occupations = const {},
    this.homeTraits = const {},
    this.transportModes = const {},
  });

  final Set<ProfileOccupation> occupations;
  final Set<HomeTrait> homeTraits;
  final Set<TransportMode> transportModes;

  bool get isEmpty =>
      occupations.isEmpty && homeTraits.isEmpty && transportModes.isEmpty;

  ProfileAnswers copyWith({
    Set<ProfileOccupation>? occupations,
    Set<HomeTrait>? homeTraits,
    Set<TransportMode>? transportModes,
  }) => ProfileAnswers(
    occupations: occupations ?? this.occupations,
    homeTraits: homeTraits ?? this.homeTraits,
    transportModes: transportModes ?? this.transportModes,
  );
}

/// Generates concrete, judgment-free profile rules with pt-BR explanations
/// from the user's multi-select answers (RF-08).
List<UserRule> buildRulesFromProfile(ProfileAnswers answers) {
  final candidates = <UserRule>[];

  for (final occ in answers.occupations) {
    switch (occ) {
      case ProfileOccupation.developer:
        candidates.addAll(const [
          UserRule(
            id: 'profile-dev-internet',
            merchantKey: 'internet fibra lar',
            name: 'Internet Fibra Lar · Desenvolvedor',
            explanation:
                'Internet estável é ferramenta de trabalho para quem desenvolve software.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
          UserRule(
            id: 'profile-dev-notebook',
            merchantKey: 'notebook loja byte',
            name: 'Notebook Loja Byte · Desenvolvedor',
            explanation:
                'Equipamento de informática conta como instrumento de trabalho.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
        ]);
      case ProfileOccupation.rideshareDriver:
        candidates.add(
          const UserRule(
            id: 'profile-driver-fuel',
            merchantKey: 'posto estrada real',
            name: 'Posto Estrada Real · Motorista de app',
            explanation:
                'Combustível é custo direto de trabalho para motorista de aplicativo.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
        );
      case ProfileOccupation.designer:
        candidates.addAll(const [
          UserRule(
            id: 'profile-designer-notebook',
            merchantKey: 'notebook loja byte',
            name: 'Notebook Loja Byte · Designer',
            explanation:
                'Notebook é equipamento principal de criação para design.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
          UserRule(
            id: 'profile-designer-books',
            merchantKey: 'livraria pagina virada',
            name: 'Livraria Página Virada · Designer',
            explanation:
                'Livros e referências visuais apoiam o trabalho criativo.',
            essentiality: Essentiality.important,
            layer: RuleLayer.profile,
          ),
        ]);
      case ProfileOccupation.student:
        candidates.addAll(const [
          UserRule(
            id: 'profile-student-books',
            merchantKey: 'livraria pagina virada',
            name: 'Livraria Página Virada · Estudante',
            explanation:
                'Livros e material de estudo são essenciais durante a formação.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
          UserRule(
            id: 'profile-student-rideshare',
            merchantKey: 'corrida de app',
            name: 'Corrida de app · Estudante',
            explanation:
                'Corridas por aplicativo ficam como flexíveis no orçamento de estudante.',
            essentiality: Essentiality.flexible,
            layer: RuleLayer.profile,
          ),
        ]);
      case ProfileOccupation.teacher:
        candidates.addAll(const [
          UserRule(
            id: 'profile-teacher-books',
            merchantKey: 'livraria pagina virada',
            name: 'Livraria Página Virada · Professor',
            explanation:
                'Livros e material didático apoiam o preparo de aulas.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
          UserRule(
            id: 'profile-teacher-internet',
            merchantKey: 'internet fibra lar',
            name: 'Internet Fibra Lar · Professor',
            explanation:
                'Conexão residencial apoia pesquisa e preparo de aulas.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
        ]);
    }
  }

  for (final trait in answers.homeTraits) {
    switch (trait) {
      case HomeTrait.livesAlone:
        candidates.add(
          const UserRule(
            id: 'profile-alone-bakery',
            merchantKey: 'padaria pao de ontem',
            name: 'Padaria Pão de Ontem · Mora sozinho',
            explanation:
                'Compras rápidas de padaria facilitam a rotina de quem mora só.',
            essentiality: Essentiality.important,
            layer: RuleLayer.profile,
          ),
        );
      case HomeTrait.withFamily:
        candidates.addAll(const [
          UserRule(
            id: 'profile-family-market',
            merchantKey: 'supermercado bom preco',
            name: 'Supermercado Bom Preço · Com família',
            explanation: 'Compras de mercado abastecem a rotina da casa inteira.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
          UserRule(
            id: 'profile-family-home',
            merchantKey: 'loja tudo pra casa',
            name: 'Loja Tudo pra Casa · Com família',
            explanation:
                'Itens de manutenção e organização apoiam o cuidado da casa.',
            essentiality: Essentiality.important,
            layer: RuleLayer.profile,
          ),
        ]);
      case HomeTrait.hasChildren:
        candidates.add(
          const UserRule(
            id: 'profile-children-pharmacy',
            merchantKey: 'farmacia vida plena',
            name: 'Farmácia Vida Plena · Tem filhos',
            explanation:
                'Gastos de farmácia têm prioridade constante em casas com crianças.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
        );
      case HomeTrait.hasPets:
        candidates.add(
          const UserRule(
            id: 'profile-pets-care',
            merchantKey: 'pet',
            name: 'Cuidados com pets · Tem pets',
            explanation:
                'Ração e cuidados veterinários entram como essenciais para quem tem pets.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
        );
    }
  }

  for (final mode in answers.transportModes) {
    switch (mode) {
      case TransportMode.carOrMotorcycle:
        candidates.add(
          const UserRule(
            id: 'profile-car-fuel',
            merchantKey: 'posto estrada real',
            name: 'Posto Estrada Real · Carro ou moto',
            explanation:
                'Combustível mantém o transporte diário funcionando.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
        );
      case TransportMode.publicTransit:
        candidates.add(
          const UserRule(
            id: 'profile-transit-fuel',
            merchantKey: 'posto estrada real',
            name: 'Posto Estrada Real · Transporte público',
            explanation:
                'Abastecimento eventual fica como flexível para quem usa transporte público.',
            essentiality: Essentiality.flexible,
            layer: RuleLayer.profile,
          ),
        );
      case TransportMode.rideshare:
        candidates.add(
          const UserRule(
            id: 'profile-rideshare-app',
            merchantKey: 'corrida de app',
            name: 'Corrida de app · Aplicativo',
            explanation:
                'Corridas por aplicativo são o meio principal de deslocamento.',
            essentiality: Essentiality.essential,
            layer: RuleLayer.profile,
          ),
        );
      case TransportMode.bikeOrWalk:
        candidates.addAll(const [
          UserRule(
            id: 'profile-bike-rideshare',
            merchantKey: 'corrida de app',
            name: 'Corrida de app · Bicicleta ou a pé',
            explanation:
                'Corridas pontuais por aplicativo ficam como flexíveis para quem se desloca a pé ou de bicicleta.',
            essentiality: Essentiality.flexible,
            layer: RuleLayer.profile,
          ),
          UserRule(
            id: 'profile-bike-gym',
            merchantKey: 'academia movimento',
            name: 'Academia Movimento · Bicicleta ou a pé',
            explanation: 'Cuidado físico complementa a rotina ativa.',
            essentiality: Essentiality.important,
            layer: RuleLayer.profile,
          ),
        ]);
    }
  }

  // Deduplicate by merchantKey, favoring the higher essentiality level
  // (essential < important < flexible) so conflicting traits resolve calmly.
  final byKey = <String, UserRule>{};
  for (final rule in candidates) {
    final existing = byKey[rule.merchantKey];
    if (existing == null) {
      byKey[rule.merchantKey] = rule;
    } else {
      final existingRank = existing.essentiality?.index ?? 99;
      final candidateRank = rule.essentiality?.index ?? 99;
      if (candidateRank < existingRank) {
        byKey[rule.merchantKey] = rule;
      }
    }
  }
  return byKey.values.toList(growable: false);
}
