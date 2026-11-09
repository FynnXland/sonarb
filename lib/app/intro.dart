import 'package:flutter/material.dart';

import 'sonar_mark.dart';
import 'theme.dart';

/// Zeigt beim Start das Logo mit einem Peilkeil, der sich einmal dreht (etwa 1,3 s),
/// und blendet dann [child] ein. Der native Splash zeigt dasselbe Bild ruhend, der Übergang
/// ist deshalb nahtlos. Läuft [ready] länger nicht, dreht sich der Keil weiter.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.ready, required this.child});

  /// Erst wenn die Module geladen sind, folgt [child].
  final bool ready;
  final Widget child;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: SonarMotion.intro,
  );
  late final Animation<double> _sweep = CurvedAnimation(
    parent: _turn,
    curve: Curves.easeInOutCubic,
  );
  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _done = true;
      return;
    }
    _turn.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (widget.ready) {
        setState(() => _done = true);
      } else {
        _turn.forward(from: 0);
      }
    });
    _turn.forward();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showChild = widget.ready && _done;
    return AnimatedSwitcher(
      duration: SonarMotion.fade,
      child: showChild
          ? KeyedSubtree(key: const ValueKey('cockpit'), child: widget.child)
          : Scaffold(
              key: const ValueKey('intro'),
              body: Center(
                child: Semantics(
                  label: 'Sonarb startet',
                  child: SonarMark(sweep: _sweep),
                ),
              ),
            ),
    );
  }
}
