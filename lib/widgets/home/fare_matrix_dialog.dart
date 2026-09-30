import 'package:flutter/material.dart';
import '../../services/fare_matrix.dart';
import '../translated_text.dart';

class HomeFareMatrixDialog extends StatelessWidget {
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

  const HomeFareMatrixDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.08),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _fareRow(
                    'Jeepney',
                    PhFareCalculator.jeepney.estimateRange,
                    Icons.directions_bus,
                    _accent,
                    detail: _ruleDetail(PhFareCalculator.jeepney),
                  ),
                  const SizedBox(height: 8),
                  _fareRow(
                    'City Bus',
                    PhFareCalculator.busOrdinary.estimateRange,
                    Icons.directions_bus_filled,
                    _danger,
                    detail:
                        'first ${_km(PhFareCalculator.busOrdinary.baseKm)}, '
                        'then +${PhFareCalculator.peso(PhFareCalculator.busOrdinary.perKm)}/km '
                        '(aircon +${PhFareCalculator.peso(PhFareCalculator.busAircon.perKm)}/km)',
                  ),
                  const SizedBox(height: 8),
                  _fareRow(
                    'Train (LRT/MRT)',
                    '₱20 – ₱55',
                    Icons.train,
                    const Color(0xFF9B7FE8),
                    detail: 'depends on the number of stations',
                  ),
                  const SizedBox(height: 8),
                  _fareRow(
                    'Tricycle',
                    PhFareCalculator.tricycle.estimateRange,
                    Icons.pedal_bike,
                    const Color(0xFFE89A3C),
                    detail: _ruleDetail(PhFareCalculator.tricycle),
                  ),
                  const SizedBox(height: 8),
                  _fareRow(
                    'FX / UV Express',
                    PhFareCalculator.fxVan.estimateRange,
                    Icons.directions_car,
                    const Color(0xFFD4A017),
                    detail: _ruleDetail(PhFareCalculator.fxVan),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      // Same 16px inset as the fare rows below, so the header icon and the
      // close button line up with the row edges.
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(bottom: BorderSide(color: _border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: _accent,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: TranslatedText(
              'Fare Matrix',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Same size and shape as the icon on the left so both ends balance.
          Material(
            color: _surfaceAlt,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(9),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.close, size: 16, color: _textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _km(double km) =>
      '${km == km.roundToDouble() ? km.toStringAsFixed(0) : km} km';

  static String _ruleDetail(FareRule rule) =>
      'first ${_km(rule.baseKm)}, then +${PhFareCalculator.peso(rule.perKm)}/km';

  Widget _fareRow(
    String label,
    String fare,
    IconData icon,
    Color color, {
    String? detail,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TranslatedText(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                if (detail != null)
                  TranslatedText(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: TranslatedText(
              fare,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
