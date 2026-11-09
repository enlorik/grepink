import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/source_image_loader.dart';
import '../services/source_page_loader.dart';

class SourceFigure extends StatefulWidget {
  final SourcePageImage figure;
  final SourceImageLoader? loader;
  final String attribution;
  const SourceFigure({
    super.key,
    required this.figure,
    this.loader,
    this.attribution = 'Article visual · not independent proof',
  });
  @override
  State<SourceFigure> createState() => _SourceFigureState();
}

class _SourceFigureState extends State<SourceFigure> {
  late Future<Uint8List> _image;
  void _load() {
    _image = (widget.loader ?? HttpSourceImageLoader.shared).load(
      widget.figure.url,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SourceFigure old) {
    super.didUpdateWidget(old);
    if (old.figure.url != widget.figure.url || old.loader != widget.loader) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<Uint8List>(
          future: _image,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(_load),
                child: const Text('Image unavailable · retry'),
              );
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 72,
                child: Center(child: Text('Loading article image…')),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  snapshot.data!,
                  cacheWidth: 1000,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  semanticLabel: widget.figure.caption,
                  errorBuilder: (_, error, stack) =>
                      const Text('This article image could not be displayed.'),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          widget.figure.caption,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(widget.attribution, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}
