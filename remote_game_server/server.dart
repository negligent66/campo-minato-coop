import 'dart:io';
import 'dart:convert';
import 'dart:math';

class Cell {
  bool mine = false;
  bool revealed = false;
  bool flagged = false;
  int adjMines = 0;
}

class Board {
  int rows;
  int cols;
  int mines;
  late List<List<Cell>> grid;

  Board(this.rows, this.cols, this.mines) {
    grid = List.generate(rows, (_) => List.generate(cols, (_) => Cell()));
    _placeMines();
    _calculateAdjMines();
  }

  void _placeMines() {
    final rand = Random();
    int placed = 0;
    while (placed < mines) {
      int r = rand.nextInt(rows);
      int c = rand.nextInt(cols);
      if (!grid[r][c].mine) {
        grid[r][c].mine = true;
        placed++;
      }
    }
  }

  void _calculateAdjMines() {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (grid[r][c].mine) continue;
        int count = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            int nr = r + dr;
            int nc = c + dc;
            if (nr >= 0 && nr < rows &&
                nc >= 0 && nc < cols &&
                grid[nr][nc].mine) {
              count++;
            }
          }
        }
        grid[r][c].adjMines = count;
      }
    }
  }

  bool reveal(int r, int c) {
    if (r < 0 || r >= rows || c < 0 || c >= cols) return true;
    if (grid[r][c].revealed || grid[r][c].flagged) return true;
    
    grid[r][c].revealed = true;
    
    if (grid[r][c].mine) return false;

    if (grid[r][c].adjMines == 0) {
      for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
          if (dr == 0 && dc == 0) continue;
          int nr = r + dr;
          int nc = c + dc;
          if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
            reveal(nr, nc);
          }
        }
      }
    }
    return true;
  }

  bool toggleFlag(int r, int c) {
    if (r < 0 || r >= rows || c < 0 || c >= cols) return false;
    if (grid[r][c].revealed) return false;
    
    grid[r][c].flagged = !grid[r][c].flagged;
    return true;
  }

  bool checkWin() {
    for (var row in grid) {
      for (var cell in row) {
        if (!cell.mine && !cell.revealed) return false;
      }
    }
    return true;
  }

  String toJson() {
    try {
      List<List<Map<String, dynamic>>> data = [];
      for (var row in grid) {
        List<Map<String, dynamic>> rowData = [];
        for (var c in row) {
          rowData.add({
            'revealed': c.revealed,
            'mine': c.revealed ? c.mine : false,
            'adj': c.adjMines,
            'flagged': c.flagged
          });
        }
        data.add(rowData);
      }
      return jsonEncode(data);
    } catch (e) {
      print('Errore serializzazione board: $e');
      return '[]';
    }
  }
}

class GameServer {
  Board board;
  List<Socket> clients = [];
  int currentTurn = 1;
  bool gameStarted = false;

  GameServer(this.board);

  void addClient(Socket client) {
    try {
      clients.add(client);
      int playerNumber = clients.length;
      
      print('✓ Giocatore $playerNumber connesso da ${client.remoteAddress.address}');
      
      // Invia il numero del giocatore
      _safeSend(client, 'PLAYER_NUMBER $playerNumber\n');
      
      // Invia info sul gioco
      _safeSend(client, 'GAME_INFO ${board.mines}\n');
      
      // Invia la board
      _safeSend(client, 'BOARD_UPDATE ${board.toJson()}\n');
      
      if (clients.length == 2 && !gameStarted) {
        gameStarted = true;
        print('Partita iniziata! Turno del giocatore 1');
        broadcast('TURN $currentTurn');
      } else if (clients.length == 1) {
        _safeSend(client, 'WAITING\n');
        print('In attesa del secondo giocatore...');
      }
    } catch (e) {
      print('Errore aggiunta client: $e');
    }
  }

  void _safeSend(Socket client, String msg) {
  try {
    client.write(msg);
  } catch (e) {
    print('Errore invio messaggio: $e');
  }
}


