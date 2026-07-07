import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../../attendance/widgets/today_card.dart';

/// Home dashboard carousel: a bold check-in hero, then compact cards the
/// employee swipes through — tasks, requests, reports. The three info cards are
/// scaffolded with empty states; wire them to providers once the backend gains
/// Task / Request / Report models.
class HomeCarousel extends StatefulWidget {
  const HomeCarousel({super.key});

  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> {
  final _controller = PageController(viewportFraction: 0.94);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cards = <Widget>[
      // Card 1 — the live check-in hero (interactive).
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: TodayAttendanceCard(compact: true),
      ),
      _CarouselCard(
        icon: Icons.checklist_rounded,
        accent: Brand.blue,
        title: 'Tasks',
        headline: '0',
        unit: 'open',
        subtitle: 'Nothing assigned right now.',
      ),
      _CarouselCard(
        icon: Icons.inbox_rounded,
        accent: Brand.orange,
        title: 'Requests',
        headline: '0',
        unit: 'pending',
        subtitle: 'No approvals waiting.',
      ),
      _CarouselCard(
        icon: Icons.description_rounded,
        accent: Brand.green,
        title: 'Reports due',
        headline: '0',
        unit: 'due',
        subtitle: 'You’re all caught up.',
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: cards,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < cards.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _page == i ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _page == i ? Brand.green : Brand.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.headline,
    required this.unit,
    required this.subtitle,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String headline;
  final String unit;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: Brand.shadowCard,
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Brand.ink,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Brand.ink,
                    fontSize: 32,
                    letterSpacing: -1,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    unit,
                    style: const TextStyle(color: Brand.mute, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Brand.slate, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
