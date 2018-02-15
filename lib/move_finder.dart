// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'gameboard.dart';
import 'gameboard_scorer.dart';

import 'dart:isolate';

enum MoveFinderResult { moveFound, noPossibleMove }
enum MoveFinderIsolateState { idle, loading, running }

class MoveFinderIsolateArguments {
  MoveFinderIsolateArguments(
      this.board, this.player, this.numPlies, this.sendPort);

  final GameBoard board;
  final PieceType player;
  final int numPlies;
  final SendPort sendPort;
}

class MoveFinderIsolateOutput {
  final MoveFinderResult result;
  final Position move;

  MoveFinderIsolateOutput(this.result, [this.move]);
}

class ScoredMove {
  final int score;
  final Position move;

  ScoredMove(this.score, this.move);
}

typedef void MoveFinderCompletionListener(MoveFinderResult result,
    [Position move]);

class MoveFinder {
  final GameBoard initialBoard;
  final MoveFinderCompletionListener listener;

  MoveFinderIsolateState _state = MoveFinderIsolateState.idle;

  bool get isRunning => _state != MoveFinderIsolateState.idle;

  final ReceivePort _receivePort;
  Isolate _isolate;

  MoveFinder(this.initialBoard, this.listener)
      : assert(listener != null),
        assert(initialBoard != null),
        _receivePort = new ReceivePort() {
    _receivePort.listen(_handleMessage);
  }

  void findNextMove(PieceType player, int numPlies) {
    if (!isRunning) {
      final MoveFinderIsolateArguments args = new MoveFinderIsolateArguments(
          initialBoard, player, numPlies, _receivePort.sendPort);

      _state = MoveFinderIsolateState.loading;

      Isolate.spawn(_isolateMain, args).then<Null>((Isolate isolate) {
        if (!isRunning) {
          isolate.kill(priority: Isolate.IMMEDIATE);
        } else {
          _state = MoveFinderIsolateState.running;
          _isolate = isolate;
        }
      });
    }
  }

  void cancelSearch() {
    if (isRunning) {
      _state = MoveFinderIsolateState.idle;
      if (_isolate != null) {
        _isolate.kill(priority: Isolate.IMMEDIATE);
        _isolate = null;
      }
    }
  }

  void _handleMessage(dynamic message) {
    if (message is MoveFinderIsolateOutput) {
      _state = MoveFinderIsolateState.idle;
      _isolate = null;
      listener(message.result, message.move);
    }
  }

  static ScoredMove _isolateRecursor(GameBoard board, PieceType scoringPlayer,
      PieceType player, int pliesRemaining) {
    List<Position> availableMoves = board.getMovesForPlayer(player);

    if (availableMoves.length == 0) {
      return new ScoredMove(0, null);
    }

    int score = (scoringPlayer == player) ? GameBoardScorer.minScore : GameBoardScorer.maxScore;
    ScoredMove bestMove;

    for (int i = 0; i < availableMoves.length; i++) {
      GameBoard newBoard =
          board.updateForMove(availableMoves[i].x, availableMoves[i].y, player);
      if (pliesRemaining > 0 &&
          newBoard.getMovesForPlayer(getOpponent(player)).length > 0) {
        // Opponent has next turn.
        score = _isolateRecursor(newBoard, scoringPlayer, getOpponent(player),
                pliesRemaining - 1)
            .score;
      } else if (pliesRemaining > 0 &&
          newBoard.getMovesForPlayer(player).length > 0) {
        // Opponent has no moves; player gets another turn.
        score = _isolateRecursor(
                newBoard, scoringPlayer, player, pliesRemaining - 1)
            .score;
      } else {
        // Game is over or the search has reached maximum depth.
        score = new GameBoardScorer(newBoard).getScore(scoringPlayer);
      }

      //print("[$pliesRemaining] : Considered $player at ${availableMoves[i].x},${availableMoves[i].y} for $score.");

      if (bestMove == null ||
          (score > bestMove.score && scoringPlayer == player) ||
          (score < bestMove.score && scoringPlayer != player)) {
        bestMove = new ScoredMove(score,
            new Position(x: availableMoves[i].x, y: availableMoves[i].y));
      }
    }

    //print("[$pliesRemaining] : Chose $player at ${bestMove.move.x},${bestMove.move.y} for ${bestMove.score}.");
    return bestMove;
  }

  static void _isolateMain(MoveFinderIsolateArguments args) {
    ScoredMove bestMove = _isolateRecursor(
        args.board, args.player, args.player, args.numPlies - 1);

    if (bestMove.move != null) {
      args.sendPort.send(new MoveFinderIsolateOutput(
          MoveFinderResult.moveFound, bestMove.move));
    } else {
      args.sendPort
          .send(new MoveFinderIsolateOutput(MoveFinderResult.noPossibleMove));
    }
  }
}
