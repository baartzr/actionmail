import 'package:flutter/material.dart';
import 'package:domail/services/domain_icon_service.dart';

class DomainIcon extends StatefulWidget {
  final String email;
  final double radius;

  const DomainIcon({
    super.key,
    required this.email,
    this.radius = 12,
  });

  @override
  State<DomainIcon> createState() => _DomainIconState();
}

class _DomainIconState extends State<DomainIcon> {
  ImageProvider? _iconProvider;
  bool _loading = true;
  String? _lastEmail;
  final _service = DomainIconService();

  @override
  void initState() {
    super.initState();
    _lastEmail = widget.email;
    _loadIcon();
  }

  @override
  void didUpdateWidget(DomainIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email) {
      _lastEmail = widget.email;
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    setState(() {
      _loading = true;
      _iconProvider = null;
    });
    final provider = await _service.getDomainIcon(widget.email);
    if (mounted && widget.email == _lastEmail) {
      setState(() {
        _iconProvider = provider;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final domain = _service.extractDomain(widget.email);
    final letter = domain.isNotEmpty ? domain[0].toUpperCase() : '?';
    final radius = widget.radius;

    if (_iconProvider != null && !_loading) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ClipOval(
          child: Image(
            image: _iconProvider!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallback(context, letter, radius);
            },
          ),
        ),
      );
    }

    return _buildFallback(context, letter, radius);
  }

  Widget _buildFallback(BuildContext context, String letter, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      child: Text(
        letter,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

