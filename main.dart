import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AnimeTrackerApp());
}

class AnimeTrackerApp extends StatelessWidget {
  const AnimeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C4DFF),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Anime Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF0E0E12),
        cardColor: const Color(0xFF1B1B22),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0E0E12),
          elevation: 0,
          centerTitle: false,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
      ),
      home: const HomeScreen(),
    );
  }
}

// --- Modelo -----------------------------------------------------------

class Episodio {
  final String id;
  final String titulo;
  final int? episodio;
  final String? imagenUrl;
  final String capituloUrl;
  final List<String> linksReferencia;

  Episodio({
    required this.id,
    required this.titulo,
    required this.episodio,
    required this.imagenUrl,
    required this.capituloUrl,
    required this.linksReferencia,
  });

  factory Episodio.fromFirestore(String id, Map<String, dynamic> data) {
    return Episodio(
      id: id,
      titulo: (data['titulo'] as String?) ?? 'Sin título',
      episodio: data['episodio'] is int ? data['episodio'] as int : null,
      imagenUrl: data['imagen_url'] as String?,
      capituloUrl: (data['capitulo_url'] as String?) ?? '',
      linksReferencia: (data['links_referencia'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

// --- Pantalla principal (Con Buscador Integrado) ---------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _buscando = false;
  String _consulta = '';
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _activarBusqueda() {
    setState(() => _buscando = true);
  }

  void _cerrarBusqueda() {
    setState(() {
      _buscando = false;
      _consulta = '';
      _controller.clear();
    });
  }

  List<Episodio> _filtrar(List<Episodio> episodios) {
    if (_consulta.trim().isEmpty) return episodios;
    final query = _consulta.toLowerCase();
    return episodios
        .where((e) => e.titulo.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
      final coleccion = FirebaseFirestore.instance
        .collection('tracker_episodios')
        .orderBy('titulo', descending: false)
        .orderBy(FieldPath.documentId, descending: true);

    return Scaffold(
      appBar: AppBar(
        title: _buscando
            ? TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Buscar anime...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _consulta = value),
              )
            : const Text(
                'Mi Tracker de Anime',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          IconButton(
            icon: Icon(_buscando ? Icons.close : Icons.search),
            onPressed: _buscando ? _cerrarBusqueda : _activarBusqueda,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: coleccion.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Ocurrió un error al cargar los datos.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Aún no hay episodios guardados.\nEjecuta el script de Python para poblar Firestore.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final episodios = docs
              .map((doc) => Episodio.fromFirestore(doc.id, doc.data()))
              .toList();

          final filtrados = _filtrar(episodios);

          if (filtrados.isEmpty) {
            return const Center(
              child: Text(
                'No se encontraron animes con ese nombre.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: filtrados.length,
            itemBuilder: (context, index) {
              return EpisodioCard(episodio: filtrados[index]);
            },
          );
        },
      ),
    );
  }
}

// --- Tarjeta de Episodio --------------------------------------------------

class EpisodioCard extends StatelessWidget {
  final Episodio episodio;
  const EpisodioCard({super.key, required this.episodio});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetalleScreen(episodio: episodio)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (episodio.imagenUrl != null && episodio.imagenUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: episodio.imagenUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                errorWidget: (context, url, error) => Container(color: const Color(0xFF1B1B22), child: const Icon(Icons.broken_image)),
              )
            else
              Container(color: const Color(0xFF1B1B22), child: const Icon(Icons.image_not_supported)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
            ),
            if (episodio.episodio != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                  child: Text('EP ${episodio.episodio}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(episodio.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Pantalla de detalle --------------------------------------------------

class DetalleScreen extends StatelessWidget {
  final Episodio episodio;
  const DetalleScreen({super.key, required this.episodio});

  Future<void> _abrirEnlaceExterno(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: episodio.imagenUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(imageUrl: episodio.imagenUrl!, fit: BoxFit.cover),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Theme.of(context).scaffoldBackgroundColor,
                              ],
                              stops: const [0.4, 1.0],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(color: const Color(0xFF1B1B22)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episodio.titulo,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (episodio.episodio != null)
                    Chip(
                      label: Text('Episodio ${episodio.episodio}'),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.2),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Fuente',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _abrirEnlaceExterno(context, episodio.capituloUrl),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir página original'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Servidores de Video disponibles:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (episodio.linksReferencia.isEmpty)
                    const Text(
                      'No hay servidores detectados para este episodio.',
                      style: TextStyle(color: Colors.white54),
                    )
                  else
                    Column(
                      children: episodio.linksReferencia.asMap().entries.map((entry) {
                        int index = entry.key + 1;
                        String link = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ReproductorScreen(
                                      videoUrl: link,
                                      titulo: '${episodio.titulo} - Servidor $index',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.play_circle_fill),
                              label: Text(
                                'Reproducir en Servidor $index',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Reproductor Interno WebView -------------------------------------------

class ReproductorScreen extends StatefulWidget {
  final String videoUrl;
  final String titulo;

  const ReproductorScreen({
    super.key,
    required this.videoUrl,
    required this.titulo,
  });

  @override
  State<ReproductorScreen> createState() => _ReproductorScreenState();
}

class _ReproductorScreenState extends State<ReproductorScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() {
            _isLoading = true;
          }),
          onPageFinished: (url) => setState(() {
            _isLoading = false;
          }),
          onNavigationRequest: (request) {
            // Protección contra redirecciones publicitarias (Pop-ups)
            if (request.url.contains(widget.videoUrl) ||
                request.url.contains('mega.nz') ||
                request.url.contains('streamtape') ||
                request.url.contains('fembed') ||
                request.url.contains('filemoon') ||
                request.url.contains('mp4upload')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.videoUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.titulo, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
