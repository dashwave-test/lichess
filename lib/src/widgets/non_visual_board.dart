import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class NonVisualBoard extends StatefulWidget {
  const NonVisualBoard({
    required this.size,
    required this.fen,
    required this.orientation,
    required this.gameData,
    this.lastMove,
    this.shapes,
    required this.settings,
    this.boardOverlay,
    this.error,
    this.boardKey,
    super.key,
  });

  final double size;
  final String fen;
  final Side orientation;
  final GameData? gameData;
  final Move? lastMove;
  final ISet<Shape>? shapes;
  final ChessboardSettings settings;
  final String? error;
  final Widget? boardOverlay;
  final GlobalKey? boardKey;

  @override
  State<NonVisualBoard> createState() => _NonVisualBoardState();
}

class _NonVisualBoardState extends State<NonVisualBoard> {
  String? _lastAnnouncedSquare;
  String? _selectedSquare;
  Offset? _lastPanPosition;

  void _handleDrag(Offset localPosition) {
    _lastPanPosition = localPosition;
    final squareSize = widget.size / 8;
    final file = (widget.orientation == Side.white
            ? (localPosition.dx / squareSize)
            : 7 - (localPosition.dx / squareSize))
        .floor();
    final rank = (widget.orientation == Side.white
            ? 7 - (localPosition.dy / squareSize)
            : (localPosition.dy / squareSize))
        .floor();

    if (file < 0 || file > 7 || rank < 0 || rank > 7) {
      if (_selectedSquare != null) {
        SemanticsService.announce('Cancel selection', TextDirection.ltr);
      }
      _lastAnnouncedSquare = null;
      return;
    }

    final square = SQUARES[rank * 8 + file];
    if (square == _lastAnnouncedSquare) {
      return;
    }
    _lastAnnouncedSquare = square;

    if (_selectedSquare == null) {
      // Announce square info
      final piece = widget.gameData?.position.get(square);
      final pieceStr =
          piece != null ? '${piece.color.name} ${piece.role.name}' : 'empty';
      final announcement = '$square, $pieceStr';
      SemanticsService.announce(announcement, TextDirection.ltr);
    } else {
      // Announce move
      if (square == _selectedSquare) {
        SemanticsService.announce('Cancel selection', TextDirection.ltr);
        return;
      }
      final piece = widget.gameData?.position.get(_selectedSquare!);
      final destPiece = widget.gameData?.position.get(square);
      final moveStr = destPiece == null ? 'to' : 'takes';
      final announcement =
          '${piece?.role.name} $_selectedSquare $moveStr $square';
      SemanticsService.announce(announcement, TextDirection.ltr);
    }
  }

  void _onPanEnd() async {
    if (_lastPanPosition == null) return;
    final localPosition = _lastPanPosition!;
    _lastPanPosition = null;
    _lastAnnouncedSquare = null;

    final squareSize = widget.size / 8;
    final file = (widget.orientation == Side.white
            ? (localPosition.dx / squareSize)
            : 7 - (localPosition.dx / squareSize))
        .floor();
    final rank = (widget.orientation == Side.white
            ? 7 - (localPosition.dy / squareSize)
            : (localPosition.dy / squareSize))
        .floor();

    if (file < 0 || file > 7 || rank < 0 || rank > 7) {
      setState(() {
        _selectedSquare = null;
      });
      SemanticsService.announce('Selection cancelled', TextDirection.ltr);
      return;
    }

    final square = SQUARES[rank * 8 + file];

    if (_selectedSquare == null) {
      final piece = widget.gameData?.position.get(square);
      final playerSide = widget.gameData?.playerSide;
      if (piece != null &&
          playerSide != null &&
          piece.color == playerSide.toSide()) {
        setState(() {
          _selectedSquare = square;
        });
        final pieceStr = '${piece.color.name} ${piece.role.name}';
        SemanticsService.announce('$square, $pieceStr, selected',
            TextDirection.ltr);
      } else {
        SemanticsService.announce('Empty square or opponent piece',
            TextDirection.ltr);
      }
    } else {
      if (square == _selectedSquare) {
        setState(() {
          _selectedSquare = null;
        });
        SemanticsService.announce('Selection cancelled', TextDirection.ltr);
        return;
      }

      final from = _selectedSquare!;
      final to = square;
      final piece = widget.gameData!.position.get(from)!;
      final toRank = int.parse(to.substring(1));
      final isPromotion = piece.role == Role.pawn &&
          ((piece.color == Side.white && toRank == 8) ||
              (piece.color == Side.black && toRank == 1));

      Role? promotionRole;
      if (isPromotion) {
        promotionRole = await showDialog<Role>(
          context: context,
          builder: (context) => const _PromotionDialog(),
        );
        if (promotionRole == null) {
          // User cancelled promotion selection
          setState(() {
            _selectedSquare = null;
          });
          SemanticsService.announce('Selection cancelled', TextDirection.ltr);
          return;
        }
      }

      final uci = '$from$to${promotionRole?.char ?? ''}';
      final legalMoves = widget.gameData!.position.legalMoves();
      final isLegal = legalMoves.any((m) => m.uci == uci);

      if (isLegal) {
        final move = NormalMove.fromUCI(uci);
        widget.gameData?.onMove(move, isDrop: false);
      } else {
        SemanticsService.announce('Illegal move', TextDirection.ltr);
      }

      setState(() {
        _selectedSquare = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_selectedSquare != null) {
          setState(() {
            _selectedSquare = null;
          });
          SemanticsService.announce('Selection cancelled', TextDirection.ltr);
        }
      },
      onPanStart: (details) {
        _handleDrag(details.localPosition);
      },
      onPanUpdate: (details) {
        _handleDrag(details.localPosition);
      },
      onPanEnd: (details) {
        _onPanEnd();
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        color: Colors.grey,
        child: const Center(
          child: Text('Non-visual board'),
        ),
      ),
    );
  }
}

class _PromotionDialog extends StatelessWidget {
  const _PromotionDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: const Text('Promote to'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            child: const Text('Queen'),
            onPressed: () => Navigator.of(context).pop(Role.queen),
          ),
          TextButton(
            child: const Text('Rook'),
            onPressed: () => Navigator.of(context).pop(Role.rook),
          ),
          TextButton(
            child: const Text('Bishop'),
            onPressed: () => Navigator.of(context).pop(Role.bishop),
          ),
          TextButton(
            child: const Text('Knight'),
            onPressed: () => Navigator.of(context).pop(Role.knight),
          ),
        ],
      ),
    );
  }
}

extension on PlayerSide {
  Side toSide() {
    return this == PlayerSide.white ? Side.white : Side.black;
  }
}
