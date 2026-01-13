# Campo minato Coop  

Campo Minato cooperativo a turni per 2 giocatori  

## Descrizione  

Campo Minato che permette a due giocatori di collegarsi a un server locale e giocare insieme in cooperativo. Ogni giocatore prende il turno per rivelare celle o piazzare bandiere, fino a quando tutte le celle senza mine sono rivelate o una mina viene scoperta.  
La comunicazione tra i 2 giocatori avviene tramite un socket TCP.  

## Architettura  

### Lato server:  
- Classe `Board`: rappresenta il campo di gioco, tiene conto delle celle scoperte, conta le celle bandierate e conta le mine adiacenti.
- Classe `GameServer`: gestisce le  connessioni dei client e la partita. Tiene traccia dei turni e dello stato della partita.  
- Classe `ClientHandler`: Collega un singolo socket al server. Legge i messaggi dal client (REVEAL / FLAG) e chiama i metodi di GameServer. Mantiene un buffer per gestire i messaggi frammentati.

### Lato Client:  
Nel `main.dart` vengono gestiti l'UI, la logica lato client e la connessione TCP  

## Flusso comunicazione  

1. Server avvia socket e aspetta 2 client.
2. Client si connette e riceve **Numero giocatore**, **Info partita**, **Stato iniziale board**.
3. Quando entrambi sono connessi, il server invia `TURN 1`.
4. Client 1 invia `REVEAL r c` al server che aggiorna board fa broadcast di board e del turno successivo.
5. Client 2 riceve l'aggiornamento di board e turno poi può giocare.
6. Ciclo continua fino a `WIN` o `BOOM`.

## Installazione  

non è possibile installare il gioco clonando la repository, si può fare solo copiando il codice ed incollandolo direttamente nel proprio progetto
