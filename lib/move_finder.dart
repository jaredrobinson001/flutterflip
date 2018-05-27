// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'game_board.dart';
import 'game_board_scorer.dart';

class MoveSearchArgs {
  MoveSearchArgs({this.board, this.player, this.numPlies});

  final GameBoard board;
  final PieceType player;
  final int numPlies;
}

/// A move and its score. Used by the minimax algorithm.
class ScoredMove {
  final int score;
  final Position move;

  const ScoredMove(this.score, this.move);
}

// The [compute] function requires a top-level method as its first argument.
// This is that method for [MoveFinder].
Position _findNextMove(MoveSearchArgs args) {
  ScoredMove bestMove = MoveFinder._performSearchPly(
      args.board, args.player, args.player, args.numPlies - 1);
  return bestMove.move;
}

/// The [MoveFinder] class exists to provide its [findNextMove] method, which
/// uses the minimax algorithm to look for the best available move on
/// [initialBoard] a [GameBoardScorer] to provide the heuristic.
class MoveFinder {
  final GameBoard initialBoard;
  final Completer<Position> completer = Completer<Position>();

  MoveFinder(this.initialBoard) : assert(initialBoard != null);

  /// Searches the tree of possible moves on [initialBoard] to a depth of
  /// [numPlies], looking for the best possible move for [player]. Because the
  /// actual work is done in an isolate, a [Future] is used as the return value.
  Future<Position> findNextMove(PieceType player, int numPlies) {
    return compute(
      _findNextMove,
      MoveSearchArgs(
        board: this.initialBoard,
        player: player,
        numPlies: numPlies,
      ),
    );
  }

  // This is a recursive implementation of minimax, an algorithm so old it has
  // its own Wikipedia page: https://wikipedia.org/wiki/Minimax.
  static ScoredMove _performSearchPly(GameBoard board, PieceType scoringPlayer,
      PieceType player, int pliesRemaining) {
    List<Position> availableMoves = board.getMovesForPlayer(player);

    if (availableMoves.length == 0) {
      return ScoredMove(0, null);
    }

    int score = (scoringPlayer == player)
        ? GameBoardScorer.minScore
        : GameBoardScorer.maxScore;
    ScoredMove bestMove;

    for (int i = 0; i < availableMoves.length; i++) {
      GameBoard newBoard =
          board.updateForMove(availableMoves[i].x, availableMoves[i].y, player);
      if (pliesRemaining > 0 &&
          newBoard.getMovesForPlayer(getOpponent(player)).length > 0) {
        // Opponent has next turn.
        score = _performSearchPly(newBoard, scoringPlayer, getOpponent(player),
                pliesRemaining - 1)
            .score;
      } else if (pliesRemaining > 0 &&
          newBoard.getMovesForPlayer(player).length > 0) {
        // Opponent has no moves; player gets another turn.
        score = _performSearchPly(
                newBoard, scoringPlayer, player, pliesRemaining - 1)
            .score;
      } else {
        // Game is over or the search has reached maximum depth.
        score = GameBoardScorer(newBoard).getScore(scoringPlayer);
      }

      if (bestMove == null ||
          (score > bestMove.score && scoringPlayer == player) ||
          (score < bestMove.score && scoringPlayer != player)) {
        bestMove = ScoredMove(
            score, Position(availableMoves[i].x, availableMoves[i].y));
      }
    }

    return bestMove;
  }
}
