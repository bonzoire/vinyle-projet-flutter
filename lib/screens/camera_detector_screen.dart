import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/vinyl_detection_result.dart';
import '../services/vinyl_detector.dart';
import '../widgets/vinyl_overlay_painter.dart';

class CameraDetectorScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraDetectorScreen({super.key, required this.cameras});

  @override
  State<CameraDetectorScreen> createState() => _CameraDetectorScreenState();
}

class _CameraDetectorScreenState extends State<CameraDetectorScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isAnalyzing = false;
  FlashMode _flashMode = FlashMode.off;

  // Résultat de l'analyse et image capturée
  File? _capturedImage;
  Size? _capturedImageSize;
  VinylDetectionResult? _detectionResult;

  final VinylDetector _detector = VinylDetector();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.cameras.isNotEmpty) {
      _initCamera(widget.cameras[_selectedCameraIndex]);
    }
  }

  Future<void> _initCamera(CameraDescription cameraDescription) async {
    final prevController = _controller;
    final controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await prevController?.dispose();

    try {
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (mounted) {
        setState(() {
          _controller = controller;
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur initialisation caméra : $e')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      camera.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(camera.description);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndAnalyze() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized || _isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      final xFile = await camera.takePicture();
      final file = File(xFile.path);

      // Récupérer la taille réelle de l'image capturée
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );

      // Exécuter l'analyse des sillons OpenCV
      final result = await _detector.detectFromFile(file.path);

      if (mounted) {
        setState(() {
          _capturedImage = file;
          _capturedImageSize = imageSize;
          _detectionResult = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la capture : $e')),
        );
      }
    }
  }

  void _resetCapture() {
    setState(() {
      _capturedImage = null;
      _capturedImageSize = null;
      _detectionResult = null;
    });
  }

  Future<void> _toggleFlash() async {
    final camera = _controller;
    if (camera == null) return;

    final nextMode = _flashMode == FlashMode.off
        ? FlashMode.torch
        : FlashMode.off;

    await camera.setFlashMode(nextMode);
    setState(() {
      _flashMode = nextMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Détecteur de Sillons Vinyle'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          if (_capturedImage == null && _isCameraInitialized)
            IconButton(
              icon: Icon(
                _flashMode == FlashMode.torch
                    ? Icons.flash_on
                    : Icons.flash_off,
                color: _flashMode == FlashMode.torch
                    ? Colors.amber
                    : Colors.white70,
              ),
              onPressed: _toggleFlash,
              tooltip: 'Lampe torche',
            ),
        ],
      ),
      body: _isAnalyzing
          ? _buildLoadingView()
          : _capturedImage != null
              ? _buildAnalysisView()
              : _buildCameraPreviewView(),
    );
  }

  /// Vue du flux caméra en direct avec guide circulaire
  Widget _buildCameraPreviewView() {
    if (!_isCameraInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Prévisualisation caméra
        Center(
          child: CameraPreview(_controller!),
        ),

        // Guide visuel circulaire pour aider au cadrage
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            height: MediaQuery.of(context).size.width * 0.85,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.6),
                width: 2.0,
              ),
            ),
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.add, color: Colors.white70, size: 20),
              ),
            ),
          ),
        ),

        // Consigne en haut
        Positioned(
          top: 24,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Centrez le vinyle et le macaron dans le repère',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),

        // Bouton de déclenchement en bas
        Positioned(
          bottom: 30,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _captureAndAnalyze,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.black87,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Vue de chargement pendant l'analyse OpenCV
  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.amber),
          SizedBox(height: 20),
          Text(
            'Analyse des sillons en cours...',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Détection du centre et calcul des profils radiaux',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Vue du résultat : Photo + Détection OpenCV dessinée par-dessus
  Widget _buildAnalysisView() {
    final result = _detectionResult;
    final imageFile = _capturedImage;
    final imgSize = _capturedImageSize;

    if (imageFile == null || imgSize == null || result == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Zone d'affichage de la photo avec l'overlay CustomPainter
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                imageFile,
                fit: BoxFit.contain,
              ),
              if (result.isSuccess)
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: imgSize.width,
                    height: imgSize.height,
                    child: CustomPaint(
                      painter: VinylOverlayPainter(
                        result: result,
                        originalImageSize: imgSize,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Panneau des résultats en bas
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    result.isSuccess ? Icons.check_circle : Icons.error_outline,
                    color: result.isSuccess ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.isSuccess
                          ? 'Vinyle détecté : ${result.trackCount} piste(s)'
                          : 'Échec de détection',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (result.isSuccess) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Rayon : ${result.outerRadius.toStringAsFixed(0)} px',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      'Macaron : ${result.labelRadius.toStringAsFixed(0)} px',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      'Sillons : ${result.trackRadii.length}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ] else if (result.errorMessage != null) ...[
                Text(
                  result.errorMessage!,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _resetCapture,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reprendre une photo'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
