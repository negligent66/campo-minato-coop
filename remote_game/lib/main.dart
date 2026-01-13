import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GameScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GameScreen extends StatefulWidget {
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Socket? socket;
  List<List<Map<String, dynamic>>> board = [];
  bool connected = false;
  String buffer = '';
  int playerNumber = 0;
  int currentTurn = 1;
  int flagsRemaining = 0;
  int totalMines = 0;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    connectServer();
  }

  void connectServer() async {
    try {
      socket = await Socket.connect('10.0.2.2', 4040, timeout: Duration(seconds: 5));
      print('Connesso al server!');

      if (!mounted) return;

      setState(() {
        connected = true;
        errorMessage = '';
      });

      socket!.listen(
            (data) {
          try {
            buffer += utf8.decode(data);
            processMessages();
          } catch (e) {
            print('Errore decodifica dati: $e');
          }
        },
        onError: (error) {
          print('Errore socket: $error');
          if (mounted) {
            setState(() {
              errorMessage = 'Errore connessione: $error';
              connected = false;
            });
          }
        },
        onDone: () {
          print('Connessione chiusa');
          if (mounted) {
            setState(() {
              connected = false;
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      print('Errore connessione al server: $e');
      if (mounted) {
        setState(() {
          errorMessage = 'Impossibile connettersi al server: $e';
          connected = false;
        });
      }
    }
  }

  void processMessages() {
    try {
      while (buffer.contains('\n')) {
        int newlineIndex = buffer.indexOf('\n');
        String msg = buffer.substring(0, newlineIndex).trim();
        buffer = buffer.substring(newlineIndex + 1);

        if (msg.isEmpty) continue;

        print('Ricevuto: ${msg.length > 100 ? msg.substring(0, 100) + "..." : msg}');
        handleMessage(msg);
      }
    } catch (e) {
      print('Errore processamento messaggi: $e');
    }
  }

  void handleMessage(String msg) {
    try {
      if (msg.startsWith('PLAYER_NUMBER ')) {
        int pNum = int.parse(msg.split(' ')[1]);
        if (mounted) {
          setState(() {
            playerNumber = pNum;
          });
        }
        print('Sei il giocatore $playerNumber');
      }
      else if (msg.startsWith('TURN ')) {
        int turn = int.parse(msg.split(' ')[1]);
        if (mounted) {
          setState(() {
            currentTurn = turn;
          });
        }
        print('Turno del giocatore $currentTurn');
      }
      else if (msg.startsWith('BOARD_UPDATE ')) {
        String jsonStr = msg.substring('BOARD_UPDATE '.length);
        var decoded = jsonDecode(jsonStr);

        List<List<Map<String, dynamic>>> newBoard = [];
        for (var row in decoded) {
          List<Map<String, dynamic>> newRow = [];
          for (var cell in row) {
            newRow.add({
              'revealed': cell['revealed'] ?? false,
              'mine': cell['mine'] ?? false,
              'adj': cell['adj'] ?? 0,
              'flagged': cell['flagged'] ?? false,
            });
          }
          newBoard.add(newRow);
        }

        if (mounted) {
          setState(() {
            board = newBoard;
            _updateFlagCount();
          });
        }
        print('Board aggiornata: ${board.length}x${board.isNotEmpty ? board[0].length : 0}');
      }
      else if (msg.startsWith('GAME_INFO ')) {
        var parts = msg.split(' ');
        if (parts.length >= 2) {
          int mines = int.parse(parts[1]);
          if (mounted) {
            setState(() {
              totalMines = mines;
              _updateFlagCount();
            });
          }
          print('Mine totali: $totalMines');
        }
      }
      else if (msg == 'BOOM') {
        if (mounted) {
          showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                title: Text('BOOM!'),
                content: Text('Hai colpito una mina!\nLa partita è finita.'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      socket?.close();
                    },
                    child: Text('OK'),
                  )
                ],
              )
          );
        }
      }
      else if (msg == 'WIN') {
        if (mounted) {
          showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                title: Text('VITTORIA!'),
                content: Text('Avete vinto la partita!\nComplimenti!'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      socket?.close();
                    },
                    child: Text('OK'),
                  )
                ],
              )
          );
        }
      }
      else if (msg == 'NOT_YOUR_TURN') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Non è il tuo turno!'),
                duration: Duration(seconds: 1),
                backgroundColor: Colors.orange,
              )
          );
        }
      }
      else if (msg == 'WAITING') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⏳ In attesa del secondo giocatore...'),
                duration: Duration(seconds: 2),
              )
          );
        }
      }
    } catch (e, stackTrace) {
      print('Errore gestione messaggio "$msg": $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _updateFlagCount() {
    try {
      int flagsPlaced = 0;
      for (var row in board) {
        for (var cell in row) {
          if (cell['flagged'] == true) flagsPlaced++;
        }
      }
      flagsRemaining = totalMines - flagsPlaced;
    } catch (e) {
      print('Errore aggiornamento bandiere: $e');
    }
  }

  void revealCell(int r, int c) {
    try {
      socket?.write('REVEAL $r $c\n');
      print('Inviato: REVEAL $r $c');
    } catch (e) {
      print('Errore invio REVEAL: $e');
    }
  }

  void toggleFlag(int r, int c) {
    try {
      socket?.write('FLAG $r $c\n');
      print('Inviato: FLAG $r $c');
    } catch (e) {
      print('Errore invio FLAG: $e');
    }
  }

  @override
  void dispose() {
    socket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Errore'),
          backgroundColor: Colors.red,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red),
                SizedBox(height: 20),
                Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      errorMessage = '';
                    });
                    connectServer();
                  },
                  child: Text('Riprova'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    bool isMyTurn = playerNumber == currentTurn;

    return Scaffold(
      appBar: AppBar(
        title: Text('Campo Minato Cooperativo'),
        backgroundColor: Colors.deepPurple,
      ),
      body: board.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              connected ? 'Caricamento partita...' : 'Connessione al server...',
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      )
          : Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: isMyTurn ? Colors.green[100] : Colors.grey[200],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      'Giocatore',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      '$playerNumber',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'Turno',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.play_arrow,
                          color: isMyTurn ? Colors.green : Colors.grey,
                          size: 24,
                        ),
                        Text(
                          isMyTurn ? 'TUO' : 'P$currentTurn',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isMyTurn ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'Bandiere',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Row(
                      children: [
                        Text(
                          '🚩 ',
                          style: TextStyle(fontSize: 20),
                        ),
                        Text(
                          '$flagsRemaining',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: flagsRemaining > 0 ? Colors.red : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              boundaryMargin: EdgeInsets.all(50),
              minScale: 0.5,
              maxScale: 3.0,
              child: Center(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: board.isNotEmpty && board[0].isNotEmpty ? board[0].length : 1,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: board.isNotEmpty && board[0].isNotEmpty
                      ? board.length * board[0].length
                      : 0,
                  itemBuilder: (context, index) {
                    if (board.isEmpty || board[0].isEmpty) return SizedBox();

                    int r = index ~/ board[0].length;
                    int c = index % board[0].length;
                    var cell = board[r][c];

                    return GestureDetector(
                      onTap: (cell['revealed'] || cell['flagged']) ? null : () {
                        if (isMyTurn) {
                          revealCell(r, c);
                        }
                      },
                      onLongPress: cell['revealed'] ? null : () {
                        if (isMyTurn) {
                          toggleFlag(r, c);
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: cell['revealed']
                              ? Colors.grey[300]
                              : (cell['flagged'] ? Colors.orange[300] : Colors.blue[400]),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: Colors.black26,
                            width: 0.5,
                          ),
                          boxShadow: !cell['revealed'] ? [
                            BoxShadow(
                              color: Colors.black12,
                              offset: Offset(1, 1),
                              blurRadius: 1,
                            )
                          ] : null,
                        ),
                        child: Center(
                          child: cell['flagged']
                              ? Text('🚩', style: TextStyle(fontSize: 16))
                              : cell['revealed']
                              ? Text(
                            cell['mine'] ? '💣' : (cell['adj'] == 0 ? '' : '${cell['adj']}'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _getNumberColor(cell['adj']),
                            ),
                          )
                              : Text(''),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  'Tap: Rivela | ',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Icon(Icons.flag, size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  'Tieni premuto: Bandiera',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getNumberColor(int num) {
    switch (num) {
      case 1: return Colors.blue;
      case 2: return Colors.green;
      case 3: return Colors.red;
      case 4: return Colors.purple;
      case 5: return Colors.orange;
      case 6: return Colors.cyan;
      case 7: return Colors.brown;
      case 8: return Colors.black;
      default: return Colors.black;
    }
  }
}