  void handleReveal(Socket client, int r, int c) {
    try {
      int playerNumber = clients.indexOf(client) + 1;
      
      if (playerNumber <= 0) {
        print('Client non trovato nella lista');
        return;
      }
      
      if (!gameStarted) {
        _safeSend(client, 'WAITING\n');
        return;
      }
      
      if (playerNumber != currentTurn) {
        _safeSend(client, 'NOT_YOUR_TURN\n');
        print('Giocatore $playerNumber ha provato a giocare fuori turno');
        return;
      }

      print('Giocatore $playerNumber rivela [$r, $c]');
      bool alive = board.reveal(r, c);

      if (!alive) {
        print('Mina colpita dal giocatore $playerNumber');
        broadcast('BOARD_UPDATE ${board.toJson()}');
        broadcast('BOOM');
        gameStarted = false;
      } else if (board.checkWin()) {
        print('VITTORIA!');
        broadcast('BOARD_UPDATE ${board.toJson()}');
        broadcast('WIN');
        gameStarted = false;
      } else {
        // Cambia turno
        currentTurn = currentTurn == 1 ? 2 : 1;
        print('Turno passato al giocatore $currentTurn');
        
        broadcast('BOARD_UPDATE ${board.toJson()}');
        broadcast('TURN $currentTurn');
      }
    } catch (e) {
      print('Errore handleReveal: $e');
    }
  }

  void handleFlag(Socket client, int r, int c) {
    try {
      int playerNumber = clients.indexOf(client) + 1;
      
      if (playerNumber <= 0) {
        print('Client non trovato nella lista');
        return;
      }
      
      if (!gameStarted) {
        _safeSend(client, 'WAITING\n');
        return;
      }
      
      if (playerNumber != currentTurn) {
        _safeSend(client, 'NOT_YOUR_TURN\n');
        print('Giocatore $playerNumber ha provato a mettere bandiera fuori turno');
        return;
      }

      print('Giocatore $playerNumber bandiera [$r, $c]');
      bool changed = board.toggleFlag(r, c);
      
      if (changed) {
        // Cambia turno anche per le bandiere
        currentTurn = currentTurn == 1 ? 2 : 1;
        print('Turno passato al giocatore $currentTurn');
        
        broadcast('BOARD_UPDATE ${board.toJson()}');
        broadcast('TURN $currentTurn');
      }
    } catch (e) {
      print('Errore handleFlag: $e');
    }
  }

  void broadcast(String msg) {
  List<Socket> toRemove = [];
  
  for (var c in clients) {
    try {
      c.write(msg + '\n');
    } catch (e) {
      print('Errore broadcast a client: $e');
      toRemove.add(c);
    }
  }
  
  for (var c in toRemove) {
    removeClient(c);
  }
}


  void removeClient(Socket client) {
    try {
      clients.remove(client);
      print('Giocatore disconnesso. Clients rimanenti: ${clients.length}');
      
      if (clients.length < 2) {
        gameStarted = false;
        if (clients.isNotEmpty) {
          _safeSend(clients[0], 'WAITING\n');
          print('In attesa di un nuovo giocatore...');
        }
      }
    } catch (e) {
      print('Errore rimozione client: $e');
    }
  }
}

class ClientHandler {
  Socket socket;
  GameServer gameServer;
  String buffer = '';

  ClientHandler(this.socket, this.gameServer) {
    socket.listen(
      (data) {
        try {
          buffer += utf8.decode(data);
          
          while (buffer.contains('\n')) {
            int newlineIndex = buffer.indexOf('\n');
            String msg = buffer.substring(0, newlineIndex).trim();
            buffer = buffer.substring(newlineIndex + 1);
            
            if (msg.isNotEmpty) {
              handleMessage(msg);
            }
          }
        } catch (e) {
          print('Errore ricezione dati: $e');
        }
      },
      onError: (error) {
        print('Errore client: $error');
        gameServer.removeClient(socket);
      },
      onDone: () {
        print('Client disconnesso normalmente');
        gameServer.removeClient(socket);
      },
      cancelOnError: false,
    );
  }

  void handleMessage(String msg) {
    try {
      var parts = msg.split(' ');
      
      if (parts[0] == 'REVEAL' && parts.length == 3) {
        int r = int.parse(parts[1]);
        int c = int.parse(parts[2]);
        gameServer.handleReveal(socket, r, c);
      } else if (parts[0] == 'FLAG' && parts.length == 3) {
        int r = int.parse(parts[1]);
        int c = int.parse(parts[2]);
        gameServer.handleFlag(socket, r, c);
      } else {
        print('Comando sconosciuto: $msg');
      }
    } catch (e) {
      print('Errore parsing comando "$msg": $e');
    }
  }
}

void main() async {
  int port = 4040;
  try {
    final board = Board(16, 16, 40);
    final gameServer = GameServer(board);

    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    
    print('Server avviato sulla porta $port');

    server.listen((client) {
      print('\n→ Nuova connessione da ${client.remoteAddress.address}:${client.remotePort}');
      gameServer.addClient(client);
      ClientHandler(client, gameServer);
    });
  } catch (e) {
    print('ERRORE CRITICO: $e');
    exit(1);
  }

}
