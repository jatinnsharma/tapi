import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/food_repository.dart';
import '../domain/food.dart';

/// Green dot for veg, red for non-veg, both for either: the marks Indian
/// menus use.
class DietMark extends StatelessWidget {
  const DietMark(this.diet, {super.key});

  final Diet diet;

  Widget _square(Color color) => Container(
    width: 14,
    height: 14,
    margin: const EdgeInsets.only(right: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color, width: 1.5),
      borderRadius: BorderRadius.circular(2),
    ),
    alignment: Alignment.center,
    child: Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: diet.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (diet != Diet.nonVeg) _square(const Color(0xFF1B8A3A)),
          if (diet != Diet.veg) _square(const Color(0xFFB3261E)),
        ],
      ),
    );
  }
}

/// "What to eat in Varanasi": the city's signature dishes. Nothing is shown
/// for cities without a list.
class SignatureDishesSection extends ConsumerWidget {
  const SignatureDishesSection({
    super.key,
    required this.cityId,
    required this.cityName,
  });

  final String cityId;
  final String cityName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dishes = ref.watch(signatureDishesProvider(cityId)).value;
    if (dishes == null || dishes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What to eat in $cityName',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Signature dishes: ask locally where they are made best.',
          style: TextStyle(fontSize: 12.5, color: AppTheme.inkMuted),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: dishes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _DishCard(dishes[i]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _DishCard extends StatelessWidget {
  const _DishCard(this.dish);

  final SignatureDish dish;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DietMark(dish.diet),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dish.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              dish.note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.inkMuted,
                height: 1.3,
              ),
            ),
          ),
          Text(
            dish.when,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.amberText,
            ),
          ),
        ],
      ),
    );
  }
}
