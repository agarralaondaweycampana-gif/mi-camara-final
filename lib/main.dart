import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializamos Firebase directo con el proyecto que creaste en la web
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cámara WebRTC Global',
      theme: ThemeData.dark(),
      home: const PantallaInicio(),
    );
  }
}

class PantallaInicio extends StatelessWidget {
  const PantallaInicio({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cámara Seguridad 2026')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.videocam, size: 30),
              label: const Text('MODO CELULAR CÁMARA (Viejo)',
                  style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PantallaCamara())),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: const Icon(Icons.visibility, size: 30),
              label: const Text('MODO CELULAR VISOR (Nuevo)',
                  style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: Colors.blueAccent),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PantallaVisor())),
            ),
          ],
        ),
      ),
    );
  }
}

// ================== MODO CÁMARA (TRANSMISOR) ==================
class PantallaCamara extends StatefulWidget {
  const PantallaCamara({super.key});
  @override
  State<PantallaCamara> createState() => _PantallaCamaraState();
}

class _PantallaCamaraState extends State<PantallaCamara> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  final String _codigoVinculacion = "8844"; // Tu clave mágica de conexión
  bool _transmitiendo = false;

  // Servidores STUN públicos de Google para cruzar redes y funcionar en la calle (4G/5G)
  Map<String, dynamic> configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  void _initRenderers() async {
    await _localRenderer.initialize();
  }

  void _encenderCamara() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {'facingMode': 'environment'}
    };
    MediaStream stream =
        await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = stream;

    _peerConnection = await createPeerConnection(configuration);
    stream
        .getTracks()
        .forEach((track) => _peerConnection!.addTrack(track, stream));

    // Guardar candidatos de red en Firebase
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      FirebaseFirestore.instance
          .collection('conexiones')
          .doc(_codigoVinculacion)
          .collection('camaraCandidates')
          .add(candidate.toMap());
    };

    // Crear la oferta de video (Offer)
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // Subir la oferta a la nube para que el visor la encuentre
    await FirebaseFirestore.instance
        .collection('conexiones')
        .doc(_codigoVinculacion)
        .set({'offer': offer.toMap()});

    // Escuchar si el Visor nos responde desde internet
    FirebaseFirestore.instance
        .collection('conexiones')
        .doc(_codigoVinculacion)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists && snapshot.data()!.containsKey('answer')) {
        var data = snapshot.data();
        var answer = RTCSessionDescription(
            data!['answer']['sdp'], data['answer']['type']);
        await _peerConnection!.setRemoteDescription(answer);
      }
    });

    // Escuchar los candidatos del visor
    FirebaseFirestore.instance
        .collection('conexiones')
        .doc(_codigoVinculacion)
        .collection('visorCandidates')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data();
          _peerConnection!.addCandidate(RTCIceCandidate(
              data!['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });

    setState(() => _transmitiendo = true);
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cámara - Código: $_codigoVinculacion')),
      body: Stack(
        children: [
          RTCVideoView(_localRenderer, mirror: false),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _transmitiendo ? Colors.green : Colors.blue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 15)),
                onPressed: _transmitiendo ? null : _encenderCamara,
                child: Text(_transmitiendo
                    ? 'TRANSMITIENDO EN VIVO GLOBAL'
                    : 'INICIAR CÁMARA'),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ================== MODO VISOR (RECEPTOR) ==================
class PantallaVisor extends StatefulWidget {
  const PantallaVisor({super.key});
  @override
  State<PantallaVisor> createState() => _PantallaVisorState();
}

class _PantallaVisorState extends State<PantallaVisor> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  String _codigoVinculacion = ""; // Sin 'final' y vacía para poder escribirla;

  Map<String, dynamic> configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  void _initRenderers() async {
    await _remoteRenderer.initialize();
  }

  void _conectarConCamara() async {
    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        setState(() => _remoteRenderer.srcObject = event.streams[0]);
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      FirebaseFirestore.instance
          .collection('conexiones')
          .doc(_codigoVinculacion)
          .collection('visorCandidates')
          .add(candidate.toMap());
    };

    // Buscar la oferta de la cámara en Firebase
    var doc = await FirebaseFirestore.instance
        .collection('conexiones')
        .doc(_codigoVinculacion)
        .get();
    if (doc.exists) {
      var data = doc.data();
      var offer =
          RTCSessionDescription(data!['offer']['sdp'], data['offer']['type']);
      await _peerConnection!.setRemoteDescription(offer);

      // Crear la respuesta (Answer) para avisarle a la cámara
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Subir la respuesta para que la cámara la lea
      await FirebaseFirestore.instance
          .collection('conexiones')
          .doc(_codigoVinculacion)
          .update({'answer': answer.toMap()});
    }

    // Escuchar candidatos de la cámara
    FirebaseFirestore.instance
        .collection('conexiones')
        .doc(_codigoVinculacion)
        .collection('camaraCandidates')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data();
          _peerConnection!.addCandidate(RTCIceCandidate(
              data!['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });
  }

void _conectarTransmision() {
    // Si tenías otra función para enganchar, la podés llamar acá adentro
  }
  @override
  void dispose() {
    _remoteRenderer.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visor Remoto')),
      body: Stack(
        children: [
          RTCVideoView(_remoteRenderer),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200), // Manera correcta en Flutter
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. El casillero flotante para escribir el código
                  TextField(
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: const InputDecoration(
                      labelText: 'Ingresá el código de la cámara',
                      labelStyle: TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black54,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue, width: 2.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.green, width: 2.0),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _codigoVinculacion = value;
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  // 2. Tu botón de siempre
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    ),
                    onPressed: () {
                      _conectarTransmision();
                    },
                    child: const Text(
                      'ENGANCHAR TRANSMISIÓN (Mundial)',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),